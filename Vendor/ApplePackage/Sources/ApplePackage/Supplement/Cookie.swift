//
//  Cookie.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import AsyncHTTPClient
import Foundation

public struct Cookie: Sendable, Codable, Equatable, Hashable {
    public var name: String
    public var value: String
    public var path: String
    public var domain: String?
    public var expiresAt: TimeInterval?
    public var httpOnly: Bool
    public var secure: Bool

    public init(
        name: String,
        value: String,
        path: String,
        domain: String? = nil,
        expiresAt: TimeInterval? = nil,
        httpOnly: Bool,
        secure: Bool,
    ) {
        self.name = name
        self.value = value
        self.path = path
        self.domain = domain
        self.expiresAt = expiresAt
        self.httpOnly = httpOnly
        self.secure = secure
    }
}

public extension Cookie {
    init(copyFrom cookie: HTTPClient.Cookie) {
        let expires: TimeInterval? = if let maxAge = cookie.maxAge {
            Date().addingTimeInterval(.init(maxAge)).timeIntervalSince1970
        } else {
            nil
        }
        self.init(
            name: cookie.name,
            value: cookie.value,
            path: cookie.path,
            domain: cookie.domain,
            expiresAt: expires,
            httpOnly: cookie.httpOnly,
            secure: cookie.secure,
        )
    }
}

public extension [Cookie] {
    mutating func mergeCookies(_ cookies: [HTTPClient.Cookie]) {
        let cookies = cookies.map { Cookie(copyFrom: $0) }
        var dict: [String: Cookie] = [:]
        self.forEach { cookie in dict[cookie.name] = cookie }
        cookies.forEach { cookie in dict[cookie.name] = cookie }
        self = Array(dict.values)
    }

    func buildCookieHeader(_ endpoint: URL) -> [(String, String)] {
        guard let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true),
              let requestHost = components.host
        else {
            return []
        }

        let requestPath = components.path.isEmpty ? "/" : components.path
        let validCookies = filterValidCookies(
            for: endpoint,
            components: components,
            requestHost: requestHost,
            requestPath: requestPath,
        )

        guard !validCookies.isEmpty else {
            return []
        }

        let cookieHeader = validCookies.joined(separator: "; ")
        return [("Cookie", cookieHeader)]
    }

    private func filterValidCookies(
        for endpoint: URL,
        components: URLComponents,
        requestHost: String,
        requestPath: String,
    ) -> [String] {
        var validCookies: [String] = []

        for cookie in self {
            guard !cookie.name.isEmpty, !cookie.value.isEmpty else { continue }
            guard isValidCookie(
                cookie,
                for: endpoint,
                components: components,
                requestHost: requestHost,
                requestPath: requestPath,
            ) else { continue }
            validCookies.append("\(cookie.name)=\(cookie.value)")
        }

        return validCookies
    }

    private func isValidCookie(
        _ cookie: Cookie,
        for _: URL,
        components: URLComponents,
        requestHost: String,
        requestPath: String,
    ) -> Bool {
        if let cookieDomain = cookie.domain {
            guard matchesDomain(cookieDomain: cookieDomain, requestHost: requestHost) else {
                return false
            }
        }

        guard matchesPath(cookiePath: cookie.path, requestPath: requestPath) else {
            return false
        }

        if let expiresAt = cookie.expiresAt {
            guard expiresAt > Date().timeIntervalSince1970 else {
                return false
            }
        }

        if cookie.secure {
            guard components.scheme == "https" else { return false }
        }

        return true
    }

    private func matchesDomain(cookieDomain: String, requestHost: String) -> Bool {
        let normalizedCookieDomain = cookieDomain.lowercased()
        let normalizedRequestHost = requestHost.lowercased()

        return false
            || normalizedRequestHost == normalizedCookieDomain
            || normalizedRequestHost.hasSuffix("." + normalizedCookieDomain)
    }

    private func matchesPath(cookiePath: String, requestPath: String) -> Bool {
        if cookiePath == "/" {
            return true
        }
        if requestPath == cookiePath {
            return true
        }
        guard requestPath.hasPrefix(cookiePath) else { return false }

        let nextIndex = cookiePath.endIndex
        if nextIndex < requestPath.endIndex {
            let nextChar = requestPath[nextIndex]
            return cookiePath.hasSuffix("/") || nextChar == "/"
        }

        return true
    }
}
