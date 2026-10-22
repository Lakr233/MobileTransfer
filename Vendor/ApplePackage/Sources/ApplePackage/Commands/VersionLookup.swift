//
//  VersionLookup.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import AsyncHTTPClient
import Foundation

public enum VersionLookup {
    public static func getVersionMetadata(
        account: inout Account,
        app: Software,
        versionID: String,
    ) async throws -> VersionMetadata {
        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }

        let dict = try await StoreDownloadEndpoint.fetchProductWithFallback(
            client: client,
            account: &account,
            app: app,
            deviceIdentifier: Configuration.deviceIdentifier,
            externalVersionID: versionID,
        )

        guard let items = dict["songList"] as? [[String: Any]], !items.isEmpty else {
            try ensureFailed(Strings.noItemsInResponse)
        }

        let item = items[0]
        guard let metadata = item["metadata"] as? [String: Any] else {
            try ensureFailed(Strings.missingMetadata)
        }

        guard let bundleShortVersionString = metadata["bundleShortVersionString"] as? String else {
            try ensureFailed(Strings.missingBundleShortVersionString)
        }

        guard let releaseDateString = metadata["releaseDate"] as? String,
              let releaseDate = ISO8601DateFormatter().date(from: releaseDateString)
        else {
            try ensureFailed(Strings.missingOrInvalidReleaseDate)
        }

        return VersionMetadata(displayVersion: bundleShortVersionString, releaseDate: releaseDate)
    }
}
