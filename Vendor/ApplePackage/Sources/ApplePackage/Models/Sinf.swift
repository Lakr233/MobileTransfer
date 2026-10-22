//
//  Sinf.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import Foundation

public struct Sinf: Codable, Hashable, Equatable, Identifiable, Sendable {
    public var id: Int64
    public var sinf: Data

    public init(id: Int64, sinf: Data) {
        self.id = id
        self.sinf = sinf
    }
}
