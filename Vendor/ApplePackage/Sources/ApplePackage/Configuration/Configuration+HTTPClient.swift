//
//  Configuration+HTTPClient.swift
//  ApplePackage
//
//  Created on 2026/6/12.
//

import AsyncHTTPClient
import Foundation

extension Configuration {
    /// Shared HTTP/1.1-only client used by all store requests.
    /// Callers own the returned client and must shut it down.
    static func makeHTTPClient(
        redirectConfiguration: HTTPClient.Configuration.RedirectConfiguration,
    ) -> HTTPClient {
        HTTPClient(
            eventLoopGroupProvider: .singleton,
            configuration: .init(
                tlsConfiguration: tlsConfiguration,
                redirectConfiguration: redirectConfiguration,
                timeout: .init(
                    connect: .seconds(timeoutConnect),
                    read: .seconds(timeoutRead),
                ),
            ).then { $0.httpVersion = .http1Only },
        )
    }
}
