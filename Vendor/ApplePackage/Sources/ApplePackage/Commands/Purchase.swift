//
//  Purchase.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import AsyncHTTPClient
import Foundation

public enum Purchase {
    public static func purchase(
        account: inout Account,
        app: Software,
    ) async throws {
        let deviceIdentifier = Configuration.deviceIdentifier

        if (app.price ?? 0) > 0 {
            try ensureFailed(Strings.paidAppsNotSupported)
        }

        do {
            try await purchaseWithParams(account: &account, app: app, guid: deviceIdentifier, pricingParameters: "STDQ")
        } catch let error as NSError {
            if error.localizedDescription.contains("failureType: 2059") ||
                error.localizedDescription.contains(Strings.itemTemporarilyUnavailable)
            {
                try await purchaseWithParams(account: &account, app: app, guid: deviceIdentifier, pricingParameters: "GAME")
            } else {
                throw error
            }
        }
    }

    private static func purchaseWithParams(
        account: inout Account,
        app: Software,
        guid: String,
        pricingParameters: String,
    ) async throws {
        APLogger.debug("purchase: using pricing parameters: \(pricingParameters)")

        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }

        let request = try makeRequest(
            account: account,
            app: app,
            guid: guid,
            pricingParameters: pricingParameters,
        )
        let response = try await client.execute(request: request).get()

        APLogger.logResponse(
            status: response.status.code,
            headers: response.headers.map { ($0.name, $0.value) },
            bodySize: response.body?.readableBytes,
        )

        account.cookie.mergeCookies(response.cookies)

        try ensure(response.status == .ok, Strings.requestFailed(status: response.status.code))

        guard var body = response.body,
              let data = body.readData(length: body.readableBytes)
        else {
            try ensureFailed(Strings.responseBodyEmpty)
        }

        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil,
        ) as? [String: Any]
        guard let dict = plist else { try ensureFailed(Strings.invalidResponse) }

        // Check if Apple requires the user to accept terms in a browser
        if let action = dict["action"] as? [String: Any],
           let urlString = (action["url"] as? String) ?? (action["URL"] as? String),
           urlString.hasSuffix("termsPage")
        {
            try ensureFailed(Strings.termsAcceptanceRequired(url: urlString))
        }

        if let failureType = dict["failureType"] as? String {
            let customerMessage = dict["customerMessage"] as? String
            switch failureType {
            case "2034", "2042":
                try ensureFailed(Strings.purchaseFailureMessage(failureType: failureType, customerMessage: customerMessage))
            default:
                if customerMessage == Strings.passwordChanged {
                    try ensureFailed(Strings.passwordTokenExpired)
                }
                if let customerMessage {
                    if customerMessage == "Subscription Required" {
                        try ensureFailed(Strings.subscriptionRequired)
                    }
                }
                try ensureFailed(Strings.purchaseFailureMessage(failureType: failureType, customerMessage: customerMessage))
            }
        }

        if let jingleDocType = dict["jingleDocType"] as? String,
           let status = dict["status"] as? Int
        {
            try ensure(jingleDocType == "purchaseSuccess" && status == 0, Strings.failedToPurchase)
        } else {
            try ensureFailed(Strings.invalidPurchaseResponse)
        }
    }

    private static func makeRequest(
        account: Account,
        app: Software,
        guid: String,
        pricingParameters: String,
    ) throws -> HTTPClient.Request {
        let payload: [String: Any] = [
            "appExtVrsId": "0",
            "hasAskedToFulfillPreorder": "true",
            "buyWithoutAuthorization": "true",
            "hasDoneAgeCheck": "true",
            "guid": guid,
            "needDiv": "0",
            "origPage": "Software-\(app.id)",
            "origPageLocation": "Buy",
            "price": "0",
            "pricingParameters": pricingParameters,
            "productType": "C",
            "salableAdamId": app.id,
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)

        var headers: [(String, String)] = [
            ("Content-Type", "application/x-apple-plist"),
            ("User-Agent", Configuration.userAgent),
            ("iCloud-DSID", account.directoryServicesIdentifier),
            ("X-Dsid", account.directoryServicesIdentifier),
            ("X-Apple-Store-Front", "\(account.store)-1"),
            ("X-Token", account.passwordToken),
        ]

        let host = Configuration.purchaseAPIHost(pod: account.pod)
        let urlString = "https://\(host)/WebObjects/MZFinance.woa/wa/buyProduct"

        for item in account.cookie.buildCookieHeader(URL(string: urlString)!) {
            headers.append(item)
        }

        APLogger.logRequest(method: "POST", url: urlString, headers: headers)

        return try .init(
            url: urlString,
            method: .POST,
            headers: .init(headers),
            body: .data(data),
        )
    }
}
