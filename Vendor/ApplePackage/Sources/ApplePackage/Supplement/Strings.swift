//
//  Strings.swift
//  ApplePackage
//
//  Created on 2026/2/20.
//

import Foundation

public enum Strings {
    // MARK: - Authentication

    static let authRequiresVerificationCode = "Authentication requires verification code\nIf no verification code prompted, try logging in at https://account.apple.com to trigger the alert and fill the code in the 2FA Code here."
    static let authFailed = "authentication failed"
    static let authFailedUnknown = "authentication failed for an unknown reason"
    static let invalid2FACode = "invalid or expired 2FA code (failureType: 5005)"
    static let invalidAuthEndpoint = "invalid auth endpoint URL"

    // MARK: - Token / Session

    static let passwordTokenExpired = "password token is expired"
    static let passwordChanged = "Your password has changed."

    // MARK: - Download

    static let downloadFailed = "download failed"
    static let missingDownloadURL = "missing download URL"
    static let missingMetadata = "missing metadata"
    static let missingRequiredInfo = "missing required information"
    static let invalidSinfItem = "invalid sinf item"
    static let noSinfFound = "no sinf found in response"
    static let appleTVPackageValidationFailed = "downloaded package does not declare AppleTVOS support"

    // MARK: - Purchase

    static let paidAppsNotSupported = "purchasing paid apps is not supported"
    static let itemTemporarilyUnavailable = "item is temporarily unavailable"
    static let subscriptionRequired = "subscription required"
    static let purchaseFailed = "purchase failed"
    static let invalidPurchaseResponse = "invalid purchase response"
    static let failedToPurchase = "failed to purchase app"
    static let alreadyPurchased = "app is already purchased"
    static let purchasedAppUnavailable = "app is already purchased, unavailable, or delisted"
    static let itemUnavailableOrNotPurchased = "app is unavailable, delisted, unavailable in this storefront, or not purchased"
    static let invalidStore = "invalid store or app unavailable in this storefront"
    static let paidAppPurchaseFailed = "paid apps cannot be purchased directly"
    static let noLicenseFound = "license not found or app id is invalid"

    static func termsAcceptanceRequired(url: String) -> String {
        "purchase requires accepting terms first, visit: \(url)"
    }

    static func purchaseFailureMessage(failureType: String, customerMessage: String?) -> String {
        let message: String = switch failureType {
        case "5002":
            alreadyPurchased
        case "2040":
            purchasedAppUnavailable
        case "2059":
            itemUnavailableOrNotPurchased
        case "1010":
            invalidStore
        case "2034", "2042":
            passwordTokenExpired
        case "2019":
            paidAppPurchaseFailed
        case "9610":
            noLicenseFound
        default:
            customerMessage.flatMap { $0.isEmpty ? nil : $0 } ?? purchaseFailed
        }

        return "\(message) (failureType: \(failureType))"
    }

    // MARK: - Version

    static let missingVersionIdentifiers = "missing version identifiers"
    static let noVersionsFound = "no versions found"
    static let missingBundleShortVersionString = "missing bundleShortVersionString"
    static let missingOrInvalidReleaseDate = "missing or invalid releaseDate"

    // MARK: - Common Response

    static let responseBodyEmpty = "response body is empty"
    static let invalidResponse = "invalid response"
    static let noItemsInResponse = "no items in response"
    static let failedToRetrieveRedirect = "failed to retrieve redirect location"
    static let noResponseReceived = "no response received"
    static let responseNotDictionary = "response is not a dictionary"

    // MARK: - Account

    static let emptyEmail = "empty email"
    static let emptyPassword = "empty password"
    static let unknownStoreIdentifier = "unknown store identifier"
    static let unableToReadAppleId = "unable to read appleId"
    static let unableToReadFirstName = "unable to read firstName"
    static let unableToReadLastName = "unable to read lastName"
    static let unableToReadPasswordToken = "unable to read passwordToken"
    static let unableToReadDsPersonId = "unable to read dsPersonId"
    static let missingAccountInfo = "missing accountInfo"
    static let missingAddress = "missing address"

    // MARK: - Request Errors

    static func requestFailed(status: UInt) -> String {
        "request failed with status \(status)"
    }

    static func unsupportedStoreIdentifier(_ id: String) -> String {
        "unsupported store identifier: \(id)"
    }

    static func failureTypeMessage(_ type: String) -> String {
        "failed: \(type)"
    }
}
