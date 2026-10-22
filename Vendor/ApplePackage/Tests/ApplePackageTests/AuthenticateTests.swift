//
//  AuthenticateTests.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import AppKit
@testable import ApplePackage
import XCTest

final class ApplePackageAuthenticateTests: XCTestCase {
    override class func setUp() {
        TestConfiguration.bootstrap()
    }

    @MainActor
    func testRotatePasswordToken() async throws {
        try XCTSkipUnless(TestConfiguration.hasAuthenticatedAccount, "No authenticated account available")
        try await withAccount(email: testAccountEmail) { @Sendable account in try await Authenticator.rotatePasswordToken(for: &account) }
    }

    @MainActor
    func testAuthenticate() async throws {
        try XCTSkipUnless(TestConfiguration.hasCredentials, "No test credentials available")

        let email = try XCTUnwrap(TestConfiguration.email)
        let password = try XCTUnwrap(TestConfiguration.password)
        let code = TestConfiguration.code ?? ""

        let result = try await Authenticator.authenticate(email: email, password: password, code: code)
        saveLoginAccount(result, for: email)
    }

    @MainActor
    func testLogin() async throws {
        try XCTSkipIf(TestConfiguration.isCI, "Login requires interactive 2FA, skipping in CI")
        try XCTSkipUnless(TestConfiguration.hasCredentials, "No test credentials available")

        let email = try XCTUnwrap(TestConfiguration.email)
        let password = try XCTUnwrap(TestConfiguration.password)
        var code = TestConfiguration.code ?? ""

        let fileManager = FileManager.default
        let loginAccountPath = "/tmp/applepackage/login_account.txt"
        if fileManager.fileExists(atPath: loginAccountPath) {
            print("login account file exists at \(loginAccountPath), rotating token instead")
            try await withAccount(email: email) { @Sendable account in try await Authenticator.rotatePasswordToken(for: &account) }
            return
        }

        let session = try await Authenticator()
        do {
            let result = try await session.authenticate(email: email, password: password, code: code)
            saveLoginAccount(result, for: email)
        } catch AuthenticationError.verificationCodeRequired {
            let alert = NSAlert()
            alert.messageText = "Apple Package Auth Failed"
            alert.informativeText = "Please fill out the verification code you received on your device."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()

            // Re-read code from file after user interaction
            if let updatedCode = TestConfiguration.code {
                code = updatedCode
            }
            XCTAssert(!code.isEmpty)
            do {
                let result = try await session.authenticate(email: email, password: password, code: code)
                saveLoginAccount(result, for: email)
            } catch { XCTFail("second attempt failed: \(error)") }
        }
    }
}
