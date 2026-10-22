//
//  VersionMetadata.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import Foundation

public struct VersionMetadata: Codable, Equatable, Hashable, Sendable {
    public var displayVersion: String
    public var releaseDate: Date

    public init(displayVersion: String, releaseDate: Date) {
        self.displayVersion = displayVersion
        self.releaseDate = releaseDate
    }
}
