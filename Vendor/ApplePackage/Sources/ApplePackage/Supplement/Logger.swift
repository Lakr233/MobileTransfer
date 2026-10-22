//
//  Logger.swift
//  ApplePackage
//
//  Created on 2026/2/20.
//

import Foundation
import Logging

public enum APLogger {
    private struct State: Sendable {
        var verbose = false
        var logger = Logger(label: "com.applepackage")
    }

    private static let state = LockedState(State())

    public static var verbose: Bool {
        get { state.withLock { $0.verbose } }
        set { state.withLock { $0.verbose = newValue } }
    }

    public static var logger: Logger {
        get { state.withLock { $0.logger } }
        set { state.withLock { $0.logger = newValue } }
    }

    static func info(_ message: String) {
        logger.info("\(message)")
    }

    static func debug(_ message: String) {
        let snapshot = state.withLock { ($0.verbose, $0.logger) }
        guard snapshot.0 else { return }
        snapshot.1.debug("\(message)")
    }

    static func error(_ message: String) {
        logger.error("\(message)")
    }

    static func logRequest(method: String, url: String, headers: [(String, String)] = []) {
        guard verbose else { return }
        var msg = ">>> \(method) \(safeURL(url))"
        for (name, value) in headers {
            let safeValue = safeHeaderValue(name: name, value: value)
            msg += "\n    \(name): \(safeValue)"
        }
        debug(msg)
    }

    static func logResponse(status: UInt, headers: [(String, String)] = [], bodySize: Int? = nil) {
        guard verbose else { return }
        var msg = "<<< \(status)"
        if let bodySize {
            msg += " (\(bodySize) bytes)"
        }
        for (name, value) in headers {
            msg += "\n    \(name): \(safeHeaderValue(name: name, value: value))"
        }
        debug(msg)
    }

    static func safeHeaderValue(name: String, value: String) -> String {
        let publicHeaders: Set = ["accept", "content-type", "content-length", "user-agent", "cache-control"]
        return publicHeaders.contains(name.lowercased()) ? value : "<redacted>"
    }

    static func safeURL(_ text: String) -> String {
        guard let url = URL(string: text), let scheme = url.scheme, let host = url.host else { return "<redacted>" }
        return "\(scheme)://\(host)\(url.path)"
    }
}
