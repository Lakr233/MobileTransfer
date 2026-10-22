//
//  StoreDownloadEndpoint.swift
//  ApplePackage
//
//  Created on 2026/6/12.
//

import Foundation

/// MZFinance product downloads use volumeStore first, then a version-pinned
/// redownload. An empty HTTP 500 can recover through the bag's update endpoint.
enum StoreDownloadEndpoint {
    case volumeStore
    case redownload
    case update

    /// The failureType returned by `volumeStore` that signals callers to retry
    /// with the `redownload` endpoint.
    static let retryableFailureType = "5002"

    /// The legacy dispatch endpoints use a different external version ID key.
    var externalVersionIDKey: String {
        switch self {
        case .volumeStore:
            "externalVersionId"
        case .redownload, .update:
            "appExtVrsId"
        }
    }

    func url(pod: String?, deviceIdentifier: String?) throws -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        switch self {
        case .volumeStore:
            comps.host = Configuration.storeAPIHost(pod: pod)
            comps.path = "/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct"
        case .redownload:
            comps.host = "downloaddispatch.itunes.apple.com"
            comps.path = "/r/redownload"
        case .update:
            comps.host = "downloaddispatch.itunes.apple.com"
            comps.path = "/up/updateProduct"
        }
        if let deviceIdentifier {
            comps.queryItems = [URLQueryItem(name: "guid", value: deviceIdentifier)]
        }
        return try comps.url.get()
    }

    static func validatedURL(_ url: URL) throws -> URL {
        let host = url.host?.lowercased() ?? ""
        let storeHost = host == "buy.itunes.apple.com" || host.range(of: #"^p[0-9]+-buy\.itunes\.apple\.com$"#, options: .regularExpression) != nil
        let storePath = ["/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct", "/WebObjects/MZFinance.woa/wa/redownloadProduct"].contains(url.path)
        let dispatchPath = ["/r/redownload", "/up/updateProduct"].contains(url.path)
        try ensure(
            url.scheme == "https" && url.user == nil && url.password == nil && url.fragment == nil
                && (url.port == nil || url.port == 443)
                && ((storeHost && storePath) || (host == "downloaddispatch.itunes.apple.com" && dispatchPath)),
            Strings.failedToRetrieveRedirect,
        )
        return url
    }
}
