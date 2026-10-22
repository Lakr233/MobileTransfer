//
//  EntityType.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import Foundation

public enum EntityType: String, Codable, CaseIterable, Hashable, Equatable, Identifiable {
    public var id: Self {
        self
    }

    case iPhone
    case iPad
    case appleTV = "AppleTV"
}

extension EntityType {
    var entityValue: String {
        switch self {
        case .iPhone:
            "software"
        case .iPad:
            "iPadSoftware"
        case .appleTV:
            "tvSoftware"
        }
    }

    var searchEntityValue: String {
        switch self {
        case .iPhone, .iPad:
            entityValue
        case .appleTV:
            "software,tvSoftware"
        }
    }

    var metadataPlatformValue: String {
        switch self {
        case .iPhone, .iPad:
            "enterprisestore"
        case .appleTV:
            "atv9"
        }
    }
}
