//
//  SearchTests.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import AppKit
@testable import ApplePackage
import XCTest

final class ApplePackageSearchTests: XCTestCase {
    @MainActor func testSearch() async throws {
        do {
            let results = try await Searcher.search(term: "wechat", countryCode: "CN", limit: 5)
            XCTAssert(!results.isEmpty, "Search results should not be empty")
            for software in results {
                XCTAssert(!software.name.isEmpty, "Software name should not be empty")
                XCTAssert(!software.bundleID.isEmpty, "Software bundleID should not be empty")
                XCTAssert(software.id > 0, "Software ID should be positive")
            }
            print("Search test passed with \(results.count) results")
        } catch {
            XCTFail("Search failed: \(error)")
        }
    }

    @MainActor func testSearchInvalidCountry() async throws {
        do {
            _ = try await Searcher.search(term: "test", countryCode: "INVALID", limit: 1)
            XCTFail("Search should fail with invalid country code")
        } catch {
            // Expected to fail
            print("Search correctly failed with invalid country: \(error)")
        }
    }

    @MainActor func testSearchNoResults() async throws {
        do {
            let results = try await Searcher.search(term: "nonexistentapp123456789", countryCode: "US", limit: 5)
            XCTAssert(results.isEmpty, "Search should return empty for non-existent term")
            print("Search correctly returned no results")
        } catch {
            // Some APIs might return error instead of empty
            print("[?] Search for non-existent term: \(error)")
        }
    }
}
