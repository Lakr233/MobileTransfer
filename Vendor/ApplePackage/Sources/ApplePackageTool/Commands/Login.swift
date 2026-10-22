//
//  Login.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import ApplePackage
import ArgumentParser
import Darwin
import Foundation

struct Login: AsyncParsableCommand, Sendable {
    static let configuration = CommandConfiguration(commandName: "login", abstract: "Sign in to an Apple Account")

    @OptionGroup
    var globalOptions: GlobalOptions

    @Argument(help: "Email address")
    var email: String

    @Argument(help: "Password (defaults to APPLEPACKAGE_PASSWORD or a secure terminal prompt)")
    var password: String?

    @Option(help: "Six-digit verification code", transform: { value in try Login.validatedVerificationCode(value) })
    var code: String?

    mutating func validate() throws {
        email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { throw ValidationError("Email address must not be empty.") }
        if let password, password.isEmpty {
            throw ValidationError("Password must not be empty.")
        }
    }

    func run() async throws {
        let password = try resolvePassword()
        globalOptions.apply()
        let session = try await Authenticator()
        var verificationCode = code ?? ""
        while true {
            do {
                let account = try await session.authenticate(email: email, password: password, code: verificationCode)
                Configuration.saveLoginAccount(account, for: email)
                print("login successful for \(email)")
                return
            } catch AuthenticationError.verificationCodeRequired {
                guard verificationCode.isEmpty, isatty(STDIN_FILENO) != 0 else { throw AuthenticationError.verificationCodeRequired }
                print("2FA verification code: ", terminator: "")
                fflush(nil)
                guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
                    throw AuthenticationError.verificationCodeRequired
                }
                verificationCode = try Self.validatedVerificationCode(input)
            }
        }
    }

    private static func validatedVerificationCode(_ input: String) throws -> String {
        let code = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.utf8.count == 6, code.utf8.allSatisfy({ (48 ... 57).contains($0) }) else {
            throw ValidationError("Verification code must contain exactly six digits.")
        }
        return code
    }

    private func resolvePassword() throws -> String {
        if let password {
            return password
        }
        if let password = ProcessInfo.processInfo.environment["APPLEPACKAGE_PASSWORD"], !password.isEmpty {
            return password
        }
        guard isatty(STDIN_FILENO) != 0 else {
            throw ValidationError("Provide a password argument or set APPLEPACKAGE_PASSWORD when no terminal is available.")
        }
        let capacity = 1024
        var buffer = [CChar](repeating: 0, count: capacity)
        defer { buffer.withUnsafeMutableBytes { bytes in _ = bytes.initializeMemory(as: UInt8.self, repeating: 0) } }
        guard let pointer = readpassphrase("Apple Account password: ", &buffer, capacity, RPP_REQUIRE_TTY) else {
            throw ValidationError("Could not read the password from the terminal.")
        }
        let password = String(cString: pointer)
        guard !password.isEmpty else { throw ValidationError("Password must not be empty.") }
        return password
    }
}
