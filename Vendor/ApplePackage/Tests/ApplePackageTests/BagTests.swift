//
//  BagTests.swift
//  ApplePackage
//
//  Created on 2026/2/20.
//

@testable import ApplePackage
import XCTest

final class ApplePackageBagTests: XCTestCase {
    @MainActor func testFetchBag() async throws {
        do {
            let output = try await Bag.fetchBag()
            let urlString = output.authEndpoint.absoluteString
            XCTAssertFalse(urlString.isEmpty, "Auth endpoint URL should not be empty")
            XCTAssertTrue(urlString.hasPrefix("https://"), "Auth endpoint should use HTTPS")
            print("bag test passed: auth endpoint = \(urlString)")
        } catch {
            XCTFail("fetch bag failed: \(error)")
        }
    }

    @MainActor func testFetchBagReturnsValidEndpoint() async throws {
        do {
            let output = try await Bag.fetchBag()
            let url = output.authEndpoint
            XCTAssertNotNil(url.host, "Auth endpoint should have a host")
            XCTAssertNotNil(url.scheme, "Auth endpoint should have a scheme")
        } catch {
            XCTFail("fetch bag failed: \(error)")
        }
    }
}
