//
//  Search.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import ApplePackage
import ArgumentParser
import Foundation

struct Search: AsyncParsableCommand, Sendable {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search for apps",
    )

    @Argument(help: "Search term")
    var term: String

    @Option(help: "Country code")
    var country: String = "US"

    @Option(help: "Limit")
    var limit: Int = 10

    @Option(help: "Platform to search: iPhone, iPad, or AppleTV")
    var platform: PlatformArgument = .iPhone

    func run() async throws {
        let results = try await Searcher.search(
            term: term,
            countryCode: country,
            limit: limit,
            entityType: platform.entityType,
        )
        for app in results {
            print("\(app.id) \(app.bundleID): \(app.name)")
        }
    }
}
