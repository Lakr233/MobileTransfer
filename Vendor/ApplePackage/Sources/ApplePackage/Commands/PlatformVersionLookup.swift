//
//  PlatformVersionLookup.swift
//  ApplePackage
//
//  Created by Codex on 2026/5/10.
//

import AsyncHTTPClient
import Foundation

public struct PlatformVersionMetadata: Equatable, Hashable {
    public var appID: Int64
    public var bundleID: String?
    public var name: String?
    public var displayVersion: String?
    public var externalVersionID: String
    public var buyParams: String?
}

public enum PlatformVersionLookup {
    public static func lookup(
        appID: Int64,
        countryCode: String,
        entityType: EntityType,
    ) async throws -> PlatformVersionMetadata {
        let client = Configuration.makeHTTPClient(redirectConfiguration: .follow(max: 8, allowCycles: false))
        defer { _ = client.shutdown() }

        let request = try makeRequest(appID: appID, countryCode: countryCode, entityType: entityType)
        let response = try await client.execute(request: request).get()

        try ensure(response.status == .ok, Strings.requestFailed(status: response.status.code))

        guard var body = response.body,
              let data = body.readData(length: body.readableBytes)
        else {
            try ensureFailed(Strings.responseBodyEmpty)
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let results = root["results"] as? [String: Any],
              let item = results["\(appID)"] as? [String: Any]
        else {
            try ensureFailed(Strings.invalidResponse)
        }

        guard let offers = item["offers"] as? [[String: Any]],
              let offer = offers.first
        else {
            try ensureFailed(Strings.noItemsInResponse)
        }

        let version = offer["version"] as? [String: Any]
        let buyParams = offer["buyParams"] as? String

        guard let externalVersionID = stringValue(version?["externalId"]) ?? externalVersionID(from: buyParams) else {
            try ensureFailed(Strings.missingVersionIdentifiers)
        }

        return PlatformVersionMetadata(
            appID: appID,
            bundleID: item["bundleId"] as? String,
            name: item["name"] as? String,
            displayVersion: version?["display"] as? String,
            externalVersionID: externalVersionID,
            buyParams: buyParams,
        )
    }

    private static func makeRequest(
        appID: Int64,
        countryCode: String,
        entityType: EntityType,
    ) throws -> HTTPClient.Request {
        let url = try createLookupURL(appID: appID, countryCode: countryCode, entityType: entityType)
        return try .init(
            url: url.absoluteString,
            method: .GET,
            headers: .init([("User-Agent", Configuration.userAgent)]),
            body: .none,
        )
    }

    private static func createLookupURL(
        appID: Int64,
        countryCode: String,
        entityType: EntityType,
    ) throws -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "uclient-api.itunes.apple.com"
        comps.path = "/WebObjects/MZStorePlatform.woa/wa/lookup"
        comps.queryItems = [
            URLQueryItem(name: "version", value: "2"),
            URLQueryItem(name: "id", value: "\(appID)"),
            URLQueryItem(name: "p", value: "mdm-lockup"),
            URLQueryItem(name: "caller", value: "MDM"),
            URLQueryItem(name: "platform", value: entityType.metadataPlatformValue),
            URLQueryItem(name: "cc", value: countryCode.lowercased()),
            URLQueryItem(name: "l", value: "en"),
        ]
        return try comps.url.get()
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            value
        case let value as Int:
            "\(value)"
        case let value as Int64:
            "\(value)"
        case let value as NSNumber:
            value.stringValue
        default:
            nil
        }
    }

    private static func externalVersionID(from buyParams: String?) -> String? {
        guard let buyParams,
              let comps = URLComponents(string: "applepackage://buy?\(buyParams)")
        else {
            return nil
        }
        return comps.queryItems?.first { $0.name == "appExtVrsId" }?.value
    }
}
