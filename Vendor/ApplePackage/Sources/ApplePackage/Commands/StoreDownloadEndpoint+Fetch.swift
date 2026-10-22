//
//  StoreDownloadEndpoint+Fetch.swift
//  ApplePackage
//
//  Created on 2026/6/12.
//

import AsyncHTTPClient
import Foundation

extension StoreDownloadEndpoint {
    /// Preserve the version across the bounded volumeStore, redownload, and update chain.
    static func fetchProductWithFallback(
        client: HTTPClient,
        account: inout Account,
        app: Software,
        deviceIdentifier: String,
        externalVersionID: String,
        entityType: EntityType = .iPhone,
    ) async throws -> [String: Any] {
        let dict = try await StoreDownloadEndpoint.volumeStore.fetchProduct(
            client: client,
            account: &account,
            app: app,
            deviceIdentifier: deviceIdentifier,
            externalVersionID: externalVersionID,
        )

        guard requiresRedownload(dict) else { return dict }
        APLogger.debug("store: volumeStore returned no package, trying redownload")
        var version = externalVersionID
        if version.isEmpty {
            guard let country = Configuration.countryCode(for: account.store) else {
                try ensureFailed(Strings.unsupportedStoreIdentifier(account.store))
            }
            version = try await PlatformVersionLookup.lookup(appID: app.id, countryCode: country, entityType: entityType).externalVersionID
        }
        let bag = try? await Bag.fetchBag()
        do {
            let response = try await StoreDownloadEndpoint.redownload.fetchProduct(
                client: client,
                account: &account,
                app: app,
                deviceIdentifier: deviceIdentifier,
                externalVersionID: version,
                endpointURL: bag?.redownloadEndpoint,
            )
            return try validateRecoveryResponse(response, app: app, version: version)
        } catch let error as StoreDownloadHTTPError {
            guard error.statusCode == 500, error.emptyBody, !version.isEmpty,
                  let updateEndpoint = bag?.updateEndpoint
            else { throw error }
            APLogger.debug("store: redownload returned an empty HTTP 500, trying updateProduct")
            let response = try await StoreDownloadEndpoint.update.fetchProduct(
                client: client, account: &account, app: app, deviceIdentifier: deviceIdentifier,
                externalVersionID: version, endpointURL: updateEndpoint,
            )
            return try validateRecoveryResponse(response, app: app, version: version)
        }
    }

    static func validateRecoveryResponse(_ response: [String: Any], app: Software, version: String) throws -> [String: Any] {
        if let failure = response["failureType"], !String(describing: failure).isEmpty {
            return response
        }
        guard (response["customerMessage"] as? String ?? "").isEmpty,
              response["dialog"] == nil, response["action"] == nil,
              let items = response["songList"] as? [[String: Any]], items.count == 1,
              let metadata = items.first?["metadata"] as? [String: Any],
              metadata["itemId"].map({ String(describing: $0) }) == String(app.id),
              metadata["softwareVersionExternalIdentifier"].map({ String(describing: $0) }) == version,
              metadata["softwareVersionBundleId"] as? String == app.bundleID
        else { try ensureFailed(Strings.invalidResponse) }
        return response
    }

    static func requiresRedownload(_ response: [String: Any]) -> Bool {
        let failure = response["failureType"].map { String(describing: $0) } ?? ""
        if failure == retryableFailureType {
            return true
        }
        guard failure.isEmpty, (response["customerMessage"] as? String ?? "").isEmpty,
              response["dialog"] == nil, response["action"] == nil,
              response["status"] == nil || (response["status"] as? NSNumber)?.intValue == 0
        else { return false }
        if let items = response["songList"] as? [Any] {
            return items.isEmpty
        }
        return response["songList"] == nil
    }

    /// Runs the product request against this endpoint, following pod redirects,
    /// and returns the parsed plist response.
    func fetchProduct(
        client: HTTPClient,
        account: inout Account,
        app: Software,
        deviceIdentifier: String,
        externalVersionID: String,
        endpointURL: URL? = nil,
    ) async throws -> [String: Any] {
        var currentURL = try url(pod: account.pod, deviceIdentifier: deviceIdentifier)
        if let endpointURL, var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "guid", value: deviceIdentifier)]
            currentURL = try components.url.get()
        }
        var redirectAttempt = 0
        var finalResponse: HTTPClient.Response?
        let maxRedirects = 3

        while redirectAttempt <= maxRedirects {
            currentURL = try Self.validatedURL(currentURL)
            let request = try makeRequest(
                account: account,
                app: app,
                url: currentURL,
                guid: deviceIdentifier,
                externalVersionID: externalVersionID,
            )
            let response = try await client.execute(request: request).get()
            defer { finalResponse = response }

            APLogger.logResponse(
                status: response.status.code,
                headers: response.headers.map { ($0.name, $0.value) },
                bodySize: response.body?.readableBytes,
            )

            account.cookie.mergeCookies(response.cookies)

            if [301, 302, 303, 307, 308].contains(response.status.code) {
                guard let location = response.headers.first(name: "location"),
                      let newURL = URL(string: location, relativeTo: currentURL)?.absoluteURL,
                      redirectAttempt < maxRedirects
                else {
                    try ensureFailed(Strings.failedToRetrieveRedirect)
                }
                currentURL = newURL
                redirectAttempt += 1
                continue
            }
            break
        }

        guard let finalResponse else { try ensureFailed(Strings.noResponseReceived) }

        guard finalResponse.status == .ok else {
            throw StoreDownloadHTTPError(statusCode: finalResponse.status.code, emptyBody: (finalResponse.body?.readableBytes ?? 0) == 0)
        }

        guard var body = finalResponse.body,
              let data = body.readData(length: body.readableBytes)
        else {
            try ensureFailed(Strings.responseBodyEmpty)
        }

        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil,
        ) as? [String: Any]
        guard let dict = plist else { try ensureFailed(Strings.invalidResponse) }

        return dict
    }

    private func makeRequest(
        account: Account,
        app: Software,
        url: URL,
        guid: String,
        externalVersionID: String,
    ) throws -> HTTPClient.Request {
        var payload: [String: Any] = [
            "creditDisplay": "",
            "guid": guid,
            "salableAdamId": app.id,
            "serialNumber": "0",
        ]

        if !externalVersionID.isEmpty {
            payload[externalVersionIDKey] = externalVersionID
        }

        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)

        var headers: [(String, String)] = [
            ("Content-Type", "application/x-apple-plist"),
            ("User-Agent", Configuration.userAgent),
            ("iCloud-DSID", account.directoryServicesIdentifier),
            ("X-Dsid", account.directoryServicesIdentifier),
        ]

        for item in account.cookie.buildCookieHeader(url) {
            headers.append(item)
        }

        APLogger.logRequest(method: "POST", url: url.absoluteString, headers: headers)

        return try .init(
            url: url,
            method: .POST,
            headers: .init(headers),
            body: .data(data),
        )
    }
}

struct StoreDownloadHTTPError: LocalizedError {
    let statusCode: UInt
    let emptyBody: Bool

    var errorDescription: String? {
        Strings.requestFailed(status: statusCode)
    }
}
