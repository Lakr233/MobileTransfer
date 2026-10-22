//
//  AppStoreBackend.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import ApplePackage
import Foundation
import Observation
import Security

@Observable
class AppStoreBackend {
    struct Account: Codable, Identifiable, Equatable, CopyableCodable {
        var id: UUID = .init()

        var email: String
        var password: String
        var countryCode: String
        var appleAccount: ApplePackage.Account
    }

    @ObservationIgnored
    private var _accounts: [Account] = []
    var accounts: [Account] {
        get {
            access(keyPath: \.accounts)
            return _accounts
        }
        set {
            withMutation(keyPath: \.accounts) {
                _accounts = newValue
            }
        }
    }

    static let shared = AppStoreBackend()
    private init() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "tech.nootag.itm.AppStore", kSecAttrAccount as String: "accounts",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, let saved = try? JSONDecoder().decode([Account].self, from: data) {
            _accounts = saved
        }
        // Discard the legacy UserDefaults credential cache.
        UserDefaults.standard.removeObject(forKey: "AppStore.Accounts")
    }

    private func persist(_ value: [Account]) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "tech.nootag.itm.AppStore", kSecAttrAccount as String: "accounts"]
        let attributes = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        accounts = value
    }

    func save(email: String, password: String, appleAccount: ApplePackage.Account) throws {
        let countryCode = Configuration.countryCode(for: appleAccount.store) ?? "US"
        let updated = accounts
            .filter { $0.email.lowercased() != email.lowercased() }
            + [.init(email: email, password: password, countryCode: countryCode, appleAccount: appleAccount)]
        try persist(updated)
    }

    func delete(id: Account.ID) {
        try? persist(accounts.filter { $0.id != id })
    }

    func delete(email: String) {
        try? persist(accounts.filter { $0.email != email })
    }

    func updateAllAccountTokens() {
        assert(!Thread.isMainThread)
        let sem = DispatchSemaphore(value: 3)
        let group = DispatchGroup()
        let accounts = accounts
        for account in accounts where !account.password.isEmpty {
            group.enter()
            DispatchQueue.global().async {
                defer {
                    sem.signal()
                    group.leave()
                }

                let email = account.email
                let password = account.password
                let appleAccount: ApplePackage.Account? = {
                    let sem = DispatchSemaphore(value: 0)
                    var result: ApplePackage.Account?
                    Task {
                        defer { sem.signal() }
                        result = try? await Authenticator.authenticate(
                            email: email,
                            password: password,
                            code: "",
                            cookies: account.appleAccount.cookie
                        )
                    }
                    sem.wait()
                    return result
                }()

                guard let appleAccount else { return }

                DispatchQueue.main.asyncAndWait {
                    try? self.save(email: email, password: password, appleAccount: appleAccount)
                }
            }
            sem.wait()
        }
        group.wait()
    }
}
