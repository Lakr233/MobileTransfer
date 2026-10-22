//
//  Logout.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import ApplePackage
import ArgumentParser
import Foundation

struct Logout: ParsableCommand, Sendable {
    static let configuration = CommandConfiguration(
        commandName: "logout",
        abstract: "Logout from Apple account",
    )

    @Argument(help: "Email address")
    var email: String

    func run() throws {
        let fileURL = Configuration.accountPath(for: email)
        try FileManager.default.removeItem(at: fileURL)
        print("logged out \(email)")
    }
}
