//
//  Account.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import Foundation

public struct Account: Codable, Hashable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "Account(email: \(email), store: \(store), pod: \(pod ?? "nil"))"
    }

    public var debugDescription: String {
        "Account(email: \(email), appleId: \(appleId), store: \(store), name: \(firstName) \(lastName), dsid: \(directoryServicesIdentifier), pod: \(pod ?? "nil"))"
    }

    public var email: String
    public var password: String

    public var appleId: String // /accountInfo/appleId
    public var store: String
    public var firstName: String // /accountInfo/address/firstName
    public var lastName: String // /accountInfo/address/lastName
    public var passwordToken: String // /passwordToken
    public var directoryServicesIdentifier: String // /dsPersonId
    public var cookie: [Cookie]
    public var pod: String?

    public init(
        email: String,
        password: String,
        appleId: String,
        store: String,
        firstName: String,
        lastName: String,
        passwordToken: String,
        directoryServicesIdentifier: String,
        cookie: [Cookie],
        pod: String? = nil,
    ) {
        self.email = email
        self.password = password
        self.appleId = appleId
        self.store = store
        self.firstName = firstName
        self.lastName = lastName
        self.passwordToken = passwordToken
        self.directoryServicesIdentifier = directoryServicesIdentifier
        self.cookie = cookie
        self.pod = pod
    }
}

public extension Account {
    init(
        email: String,
        password: String,
        appleId: String?,
        store: String,
        firstName: String?,
        lastName: String?,
        passwordToken: String?,
        directoryServicesIdentifier: String?,
        cookie: [Cookie],
        pod: String? = nil,
    ) throws {
        try ensure(!email.isEmpty, Strings.emptyEmail)
        try ensure(!password.isEmpty, Strings.emptyPassword)
        self.email = email
        self.password = password
        self.appleId = try appleId.get(Strings.unableToReadAppleId)
        try ensure(!store.isEmpty, Strings.unknownStoreIdentifier)
        try ensure(Configuration.countryCode(for: store) != nil, Strings.unsupportedStoreIdentifier(store))
        self.store = store
        self.firstName = try firstName.get(Strings.unableToReadFirstName)
        self.lastName = try lastName.get(Strings.unableToReadLastName)
        self.passwordToken = try passwordToken.get(Strings.unableToReadPasswordToken)
        self.directoryServicesIdentifier = try directoryServicesIdentifier.get(Strings.unableToReadDsPersonId)
        self.cookie = cookie
        self.pod = pod
    }
}
