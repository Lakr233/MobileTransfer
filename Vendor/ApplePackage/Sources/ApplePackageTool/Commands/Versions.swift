//
//  Versions.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import ApplePackage
import ArgumentParser
import Foundation

struct Versions: AsyncParsableCommand, Sendable {
    static let configuration = CommandConfiguration(
        commandName: "versions",
        abstract: "List versions of an app",
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Argument(help: "Email address")
    var email: String

    @Argument(help: "Bundle ID")
    var bundleID: String

    @Option(help: "Platform to list versions for: iPhone, iPad, or AppleTV")
    var platform: PlatformArgument?

    @Option(help: "Seed version ID used to select a platform-specific version line")
    var versionID: String?

    func run() async throws {
        globalOptions.apply()
        try await Configuration.withAccount(email: email) { account in
            try await Authenticator.rotatePasswordToken(for: &account)
            let versions = try await VersionFinder.list(
                account: &account,
                bundleIdentifier: bundleID,
                entityType: platform?.entityType,
                externalVersionID: versionID,
            )
            for version in versions {
                print(version)
            }
        }
    }
}
