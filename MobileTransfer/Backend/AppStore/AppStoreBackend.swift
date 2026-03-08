//
//  AppStoreBackend.swift
//  MobileTransfer
//
//  Created by 秋星桥 on 2024/9/25.
//

import ApplePackage
import Foundation
import Observation

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
    private var _accounts = StoredValue(key: "AppStore.Accounts", defaultValue: [Account]())
    var accounts: [Account] {
        get {
            access(keyPath: \.accounts)
            return _accounts.get()
        }
        set {
            withMutation(keyPath: \.accounts) {
                _accounts.set(newValue)
            }
        }
    }

    static let shared = AppStoreBackend()
    private init() {}

    func save(email: String, password: String, appleAccount: ApplePackage.Account) {
        let countryCode = Configuration.countryCode(for: appleAccount.store) ?? "US"
        accounts = accounts
            .filter { $0.email.lowercased() != email.lowercased() }
            + [.init(email: email, password: password, countryCode: countryCode, appleAccount: appleAccount)]
    }

    func delete(id: Account.ID) {
        accounts = accounts.filter { $0.id != id }
    }

    func delete(email: String) {
        accounts = accounts.filter { $0.email != email }
    }

    func updateAllAccountTokens() {
        assert(!Thread.isMainThread)
        let sem = DispatchSemaphore(value: 3)
        let group = DispatchGroup()
        let accounts = accounts
        for account in accounts {
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
                    self.save(email: email, password: password, appleAccount: appleAccount)
                }
            }
            sem.wait()
        }
        group.wait()
    }
}
