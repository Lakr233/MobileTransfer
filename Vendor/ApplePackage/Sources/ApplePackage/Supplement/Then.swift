//
//  Then.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import AsyncHTTPClient
import Foundation

extension HTTPClient.Configuration {
    func then(_ configure: (inout Self) -> Void) -> Self {
        var copy = self
        configure(&copy)
        return copy
    }
}
