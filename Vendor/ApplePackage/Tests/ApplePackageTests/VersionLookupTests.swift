//
//  VersionLookupTests.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import AppKit
@testable import ApplePackage
import XCTest

final class ApplePackageVersionLookupTests: XCTestCase {
    override class func setUp() {
        TestConfiguration.bootstrap()
    }

    @MainActor func testGetVersionMetadata() async throws {
        try XCTSkipUnless(TestConfiguration.hasAuthenticatedAccount, "No authenticated account available")

        let testBundleID = "com.tencent.xin"
        let testVersionID = "850481143"
        do {
            try await withAccount(email: testAccountEmail) { @Sendable account in
                let app = try await Lookup.lookup(bundleID: testBundleID, countryCode: "CN")
                let metadata = try await VersionLookup.getVersionMetadata(account: &account, app: app, versionID: testVersionID)
                print("version metadata test passed: \(metadata.displayVersion) - \(metadata.releaseDate)")
            }
        } catch {
            XCTFail("get version metadata test failed: \(error)")
        }
    }

    @MainActor func testGetVersionMetadataInvalidVersion() async throws {
        try XCTSkipUnless(TestConfiguration.hasAuthenticatedAccount, "No authenticated account available")

        let testBundleID = "com.tencent.xin"
        do {
            try await withAccount(email: testAccountEmail) { @Sendable account in
                let app = try await Lookup.lookup(bundleID: testBundleID, countryCode: "CN")
                _ = try await VersionLookup.getVersionMetadata(account: &account, app: app, versionID: "invalid")
                XCTFail("should fail with invalid version ID")
            }
        } catch {
            // good
        }
    }
}
