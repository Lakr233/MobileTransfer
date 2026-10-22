//
//  Bag.swift
//  ApplePackage
//
//  Created on 2026/2/20.
//

import AsyncHTTPClient
import Foundation

public enum Bag {
    public struct BagOutput {
        public var authEndpoint: URL
        public var redownloadEndpoint: URL?
        public var updateEndpoint: URL?
    }

    private static let defaultAuthEndpoint = "https://auth.itunes.apple.com/auth/v1/native/fast/"

    public static func fetchBag(
        redirectConfiguration: HTTPClient.Configuration.RedirectConfiguration = .follow(max: 8, allowCycles: false),
    ) async throws -> BagOutput {
        let deviceIdentifier = Configuration.deviceIdentifier

        let client = Configuration.makeHTTPClient(redirectConfiguration: redirectConfiguration)
        defer { _ = client.shutdown() }

        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "init.itunes.apple.com"
        comps.path = "/bag.xml"
        comps.queryItems = [URLQueryItem(name: "guid", value: deviceIdentifier)]
        guard let url = comps.url else {
            APLogger.debug("bag: failed to construct URL, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        let headers: [(String, String)] = [
            ("User-Agent", Configuration.userAgent),
            ("Accept", "application/xml"),
        ]

        APLogger.logRequest(method: "GET", url: url.absoluteString, headers: headers)

        let request = try HTTPClient.Request(
            url: url.absoluteString,
            method: .GET,
            headers: .init(headers),
        )

        let response = try await client.execute(request: request).get()

        APLogger.logResponse(
            status: response.status.code,
            headers: response.headers.map { ($0.name, $0.value) },
            bodySize: response.body?.readableBytes,
        )

        guard var body = response.body,
              let data = body.readData(length: body.readableBytes)
        else {
            APLogger.debug("bag: empty response body, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        return parse(data)
    }

    static func parse(_ data: Data) -> BagOutput {
        let plistData = extractPlistData(from: data)

        guard
            let plist = try? PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil,
            ) as? [String: Any]
        else {
            APLogger.debug("bag: failed to parse plist, using default auth endpoint")
            return BagOutput(authEndpoint: URL(string: defaultAuthEndpoint)!)
        }

        // authenticateAccount used to live inside the nested urlBag dict,
        // newer bag responses move it to the plist root
        let urlBag = plist["urlBag"] as? [String: Any] ?? [:]
        let authURLString = (plist["authenticateAccount"] as? String) ?? (urlBag["authenticateAccount"] as? String)

        let authURL = authURLString.flatMap(normalizedAuthEndpoint) ?? URL(string: defaultAuthEndpoint)!
        if authURLString == nil {
            APLogger.debug("bag: no authenticateAccount in plist, using default auth endpoint")
        }

        APLogger.info("bag: auth endpoint resolved to \(APLogger.safeURL(authURL.absoluteString))")
        return BagOutput(
            authEndpoint: authURL,
            redownloadEndpoint: downloadEndpoint(plist["redownloadProduct"] ?? urlBag["redownloadProduct"], path: "/r/redownload"),
            updateEndpoint: downloadEndpoint(plist["updateProduct"] ?? urlBag["updateProduct"], path: "/up/updateProduct"),
        )
    }

    private static func downloadEndpoint(_ value: Any?, path: String) -> URL? {
        guard let value = value as? String, let url = URL(string: value),
              url.scheme == "https", url.host == "downloaddispatch.itunes.apple.com",
              url.path == path, url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, url.query == nil, url.fragment == nil
        else { return nil }
        return url
    }

    /// The bag advertises the native auth endpoint without the `/fast/` sub-path
    /// that the login flow requires; the no-trailing-slash variant 301s to an
    /// HTML page. The legacy authenticate route also requires its trailing
    /// slash; the bare route can return a bodyless 301 without Location.
    static func normalizedAuthEndpoint(from urlString: String) -> URL? {
        guard var comps = URLComponents(string: urlString) else { return nil }
        if comps.host == "auth.itunes.apple.com" {
            var path = comps.path
            while path.hasSuffix("/") {
                path.removeLast()
            }
            if !path.hasSuffix("/fast") {
                path += "/fast"
            }
            comps.path = path + "/"
        } else if comps.scheme?.lowercased() == "https", let host = comps.host?.lowercased() {
            let legacyHost =
                host == "buy.itunes.apple.com" || host.range(of: "^p[0-9]+-buy[.]itunes[.]apple[.]com$", options: .regularExpression) != nil
            if legacyHost, comps.path == "/WebObjects/MZFinance.woa/wa/authenticate" {
                comps.path += "/"
            }
        }
        return comps.url
    }

    /// The bag XML response wraps the plist inside `<Document><Protocol><plist>...</plist>`.
    /// Extract the `<plist>...</plist>` portion so PropertyListSerialization can parse it.
    /// If the data is already a bare plist, return it as-is.
    private static func extractPlistData(from data: Data) -> Data {
        guard let xmlString = String(data: data, encoding: .utf8),
              let startRange = xmlString.range(of: "<plist"),
              let endRange = xmlString.range(of: "</plist>")
        else {
            return data
        }
        return Data(xmlString[startRange.lowerBound ..< endRange.upperBound].utf8)
    }
}
