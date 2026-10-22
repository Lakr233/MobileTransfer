//
//  VersionFinder.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import AsyncHTTPClient
import Foundation

public enum VersionFinder {
    public static func list(
        account: inout Account,
        bundleIdentifier: String,
        entityType: EntityType? = nil,
        externalVersionID: String? = nil,
    ) async throws -> [String] {
        guard let countryCode = Configuration.countryCode(for: account.store) else {
            try ensureFailed(Strings.unsupportedStoreIdentifier(account.store))
        }
        let app = try await Lookup.lookup(bundleID: bundleIdentifier, countryCode: countryCode, entityType: entityType)
        let resolvedExternalVersionID: String
        if let externalVersionID {
            resolvedExternalVersionID = externalVersionID
        } else if let entityType {
            let metadata = try await PlatformVersionLookup.lookup(
                appID: app.id,
                countryCode: countryCode,
                entityType: entityType,
            )
            resolvedExternalVersionID = metadata.externalVersionID
        } else {
            resolvedExternalVersionID = ""
        }

        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }

        let dict = try await StoreDownloadEndpoint.fetchProductWithFallback(
            client: client,
            account: &account,
            app: app,
            deviceIdentifier: Configuration.deviceIdentifier,
            externalVersionID: resolvedExternalVersionID,
            entityType: entityType ?? .iPhone,
        )

        guard let items = dict["songList"] as? [[String: Any]], !items.isEmpty else {
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
                    try ensureFailed(Strings.noItemsInResponse)
                }
            } else {
                try ensureFailed(Strings.noItemsInResponse)
            }
        }

        let item = items[0]
        guard let metadata = item["metadata"] as? [String: Any],
              let identifiers = metadata["softwareVersionExternalIdentifiers"] as? [Any]
        else {
            try ensureFailed(Strings.missingVersionIdentifiers)
        }

        let result = identifiers.map { "\($0)" }
        try ensure(!result.isEmpty, Strings.noVersionsFound)

        return result
    }
}
