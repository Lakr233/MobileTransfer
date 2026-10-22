import Foundation

/// Logical inputs for one signing session, produced by the SAP handshake.
/// Keep exported sessions private: they include the material needed to sign.
public struct SAPSession: Codable, Sendable {
    public let source: Data
    public let f2Input1: Data
    public let f2Input2: Data
    public let f2Tail: Data
    public let f3: Data
    public let randomWords: [UInt32]
    public let randomCursor: UInt32
    public let seed30: UInt32
    public let seed54: UInt32
    public let f1MaterialAddress: UInt64
    public let ivAddress: UInt64

    public init(
        source: Data, f2Input1: Data, f2Input2: Data, f2Tail: Data, f3: Data, randomWords: [UInt32], randomCursor: UInt32, seed30: UInt32,
        seed54: UInt32, f1MaterialAddress: UInt64, ivAddress: UInt64 = 0x5000_007F_ED90,
    ) throws {
        self.source = source
        self.f2Input1 = f2Input1
        self.f2Input2 = f2Input2
        self.f2Tail = f2Tail
        self.f3 = f3
        self.randomWords = randomWords
        self.randomCursor = randomCursor
        self.seed30 = seed30
        self.seed54 = seed54
        self.f1MaterialAddress = f1MaterialAddress
        self.ivAddress = ivAddress
        try validate()
    }

    func validate() throws {
        guard source.count == 576, f2Input1.count == 16, f2Input2.count == 16, f2Tail.count <= 16, f3.count <= 16 * 1024 * 1024,
              randomWords.count == 624
        else { throw SAPError.invalidInput("invalid logical session field lengths") }
    }

    /// Decode an original complete `post_handshake` snapshot from the research exporter.
    public init(snapshot: Data, ivAddress: UInt64 = 0x5000_007F_ED90) throws {
        self = try SAPSnapshot.decode(snapshot, ivAddress: ivAddress)
    }
}
