import Foundation

/// Stateful signing of the exact bytes sent in an authentication request.
/// Reuse the same instance for retries, redirects, and verification-code calls.
public protocol SAPRequestSigning: Sendable { func sign(_ body: Data) async throws -> Data }

extension SAPSigner: SAPRequestSigning {}

public enum AuthenticationError: LocalizedError {
    case verificationCodeRequired

    public var errorDescription: String? {
        switch self {
        case .verificationCodeRequired: Strings.authRequiresVerificationCode
        }
    }
}
