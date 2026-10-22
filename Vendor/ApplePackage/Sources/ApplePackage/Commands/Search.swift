//
//  Search.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import AsyncHTTPClient
import Foundation

public enum Searcher {
    private struct SearchResponse: Codable {
        var resultCount: Int
        var results: [Software]
    }

    public static func search(
        term: String,
        countryCode: String,
        limit: Int = 5,
        entityType: EntityType = .iPhone,
    ) async throws -> [Software] {
        let client = Configuration.makeHTTPClient(redirectConfiguration: .follow(max: 8, allowCycles: false))
        defer { _ = client.shutdown() }

        let request = try makeRequest(
            term: term,
            countryCode: countryCode,
            limit: limit,
            entityType: entityType,
        )
        let response = try await client.execute(request: request).get()

        try ensure(response.status == .ok, "search request failed with status \(response.status.code)")
        guard var body = response.body,
              let data = body.readData(length: body.readableBytes)
        else {
            try ensureFailed("response body is empty")
        }

        let decoder = JSONDecoder()
        let searchResponse = try decoder.decode(SearchResponse.self, from: data)
        return searchResponse.results
    }

    private static func makeRequest(
        term: String,
        countryCode: String,
        limit: Int,
        entityType: EntityType,
    ) throws -> HTTPClient.Request {
        let url = try createSearchURL(
            term: term,
            countryCode: countryCode,
            limit: limit,
            entityType: entityType,
        )
        return try .init(
            url: url.absoluteString,
            method: .GET,
            headers: .init([("User-Agent", Configuration.userAgent)]),
            body: .none,
        )
    }

    private static func createSearchURL(
        term: String,
        countryCode: String,
        limit: Int,
        entityType: EntityType,
    ) throws -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "itunes.apple.com"
        comps.path = "/search"
        comps.queryItems = [
            URLQueryItem(name: "entity", value: entityType.searchEntityValue),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "media", value: "software"),
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: countryCode),
        ]
        return try comps.url.get()
    }
}
