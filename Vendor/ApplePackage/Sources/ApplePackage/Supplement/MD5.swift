//
//  MD5.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import CryptoKit
import Foundation

public extension String {
    /// Lowercase hex MD5 digest, used to derive stable on-disk account paths.
    var md5: String {
        Insecure.MD5.hash(data: Data(utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
