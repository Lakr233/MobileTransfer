//
//  AccountTests.swift
//  ApplePackage
//
//  Created on 2026/2/20.
//

@testable import ApplePackage
import XCTest

final class ApplePackageAccountTests: XCTestCase {
    func testAccountCodableWithPod() throws {
        let account = Account(
            email: "test@example.com",
            password: "pass",
            appleId: "123",
            store: "143441",
            firstName: "John",
            lastName: "Doe",
            passwordToken: "token",
            directoryServicesIdentifier: "ds123",
            cookie: [],
            pod: "42",
        )
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        XCTAssertEqual(decoded.pod, "42")
        XCTAssertEqual(decoded.email, "test@example.com")
    }

    func testAccountCodableWithoutPod() throws {
        let account = Account(
            email: "test@example.com",
            password: "pass",
            appleId: "123",
            store: "143441",
            firstName: "John",
            lastName: "Doe",
            passwordToken: "token",
            directoryServicesIdentifier: "ds123",
            cookie: [],
        )
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        XCTAssertNil(decoded.pod)
    }

    func testAccountBackwardCompatibility() throws {
        // Simulate an old account.json without the pod field
        let json = """
        {
            "email": "test@example.com",
            "password": "pass",
            "appleId": "123",
            "store": "143441",
            "firstName": "John",
            "lastName": "Doe",
            "passwordToken": "token",
            "directoryServicesIdentifier": "ds123",
            "cookie": []
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        XCTAssertNil(decoded.pod)
        XCTAssertEqual(decoded.email, "test@example.com")
        XCTAssertEqual(decoded.store, "143441")
    }

    func testAccountValidationInit() throws {
        let appleId: String? = "123"
        let account = try Account(
            email: "test@example.com",
            password: "pass",
            appleId: appleId,
            store: "143441",
            firstName: "John" as String?,
            lastName: "Doe" as String?,
            passwordToken: "token" as String?,
            directoryServicesIdentifier: "ds123" as String?,
            cookie: [],
            pod: "99",
        )
        XCTAssertEqual(account.pod, "99")
    }

    func testAccountValidationInitEmptyEmail() {
        let appleId: String? = "123"
        XCTAssertThrowsError(
            try Account(
                email: "",
                password: "pass",
                appleId: appleId,
                store: "143441",
                firstName: "John" as String?,
                lastName: "Doe" as String?,
                passwordToken: "token" as String?,
                directoryServicesIdentifier: "ds123" as String?,
                cookie: [],
            ),
        )
    }

    func testAccountValidationInitEmptyPassword() {
        let appleId: String? = "123"
        XCTAssertThrowsError(
            try Account(
                email: "test@example.com",
                password: "",
                appleId: appleId,
                store: "143441",
                firstName: "John" as String?,
                lastName: "Doe" as String?,
                passwordToken: "token" as String?,
                directoryServicesIdentifier: "ds123" as String?,
                cookie: [],
            ),
        )
    }

    func testAccountValidationInitUnsupportedStore() {
        let appleId: String? = "123"
        XCTAssertThrowsError(
            try Account(
                email: "test@example.com",
                password: "pass",
                appleId: appleId,
                store: "999999",
                firstName: "John" as String?,
                lastName: "Doe" as String?,
                passwordToken: "token" as String?,
                directoryServicesIdentifier: "ds123" as String?,
                cookie: [],
            ),
        )
    }

    func testAccountValidationInitNilAppleId() {
        XCTAssertThrowsError(
            try Account(
                email: "test@example.com",
                password: "pass",
                appleId: nil,
                store: "143441",
                firstName: "John" as String?,
                lastName: "Doe" as String?,
                passwordToken: "token" as String?,
                directoryServicesIdentifier: "ds123" as String?,
                cookie: [],
            ),
        )
    }
}
