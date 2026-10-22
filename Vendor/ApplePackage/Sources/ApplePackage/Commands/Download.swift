//
//  Download.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import AsyncHTTPClient
import Foundation

public enum Download {
    public static func download(
        account: inout Account,
        app: Software,
        externalVersionID: String? = nil,
        entityType: EntityType = .iPhone,
    ) async throws -> DownloadOutput {
        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }

        let dict = try await StoreDownloadEndpoint.fetchProductWithFallback(
            client: client,
            account: &account,
            app: app,
            deviceIdentifier: Configuration.deviceIdentifier,
            externalVersionID: externalVersionID ?? "",
            entityType: entityType,
        )

        if let failureType = dict["failureType"] as? String {
            let customerMessage = dict["customerMessage"] as? String
            switch failureType {
            case "2034", "2042":
                try ensureFailed(Strings.passwordTokenExpired)
            case "9610":
                throw ApplePackageError.licenseRequired
            default:
                if customerMessage == Strings.passwordChanged {
                    try ensureFailed(Strings.passwordTokenExpired)
                }
                if let customerMessage {
                    try ensureFailed(customerMessage)
                }
                try ensureFailed("\(Strings.downloadFailed): \(failureType)")
            }
        }

        guard let items = dict["songList"] as? [[String: Any]], !items.isEmpty else {
            try ensureFailed(Strings.noItemsInResponse)
        }

        let item = items[0]
        guard let url = item["URL"] as? String else {
            try ensureFailed(Strings.missingDownloadURL)
        }

        guard var metadata = item["metadata"] as? [String: Any] else {
            try ensureFailed(Strings.missingMetadata)
        }

        let version = (metadata["bundleShortVersionString"] as? String)
        let bundleVersion = metadata["bundleVersion"] as? String

        guard let version, let bundleVersion else {
            try ensureFailed(Strings.missingRequiredInfo)
        }

        metadata["apple-id"] = account.email
        metadata["userName"] = account.email

        let iTunesMetadata = try PropertyListSerialization.data(
            fromPropertyList: metadata,
            format: .binary,
            options: 0,
        )

        var sinfs: [Sinf] = []
        if let sinfData = item["sinfs"] as? [[String: Any]] {
            for sinfItem in sinfData {
                if let id = sinfItem["id"] as? Int64,
                   let data = sinfItem["sinf"] as? Data
                {
                    sinfs.append(Sinf(id: id, sinf: data))
                } else {
                    try ensureFailed(Strings.invalidSinfItem)
                }
            }
        }
        try ensure(!sinfs.isEmpty, Strings.noSinfFound)

        return DownloadOutput(
            downloadURL: url,
            sinfs: sinfs,
            bundleShortVersionString: version,
            bundleVersion: bundleVersion,
            iTunesMetadata: iTunesMetadata,
        )
    }
}
