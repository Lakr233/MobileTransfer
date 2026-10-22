//
//  DownloadTests.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import AppKit
@testable import ApplePackage
import XCTest
import ZIPFoundation

final class ApplePackageDownloadTests: XCTestCase {
    override class func setUp() {
        TestConfiguration.bootstrap()
    }

    @MainActor func testDownload() async throws {
        try XCTSkipUnless(TestConfiguration.hasAuthenticatedAccount, "No authenticated account available")

        let testBundleID = "developer.apple.wwdc-Release"
        do {
            try await withAccount(email: testAccountEmail) { @Sendable account in
                try await Authenticator.rotatePasswordToken(for: &account)
                let countryCode = Configuration.countryCode(for: account.store) ?? "US"
                let app = try await Lookup.lookup(bundleID: testBundleID, countryCode: countryCode)
                let output = try await Download.download(account: &account, app: app)
                print("download test passed: \(output.downloadURL)")
                print("    Bundle Short Version: \(output.bundleShortVersionString)")
                print("    Bundle Version: \(output.bundleVersion)")
                print("    SINFs count: \(output.sinfs.count)")
                print("    iTunesMetadata size: \(output.iTunesMetadata.count) bytes")

                XCTAssertFalse(output.downloadURL.isEmpty, "Download URL should not be empty")
                XCTAssertNotNil(output.bundleShortVersionString, "Bundle short version should not be nil")
                XCTAssertGreaterThan(output.sinfs.count, 0, "Should have at least one SINF")
                XCTAssertGreaterThan(output.iTunesMetadata.count, 0, "iTunesMetadata should not be empty")

                let metadata = try PropertyListSerialization.propertyList(
                    from: output.iTunesMetadata,
                    options: [],
                    format: nil,
                ) as? [String: Any]
                XCTAssertNotNil(metadata, "iTunesMetadata should be a valid plist")
                XCTAssertEqual(metadata?["apple-id"] as? String, account.email, "apple-id should match account email")
                XCTAssertEqual(metadata?["userName"] as? String, account.email, "userName should match account email")
            }
        } catch {
            XCTFail("download test failed: \(error)")
        }
    }

    @MainActor func testDownloadAndAssembleIPA() async throws {
        try XCTSkipUnless(TestConfiguration.hasAuthenticatedAccount, "No authenticated account available")

        let testBundleID = "developer.apple.wwdc-Release"
        let tempDir = FileManager.default.temporaryDirectory
        let ipaURL = tempDir.appendingPathComponent("test_download_\(UUID().uuidString).ipa")

        defer { try? FileManager.default.removeItem(at: ipaURL) }

        try await withAccount(email: testAccountEmail) { @Sendable account in
            try await Authenticator.rotatePasswordToken(for: &account)
            let countryCode = Configuration.countryCode(for: account.store) ?? "US"
            let app = try await Lookup.lookup(bundleID: testBundleID, countryCode: countryCode)
            let output = try await Download.download(account: &account, app: app)

            // Download IPA
            let url = URL(string: output.downloadURL)!
            let (data, response) = try await URLSession.shared.data(from: url)
            let httpResponse = response as! HTTPURLResponse
            XCTAssertTrue(200 ... 299 ~= httpResponse.statusCode, "Download should succeed")
            try data.write(to: ipaURL)

            // Inject sinfs + metadata
            try await SignatureInjector.inject(
                sinfs: output.sinfs,
                iTunesMetadata: output.iTunesMetadata,
                into: ipaURL.path,
            )

            // Verify IPA contents
            let archive = try Archive(url: ipaURL, accessMode: .read)

            var hasSinf = false
            var hasMetadata = false
            for entry in archive {
                if entry.path.contains("SC_Info/"), entry.path.hasSuffix(".sinf") {
                    hasSinf = true
                }
                if entry.path == "iTunesMetadata.plist" {
                    hasMetadata = true
                    var metadataData = Data()
                    _ = try archive.extract(entry, consumer: { metadataData.append($0) })
                    let plist = try PropertyListSerialization.propertyList(
                        from: metadataData,
                        options: [],
                        format: nil,
                    ) as? [String: Any]
                    XCTAssertNotNil(plist, "iTunesMetadata.plist should be a valid plist")
                    XCTAssertEqual(plist?["apple-id"] as? String, account.email)
                    XCTAssertEqual(plist?["userName"] as? String, account.email)
                    print("    iTunesMetadata.plist keys: \(plist?.keys.sorted() ?? [])")
                }
            }

            XCTAssertTrue(hasSinf, "IPA should contain SINF files")
            XCTAssertTrue(hasMetadata, "IPA should contain iTunesMetadata.plist")
            print("IPA assembly test passed: \(ipaURL.lastPathComponent)")
        }
    }
}
