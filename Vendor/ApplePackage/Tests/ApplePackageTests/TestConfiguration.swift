//
//  TestConfiguration.swift
//  ApplePackage
//

@testable import ApplePackage
import Foundation

/// Credential identity is derived when read; bootstrap has no shared write.
var testAccountEmail: String {
    TestConfiguration.email ?? ""
}

/// Central credential loader for test infrastructure.
/// Reads from environment variables with fallback to `/tmp/applepackage/*.txt` files.
enum TestConfiguration {
    private static let env = ProcessInfo.processInfo.environment

    static var email: String? {
        if let value = env["TEST_ACCOUNT_EMAIL"], !value.isEmpty {
            return value
        }
        return readFile("/tmp/applepackage/account.txt")
    }

    static var password: String? {
        if let value = env["TEST_ACCOUNT_PASSWORD"], !value.isEmpty {
            return value
        }
        return readFile("/tmp/applepackage/password.txt")
    }

    static var code: String? {
        if let value = env["TEST_ACCOUNT_CODE"], !value.isEmpty {
            return value
        }
        return readFile("/tmp/applepackage/code.txt")
    }

    static var deviceGUID: String? {
        if let value = env["TEST_DEVICE_GUID"], !value.isEmpty {
            return value
        }
        return nil
    }

    static var hasCredentials: Bool {
        email != nil && password != nil
    }

    static var hasAuthenticatedAccount: Bool {
        guard let email else { return false }
        let accountPath = Configuration.accountPath(for: email)
        return FileManager.default.fileExists(atPath: accountPath.path)
    }

    static var isCI: Bool {
        env["CI"] != nil
    }

    static func bootstrap() {
        if let guid = deviceGUID {
            Configuration.deviceIdentifier = guid
        } else if Configuration.deviceIdentifier.isEmpty {
            Configuration.deviceIdentifier = (try? DeviceIdentifier.system()) ?? DeviceIdentifier.random()
        }

        guard let email else { return }
        // Bootstrap account.json from TEST_ACCOUNT_DATA (base64) if no cached account exists
        if let base64Data = env["TEST_ACCOUNT_DATA"], !base64Data.isEmpty {
            let accountPath = Configuration.accountPath(for: email)
            if !FileManager.default.fileExists(atPath: accountPath.path),
               let data = Data(base64Encoded: base64Data)
            {
                try? FileManager.default.createDirectory(
                    at: accountPath.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                )
                try? data.write(to: accountPath)
                print("[TestConfiguration] bootstrapped account.json from TEST_ACCOUNT_DATA")
            }
        }
    }

    private static func readFile(_ path: String) -> String? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
