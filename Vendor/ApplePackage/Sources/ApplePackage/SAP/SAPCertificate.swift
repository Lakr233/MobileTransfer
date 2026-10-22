import Foundation
import OpenSSL

/// The SAP container embeds an X.509 chain; the last certificate supplies the setup RSA key.
struct SAPCertificate {
    let serial: [UInt8]
    let modulus: [UInt8]
    let exponent: [UInt8]

    init(_ data: Data) throws {
        let bytes = [UInt8](data)
        guard (512 ... 1 << 20).contains(bytes.count) else { throw SAPError.invalidInput("invalid SAP certificate container length") }
        var selected: OpaquePointer?
        var selectedEnd = 0
        defer { X509_free(selected) }
        bytes.withUnsafeBufferPointer { buffer in
            for offset in 0 ..< bytes.count - 4 where bytes[offset] == 0x30 {
                var cursor: UnsafePointer<UInt8>? = buffer.baseAddress!.advanced(by: offset)
                guard let certificate = d2i_X509(nil, &cursor, bytes.count - offset) else { continue }
                let end = cursor.map { buffer.baseAddress!.distance(to: $0) } ?? offset
                if end > selectedEnd, end - offset >= 512 {
                    X509_free(selected)
                    selected = certificate
                    selectedEnd = end
                } else {
                    X509_free(certificate)
                }
            }
        }
        guard let selected, let serialNumber = X509_get_serialNumber(selected), let serialBytes = ASN1_STRING_get0_data(serialNumber),
              let key = X509_get_pubkey(selected)
        else { throw SAPError.invalidInput("SAP container has no usable X.509 certificate") }
        defer { EVP_PKEY_free(key) }
        let serialLength = Int(ASN1_STRING_length(serialNumber))
        guard (1 ... 127).contains(serialLength) else { throw SAPError.invalidInput("invalid SAP certificate serial") }
        let magnitude = Array(UnsafeBufferPointer(start: serialBytes, count: serialLength))
        // OpenSSL removes DER's positive-integer sign byte; the wire request retains it.
        serial = (magnitude[0] & 0x80 == 0 ? [] : [0]) + magnitude
        guard serial.count <= 127 else { throw SAPError.invalidInput("invalid SAP certificate serial") }
        var n: OpaquePointer?
        var e: OpaquePointer?
        defer {
            BN_free(n)
            BN_free(e)
        }
        guard EVP_PKEY_get_bn_param(key, "n", &n) == 1, EVP_PKEY_get_bn_param(key, "e", &e) == 1, let n, let e, BN_num_bits(n) == 2048,
              BN_num_bits(e) >= 2, BN_is_odd(e) == 1
        else { throw SAPError.invalidInput("SAP certificate must contain an RSA-2048 public key") }
        var modulus = [UInt8](repeating: 0, count: 256)
        var exponent = [UInt8](repeating: 0, count: Int((BN_num_bits(e) + 7) / 8))
        guard BN_bn2binpad(n, &modulus, Int32(modulus.count)) == modulus.count,
              BN_bn2binpad(e, &exponent, Int32(exponent.count)) == exponent.count
        else { throw SAPError.cryptoFailure }
        self.modulus = modulus
        self.exponent = exponent
    }
}
