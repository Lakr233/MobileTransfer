import Foundation
import OpenSSL

enum SAPCrypto {
    static func sha1(_ bytes: [UInt8]) throws -> [UInt8] {
        var digest = [UInt8](repeating: 0, count: 20)
        var count: UInt32 = 0
        let result = bytes.withUnsafeBytes {
            EVP_Digest($0.baseAddress, bytes.count, &digest, &count, EVP_sha1(), nil)
        }
        guard result == 1, count == 20 else { throw SAPError.cryptoFailure }
        return digest
    }

    static func sha256(_ bytes: [UInt8]) throws -> String {
        var digest = [UInt8](repeating: 0, count: 32)
        var count: UInt32 = 0
        let result = bytes.withUnsafeBytes {
            EVP_Digest($0.baseAddress, bytes.count, &digest, &count, EVP_sha256(), nil)
        }
        guard result == 1, count == 32 else { throw SAPError.cryptoFailure }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
