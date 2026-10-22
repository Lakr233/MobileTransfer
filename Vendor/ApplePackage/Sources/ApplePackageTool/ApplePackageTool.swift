//
//  ApplePackageTool.swift
//  ApplePackageTool
//
//  Created by qaq on 9/15/25.
//

import ApplePackage
import ArgumentParser
import Foundation

enum PlatformArgument: String, ExpressibleByArgument, Sendable {
    case iPhone
    case iPad
    case AppleTV

    var entityType: EntityType {
        switch self {
        case .iPhone: .iPhone
        case .iPad: .iPad
        case .AppleTV: .appleTV
        }
    }
}

struct GlobalOptions: ParsableArguments, Sendable {
    @Option(
        name: .long, help: "Device GUID as 12 hexadecimal characters (default: system MAC address)",
        transform: { value in
            guard value.utf8.count == 12,
                  value.utf8.allSatisfy({ (48 ... 57).contains($0) || (65 ... 70).contains($0) || (97 ... 102).contains($0) })
            else { throw ValidationError("Device GUID must contain exactly 12 hexadecimal characters.") }
            return value.uppercased()
        },
    )
    var guid: String?

    @Flag(name: .shortAndLong, help: "Enable verbose logging of requests and responses")
    var verbose: Bool = false

    func apply() {
        if let guid {
            Configuration.deviceIdentifier = guid
        }
        if verbose {
            APLogger.verbose = true
            APLogger.logger.logLevel = .debug
        }
    }
}

@main
struct ApplePackageTool: AsyncParsableCommand, Sendable {
    static let configuration = CommandConfiguration(
        commandName: "applepackage", abstract: "A tool for managing Apple apps",
        subcommands: [Login.self, Logout.self, Search.self, Versions.self, Download.self],
    )
}
