//
//  Ensure.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import Foundation

func ensure(_ condition: Bool, _ error: String) throws {
    guard condition else { try ensureFailed(error) }
}

func ensureFailed(_ error: String) throws -> Never {
    throw NSError(
        domain: #function,
        code: 1,
        userInfo: [
            NSLocalizedDescriptionKey: error,
        ],
    )
}
