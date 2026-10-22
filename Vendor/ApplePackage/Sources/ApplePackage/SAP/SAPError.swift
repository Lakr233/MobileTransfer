import Foundation

public enum SAPError: Error, LocalizedError, Sendable {
    case invalidInput(String)
    case invalidResource(String)
    case cryptoFailure

    public var errorDescription: String? {
        switch self {
        case let .invalidInput(message): "Invalid SAP input: \(message)"
        case let .invalidResource(message): "Invalid SAP table resource: \(message)"
        case .cryptoFailure: "OpenSSL digest calculation failed"
        }
    }
}

enum SAPBytes {
    static func hex(_ text: String) throws -> [UInt8] {
        let input = Array(text.utf8)
        guard input.count.isMultiple(of: 2) else { throw SAPError.invalidInput("odd hex length") }
        func digit(_ byte: UInt8) throws -> UInt8 {
            switch byte {
            case 48 ... 57: return byte - 48
            case 65 ... 70: return byte - 55
            case 97 ... 102: return byte - 87
            default: throw SAPError.invalidInput("invalid hexadecimal byte")
            }
        }
        return try stride(from: 0, to: input.count, by: 2).map {
            try (digit(input[$0]) << 4) | digit(input[$0 + 1])
        }
    }

    static func word(_ bytes: [UInt8], at offset: Int, width: Int) throws -> UInt64 {
        guard offset >= 0, width > 0, width <= 8, offset <= bytes.count - width else {
            throw SAPError.invalidInput("word outside saved region")
        }
        return (0 ..< width).reduce(0) { $0 | (UInt64(bytes[offset + $1]) << (8 * $1)) }
    }

    static func be32(_ value: UInt32) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value),
        ]
    }
}
