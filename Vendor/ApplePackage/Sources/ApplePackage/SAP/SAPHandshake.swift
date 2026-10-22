import CApplePackage
import Foundation
import OpenSSL

/// Owns the locally generated secrets until Apple's second exchange completes.
struct SAPHandshake {
    let request: Data
    let responseKey: [UInt8]
    let responseEcho: [UInt8]
    private let f2Material: [UInt8]
    private let random: sap_rng_state
    private let seed30: UInt32
    private let seed54: UInt32

    init(certificate: Data) throws {
        var entropy = [UInt32](repeating: 0, count: 3)
        let result = entropy.withUnsafeMutableBytes { RAND_bytes($0.baseAddress, Int32($0.count)) }
        guard result == 1 else { throw SAPError.cryptoFailure }
        let now = Date().timeIntervalSince1970
        try self.init(certificate: certificate, entropy: entropy, seconds: Int64(now), microseconds: UInt32((now - floor(now)) * 1_000_000))
    }

    /// Explicit entropy and time keep deterministic compatibility tests independent of OS reads.
    init(certificate: Data, entropy: [UInt32], seconds: Int64, microseconds: UInt32) throws {
        guard entropy.count == 3, microseconds < 1_000_000 else { throw SAPError.invalidInput("invalid setup entropy or time") }
        let certificate = try SAPCertificate(certificate)
        var random = sap_rng_state()
        var pool = [UInt32](repeating: 0, count: 128)
        sap_rng_initialize(&random, entropy[0], entropy[1], entropy[2], UInt32(truncatingIfNeeded: seconds), microseconds, &pool)
        let seed30 = pool[0x30 / 4]
        let seed54 = pool[0x54 / 4]
        func generate(_ count: Int, address: UInt32, exchange: Bool = false) -> [UInt8] {
            var output = [UInt8](repeating: 0, count: count)
            if exchange {
                sap_rng_exchange(&random, pool[0x3C / 4], address, &output, count)
            } else {
                sap_rng_setup(&random, seed54, address, &output, count)
            }
            return output
        }
        // These constants are arithmetic salts from the reconstructed layout, never pointers.
        let initial = generate(33, address: 0x7FFAC0)
        let f2Material = initial.prefix(16 + Int(initial[32] % 17)).map { $0 ^ 0x2D }
        let responseKey = generate(16, address: 0x7FFC14, exchange: true)
        let responseEcho = generate(16, address: 0x7FFC14, exchange: true)
        let encryptionKey = generate(16, address: 0x7FFC14, exchange: true)
        let iv = generate(16, address: 0x7FFC14, exchange: true)
        let authenticationKey = generate(20, address: 0x7FFC24, exchange: true)
        let padding = (UInt32(0x7FF808) ..< 0x7FF813).reversed().map { UInt8(truncatingIfNeeded: (($0 ^ 0xBA) &* ($0 &+ 0x11)) ^ 0x2D) }
        let plaintext = [UInt8(2)] + SAPBytes.be32(1) + responseKey + responseEcho + padding
        let oaepSeed = generate(20, address: 0x7FF4E4)
        let keyBlock = try SAPCrypto.rsaOAEP(
            encryptionKey + authenticationKey, seed: oaepSeed, modulus: certificate.modulus, exponent: certificate.exponent,
        )
        let encrypted = try SAPCrypto.cbc(plaintext, key: encryptionKey, iv: iv, encrypt: true)
        let mac = try SAPCrypto.hmacSHA1(key: authenticationKey, message: encrypted)
        var request = Data([1, UInt8(certificate.serial.count)])
        request.append(contentsOf: certificate.serial)
        request.append(contentsOf: keyBlock)
        request.append(contentsOf: iv)
        request.append(contentsOf: SAPBytes.be32(UInt32(encrypted.count)))
        request.append(contentsOf: encrypted)
        request.append(contentsOf: mac)
        self.request = request
        self.responseKey = responseKey
        self.responseEcho = responseEcho
        self.f2Material = f2Material
        self.random = random
        self.seed30 = seed30
        self.seed54 = seed54
    }

    func complete(_ reply: Data) throws -> SAPSession {
        let bytes = [UInt8](reply)
        func length(at offset: Int) throws -> Int {
            guard offset >= 0, offset <= bytes.count - 4 else { throw SAPError.invalidInput("truncated setup length") }
            return bytes[offset ..< offset + 4].reduce(0) { ($0 << 8) | Int($1) }
        }
        guard bytes.count >= 21, bytes.count <= 1 << 20, bytes[0] == 2 else { throw SAPError.invalidInput("invalid SAP setup response") }
        let encryptedLength = try length(at: 17)
        guard encryptedLength > 0, encryptedLength.isMultiple(of: 16), encryptedLength <= bytes.count - 21 - 25 else {
            throw SAPError.invalidInput("invalid SAP setup ciphertext length")
        }
        let recordOffset = 21 + encryptedLength
        let declared = try length(at: recordOffset + 21)
        let recordLength = Int(UInt32(truncatingIfNeeded: declared) &+ 25)
        guard recordLength <= 16 * 1024 * 1024, recordLength <= bytes.count - recordOffset else {
            throw SAPError.invalidInput("invalid SAP setup signature record length")
        }
        let plaintext = try SAPCrypto.cbc(Array(bytes[21 ..< recordOffset]), key: responseKey, iv: Array(bytes[1 ..< 17]), encrypt: false)
        var fields: [[UInt8]] = []
        var offset = 0
        for expected in [16, 16, 16, 576, 576, 16] {
            guard offset <= plaintext.count - 4 else { throw SAPError.invalidInput("truncated decrypted setup field") }
            let count = plaintext[offset ..< offset + 4].reduce(0) { ($0 << 8) | Int($1) }
            offset += 4
            guard count == expected, count <= plaintext.count - offset else {
                throw SAPError.invalidInput("invalid decrypted SAP setup field length")
            }
            fields.append(Array(plaintext[offset ..< offset + count]))
            offset += count
        }
        let difference = zip(fields[5], responseEcho).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) }
        guard difference == 0 else { throw SAPError.invalidInput("SAP reply belongs to another exchange") }
        let words = withUnsafeBytes(of: random.words) { Array($0.bindMemory(to: UInt32.self)) }
        return try SAPSession(
            source: Data(fields[4]), f2Input1: Data(fields[2].map { $0 &+ 0x2D }), f2Input2: Data(f2Material.prefix(16)),
            f2Tail: Data(f2Material.dropFirst(16).map { $0 ^ 0x2D }), f3: Data(bytes[recordOffset ..< recordOffset + recordLength]),
            randomWords: words, randomCursor: random.cursor, seed30: seed30, seed54: seed54,
            f1MaterialAddress: 0x4000_0000_0604 + UInt64(f2Material.count > 28 ? 16 : 0),
        )
    }
}
