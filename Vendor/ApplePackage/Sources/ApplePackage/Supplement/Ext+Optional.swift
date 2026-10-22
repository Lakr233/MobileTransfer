//
//  Ext+Optional.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import Foundation

extension Optional {
    func get(_ error: String? = nil) throws -> Wrapped {
        guard let value = self else {
            try ensureFailed("\(error ?? "unexpected nil value")")
        }
        return value
    }
}
