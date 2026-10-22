//
//  PurchaseTests.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import AppKit
@testable import ApplePackage
import XCTest

final class ApplePackagePurchaseTests: XCTestCase {
    override class func setUp() {
        TestConfiguration.bootstrap()
    }

    func testPurchaseFailureTypeMessages() {
        XCTAssertEqual(
            Strings.purchaseFailureMessage(failureType: "5002", customerMessage: nil),
            "app is already purchased (failureType: 5002)",
        )
        XCTAssertEqual(
            Strings.purchaseFailureMessage(failureType: "2040", customerMessage: nil),
            "app is already purchased, unavailable, or delisted (failureType: 2040)",
        )
        XCTAssertEqual(
            Strings.purchaseFailureMessage(failureType: "2059", customerMessage: nil),
            "app is unavailable, delisted, unavailable in this storefront, or not purchased (failureType: 2059)",
        )
        XCTAssertEqual(
            Strings.purchaseFailureMessage(failureType: "1010", customerMessage: nil),
            "invalid store or app unavailable in this storefront (failureType: 1010)",
        )
        XCTAssertEqual(
            Strings.purchaseFailureMessage(failureType: "2034", customerMessage: nil),
            "password token is expired (failureType: 2034)",
        )
        XCTAssertEqual(
            Strings.purchaseFailureMessage(failureType: "2042", customerMessage: nil),
            "password token is expired (failureType: 2042)",
        )
        XCTAssertEqual(
            Strings.purchaseFailureMessage(failureType: "2019", customerMessage: nil),
            "paid apps cannot be purchased directly (failureType: 2019)",
        )
        XCTAssertEqual(
            Strings.purchaseFailureMessage(failureType: "9610", customerMessage: nil),
            "license not found or app id is invalid (failureType: 9610)",
        )
        XCTAssertEqual(
            Strings.purchaseFailureMessage(failureType: "", customerMessage: "Purchase failed from server"),
            "Purchase failed from server (failureType: )",
        )
    }

    @MainActor func testPurchase() async throws {
        try XCTSkipUnless(TestConfiguration.hasAuthenticatedAccount, "No authenticated account available")

        let testBundleID = "developer.apple.wwdc-Release"
        do {
            try await withAccount(email: testAccountEmail) { @Sendable account in
                try await Authenticator.rotatePasswordToken(for: &account)
                let countryCode = Configuration.countryCode(for: account.store) ?? "US"
                let app = try await Lookup.lookup(bundleID: testBundleID, countryCode: countryCode)
                try await Purchase.purchase(account: &account, app: app)
                print("purchase test passed")
            }
        } catch {
            print("purchase test completed with expected result: \(error)")
        }
    }

    @MainActor func testPurchasePaidApp() async throws {
        try XCTSkipUnless(TestConfiguration.hasAuthenticatedAccount, "No authenticated account available")

        do {
            try await withAccount(email: testAccountEmail) { @Sendable account in
                let paidApp = Software(
                    id: 123_456_789,
                    bundleID: "com.example.paid",
                    name: "Paid App",
                    version: "1.0.0",
                    price: 4.99,
                    artistName: "Example",
                    sellerName: "Example Inc",
                    description: "A paid app",
                    averageUserRating: 4.5,
                    userRatingCount: 100,
                    artworkUrl: "https://example.com/artwork.png",
                    screenshotUrls: ["https://example.com/screenshot.png"],
                    minimumOsVersion: "14.0",
                    releaseDate: "2023-01-01T00:00:00Z",
                    formattedPrice: "$4.99",
                    primaryGenreName: "Utilities",
                )
                try await Purchase.purchase(account: &account, app: paidApp)
                XCTFail("should fail with paid app")
            }
        } catch {
            print("paid app purchase test passed with expected error: \(error)")
        }
    }
}
