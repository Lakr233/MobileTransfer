//
//  Accounts.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import Foundation

public func saveLoginAccount(_ account: Account, for email: String) {
    let fileURL = Configuration.accountPath(for: email)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let data = try! encoder.encode(account)
    try? FileManager.default.removeItem(at: fileURL)
    try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data.write(to: fileURL)
}

public func withAccount<T>(email: String, _ body: (inout Account) async throws -> T) async throws -> T {
    var account: Account = try {
        let fileURL = Configuration.accountPath(for: email)
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Account.self, from: data)
    }()
    defer { saveLoginAccount(account, for: email) }
    return try await body(&account)
}
