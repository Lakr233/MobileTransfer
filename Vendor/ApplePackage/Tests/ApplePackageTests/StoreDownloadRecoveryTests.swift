@testable import ApplePackage
import Foundation
import Testing

struct StoreDownloadRecoveryTests {
    @Test
    func `download endpoints survive missing authentication endpoint`() throws {
        let endpoints = [
            "redownloadProduct": "https://downloaddispatch.itunes.apple.com/r/redownload",
            "updateProduct": "https://downloaddispatch.itunes.apple.com/up/updateProduct",
        ]
        let bags: [[String: Any]] = [endpoints, ["urlBag": endpoints]]
        for contents in bags {
            let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
            let bag = Bag.parse(data)
            #expect(bag.redownloadEndpoint?.absoluteString == endpoints["redownloadProduct"])
            #expect(bag.updateEndpoint?.absoluteString == endpoints["updateProduct"])
        }
    }

    @Test
    func `rejects unapproved download endpoints`() throws {
        for endpoint in [
            "http://downloaddispatch.itunes.apple.com/up/updateProduct",
            "https://downloaddispatch.itunes.apple.com.example.invalid/up/updateProduct",
            "https://user:password@downloaddispatch.itunes.apple.com/up/updateProduct",
            "https://downloaddispatch.itunes.apple.com/up/updateProduct?redirect=other",
            "https://downloaddispatch.itunes.apple.com/r/redownload",
        ] {
            let data = try PropertyListSerialization.data(fromPropertyList: ["urlBag": ["updateProduct": endpoint]], format: .xml, options: 0)
            #expect(Bag.parse(data).updateEndpoint == nil)
        }
    }

    @Test
    func `recovers empty responses but preserves explicit failures`() {
        let recoverable: [[String: Any]] = [[:], ["songList": [], "status": 0], ["failureType": 5002]]
        for response in recoverable {
            #expect(StoreDownloadEndpoint.requiresRedownload(response))
        }
        let failures: [[String: Any]] = [
            ["failureType": "9610"], ["status": -1], ["customerMessage": "Rejected"],
            ["dialog": [:]], ["songList": "invalid"], ["songList": [["metadata": [:]]]],
        ]
        for response in failures {
            #expect(!StoreDownloadEndpoint.requiresRedownload(response))
        }
    }

    @Test
    func `recovery must match the requested package`() throws {
        let app = Software(id: 123, bundleID: "example.app", name: "Fixture", version: "1.0",
                           artistName: "", sellerName: "", description: "", averageUserRating: 0,
                           userRatingCount: 0, artworkUrl: "", screenshotUrls: [], minimumOsVersion: "15.0",
                           releaseDate: "", primaryGenreName: "")
        let metadata: [String: Any] = ["itemId": 123, "softwareVersionExternalIdentifier": 456, "softwareVersionBundleId": "example.app"]
        let response: [String: Any] = ["songList": [["metadata": metadata]]]
        _ = try StoreDownloadEndpoint.validateRecoveryResponse(response, app: app, version: "456")
        for field in metadata.keys {
            var mismatched = metadata
            mismatched[field] = "wrong"
            #expect(throws: (any Error).self) {
                try StoreDownloadEndpoint.validateRecoveryResponse(["songList": [["metadata": mismatched]]], app: app, version: "456")
            }
        }
    }
}
