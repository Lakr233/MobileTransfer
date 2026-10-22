//
//  LookupTests.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import AppKit
@testable import ApplePackage
import XCTest

final class ApplePackageLookupTests: XCTestCase {
    @MainActor func testLookup() async throws {
        do {
            let item = "com.tencent.xin"
            let software = try await Lookup.lookup(bundleID: item, countryCode: "CN")
            XCTAssert(software.bundleID == item, "bundle identifier should match")
            XCTAssert(!software.name.isEmpty, "software name should not be empty")
            print(software)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    @MainActor func testLookupInvalidBundle() async throws {
        do {
            let software = try await Lookup.lookup(bundleID: "com.apple.invalid.bundle.id", countryCode: "US")
            XCTFail("should not find software, but got: \(software)")
        } catch {
            // good
        }
    }

    @MainActor func testAppleTVPlatformVersionLookup() async throws {
        let metadata = try await PlatformVersionLookup.lookup(
            appID: 544_007_664,
            countryCode: "US",
            entityType: .appleTV,
        )

        XCTAssertEqual(metadata.bundleID, "com.google.ios.youtube")
        XCTAssertFalse(metadata.externalVersionID.isEmpty)
        XCTAssertFalse(metadata.displayVersion?.isEmpty ?? true)
    }
}
