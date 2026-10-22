//
//  ConfigurationTests.swift
//  ApplePackage
//
//  Created on 2026/2/20.
//

@testable import ApplePackage
import XCTest

final class ApplePackageConfigurationTests: XCTestCase {
    // MARK: - storeAPIHost

    func testStoreAPIHostWithPod() {
        let host = Configuration.storeAPIHost(pod: "42")
        XCTAssertEqual(host, "p42-buy.itunes.apple.com")
    }

    func testStoreAPIHostWithNilPod() {
        let host = Configuration.storeAPIHost(pod: nil)
        XCTAssertEqual(host, "p25-buy.itunes.apple.com")
    }

    func testStoreAPIHostWithEmptyPod() {
        let host = Configuration.storeAPIHost(pod: "")
        XCTAssertEqual(host, "p25-buy.itunes.apple.com")
    }

    // MARK: - purchaseAPIHost

    func testPurchaseAPIHostWithPod() {
        let host = Configuration.purchaseAPIHost(pod: "42")
        XCTAssertEqual(host, "p42-buy.itunes.apple.com")
    }

    func testPurchaseAPIHostWithNilPod() {
        let host = Configuration.purchaseAPIHost(pod: nil)
        XCTAssertEqual(host, "buy.itunes.apple.com")
    }

    func testPurchaseAPIHostWithEmptyPod() {
        let host = Configuration.purchaseAPIHost(pod: "")
        XCTAssertEqual(host, "buy.itunes.apple.com")
    }

    // MARK: - Country code

    func testCountryCodeRoundTrip() {
        let storeId = Configuration.storeId(for: "US")
        XCTAssertEqual(storeId, "143441")
        let countryCode = Configuration.countryCode(for: "143441")
        XCTAssertEqual(countryCode, "US")
    }

    func testCountryCodeForUnknownStore() {
        let countryCode = Configuration.countryCode(for: "999999")
        XCTAssertNil(countryCode)
    }
}
