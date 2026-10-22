import CApplePackage
import Foundation

/// Stateful local signer. Calls on the same actor advance one shared RNG stream.
/// Use `connect()` to establish fresh state with Apple before signing requests.
public actor SAPSigner {
    private let cipher: SAPCipher
    private let session: SAPSession
    private let platform: UInt32
    private let f2: [UInt8]
    private var random = sap_rng_state()
    private var blob: [UInt8]?
    public private(set) var calls: UInt64 = 0

    public init(snapshot: Data, ivAddress: UInt64 = 0x5000_007F_ED90, platform: UInt32 = 1) throws {
        try self.init(session: SAPSession(snapshot: snapshot, ivAddress: ivAddress), platform: platform)
    }

    public init(session: SAPSession, platform: UInt32 = 1) throws {
        try session.validate()
        let tables = try SAPStaticTables()
        cipher = try SAPCipher(source: [UInt8](session.source), tables: tables)
        f2 = try SAPF2.deriveHead([UInt8](session.f2Input1), [UInt8](session.f2Input2), tables: tables) + session.f2Tail
        self.session = session
        self.platform = platform
        random.cursor = session.randomCursor
        withUnsafeMutableBytes(of: &random.words) { bytes in
            for (index, word) in session.randomWords.enumerated() {
                bytes.storeBytes(of: word, toByteOffset: 4 * index, as: UInt32.self)
            }
        }
    }

    public func sign(_ body: Data) throws -> Data {
        if blob == nil {
            var f1 = [UInt8](repeating: 0, count: 256)
            sap_rng_f1(&random, session.seed30, UInt32(truncatingIfNeeded: session.f1MaterialAddress), &f1)
            var value: [UInt8] = [3] + SAPBytes.be32(platform) + SAPBytes.be32(256) + f1
            value += SAPBytes.be32(UInt32(f2.count)) + f2
            value += SAPBytes.be32(UInt32(session.f3.count)) + session.f3
            value += [UInt8](repeating: 0, count: (16 - value.count % 16) % 16)
            blob = value
        }
        guard let blob else { throw SAPError.invalidInput("missing signing blob") }
        var iv = [UInt8](repeating: 0, count: 16)
        sap_rng_iv(&random, session.seed54, UInt32(truncatingIfNeeded: session.ivAddress), &iv)
        let digest = try SAPCrypto.sha1(blob + body)
        let first = try cipher.encrypt(zip(iv, digest.prefix(16)).map(^))
        let tail = Array(digest.suffix(4)) + [UInt8](repeating: 0, count: 12)
        let tag = try cipher.encrypt(zip(first, tail).map(^))
        calls &+= 1
        return Data([2] + iv + tag + SAPBytes.be32(UInt32(blob.count)) + blob)
    }
}
