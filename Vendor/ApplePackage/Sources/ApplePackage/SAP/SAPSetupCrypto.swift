import Foundation
import OpenSSL

extension SAPCrypto {
    static func hmacSHA1(key: [UInt8], message: [UInt8]) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: 20)
        var count: UInt32 = 0
        let result = key.withUnsafeBytes { key in
            message.withUnsafeBytes { message in
                HMAC(EVP_sha1(), key.baseAddress, Int32(key.count), message.baseAddress, message.count, &output, &count)
            }
        }
        guard result != nil, count == 20 else { throw SAPError.cryptoFailure }
        return output
    }

    static func cbc(_ bytes: [UInt8], key: [UInt8], iv: [UInt8], encrypt: Bool) throws -> [UInt8] {
        guard key.count == 16, iv.count == 16, bytes.count.isMultiple(of: 16), bytes.count <= 1 << 20 else {
            throw SAPError.invalidInput("AES-CBC requires a 16-byte key and IV and bounded complete blocks")
        }
        guard let context = EVP_CIPHER_CTX_new() else { throw SAPError.cryptoFailure }
        defer { EVP_CIPHER_CTX_free(context) }
        guard EVP_CipherInit_ex(context, EVP_aes_128_cbc(), nil, key, iv, encrypt ? 1 : 0) == 1, EVP_CIPHER_CTX_set_padding(context, 0) == 1
        else { throw SAPError.cryptoFailure }
        var output = [UInt8](repeating: 0, count: bytes.count + 16)
        var count: Int32 = 0
        guard EVP_CipherUpdate(context, &output, &count, bytes, Int32(bytes.count)) == 1 else { throw SAPError.cryptoFailure }
        var tail = [UInt8](repeating: 0, count: 16)
        var tailCount: Int32 = 0
        guard EVP_CipherFinal_ex(context, &tail, &tailCount) == 1 else { throw SAPError.cryptoFailure }
        return Array(output.prefix(Int(count))) + tail.prefix(Int(tailCount))
    }

    static func rsaOAEP(_ message: [UInt8], seed: [UInt8], modulus: [UInt8], exponent: [UInt8]) throws -> [UInt8] {
        guard modulus.count == 256, seed.count == 20, message.count <= 214 else {
            throw SAPError.invalidInput("SAP setup requires RSA-2048 and a 20-byte OAEP seed")
        }
        func mask(_ seed: [UInt8], count: Int) throws -> [UInt8] {
            var output: [UInt8] = []
            for index in 0 ..< (count + 19) / 20 {
                output += try sha1(seed + SAPBytes.be32(UInt32(index)))
            }
            return Array(output.prefix(count))
        }
        let database = try sha1([]) + [UInt8](repeating: 0, count: 214 - message.count) + [1] + message
        let maskedDatabase = try zip(database, mask(seed, count: 235)).map(^)
        let maskedSeed = try zip(seed, mask(maskedDatabase, count: 20)).map(^)
        let encoded = [UInt8(0)] + maskedSeed + maskedDatabase
        let input = BN_bin2bn(encoded, Int32(encoded.count), nil)
        let n = BN_bin2bn(modulus, Int32(modulus.count), nil)
        let e = BN_bin2bn(exponent, Int32(exponent.count), nil)
        let result = BN_new()
        let context = BN_CTX_new()
        defer {
            BN_free(input)
            BN_free(n)
            BN_free(e)
            BN_free(result)
            BN_CTX_free(context)
        }
        guard let input, let n, let e, let result, let context, BN_num_bits(n) == 2048, BN_num_bits(e) >= 2, BN_is_odd(e) == 1,
              BN_cmp(input, n) < 0, BN_mod_exp(result, input, e, n, context) == 1
        else { throw SAPError.cryptoFailure }
        var output = [UInt8](repeating: 0, count: 256)
        guard BN_bn2binpad(result, &output, 256) == 256 else { throw SAPError.cryptoFailure }
        return output
    }
}
