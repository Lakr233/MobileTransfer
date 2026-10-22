@testable import ApplePackage
import Foundation
import Testing

struct SAPHandshakeTests {
    private struct Fixture: Decodable {
        let certificate: String
        let cases: [Vector]
    }

    private struct Vector: Decodable {
        let entropy: [UInt32]
        let seconds: Int64
        let microseconds: UInt32
        let request: String
        let reply: String
        let randomHash: String
        let cursor: UInt32
        let seed30: UInt32
        let seed54: UInt32
        let f2Input2: String
        let f2Tail: String
        let responseKey: String
        let responseEcho: String
    }

    private func fixture() throws -> Fixture {
        let url = try #require(Bundle.module.url(forResource: "handshake", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func bytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return UInt8(hex[start ..< hex.index(start, offsetBy: 2)], radix: 16)!
        }
    }

    @Test
    func `matches independent python setup vectors`() throws {
        let fixture = try fixture()
        for vector in fixture.cases {
            let pending = try SAPHandshake(
                certificate: Data(bytes(fixture.certificate)), entropy: vector.entropy, seconds: vector.seconds,
                microseconds: vector.microseconds,
            )
            #expect(pending.request == Data(bytes(vector.request)))
            #expect(pending.responseKey == bytes(vector.responseKey))
            #expect(pending.responseEcho == bytes(vector.responseEcho))
            let session = try pending.complete(Data(bytes(vector.reply)))
            let words = session.randomWords.flatMap { word in (0 ..< 4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) } }
            #expect(try SAPCrypto.sha256(words) == vector.randomHash)
            #expect(session.randomCursor == vector.cursor)
            #expect(session.seed30 == vector.seed30)
            #expect(session.seed54 == vector.seed54)
            #expect(session.f2Input2 == Data(bytes(vector.f2Input2)))
            #expect(session.f2Tail == Data(bytes(vector.f2Tail)))
            #expect(session.source == Data((0 ..< 576).map { UInt8(truncatingIfNeeded: $0 * 17 + 3) }))
            #expect(session.f2Input1 == Data((32 ..< 48).map { UInt8($0 + 0x2D) }))
            #expect(session.f3.count == 159)
        }
    }

    @Test
    func `rejects truncated corrupted and unrelated replies`() throws {
        let fixture = try fixture()
        let first = try #require(fixture.cases.first)
        let second = fixture.cases[1]
        let pending = try SAPHandshake(
            certificate: Data(bytes(fixture.certificate)), entropy: first.entropy, seconds: first.seconds, microseconds: first.microseconds,
        )
        let reply = Data(bytes(first.reply))
        for count in [0, 20, 21, reply.count - 1] {
            #expect(throws: (any Error).self) { try pending.complete(reply.prefix(count)) }
        }
        #expect(throws: (any Error).self) { try pending.complete(Data(bytes(second.reply))) }
        var corrupted = reply
        corrupted[17 ..< 21] = Data(repeating: 0xFF, count: 4)
        #expect(throws: (any Error).self) { try pending.complete(corrupted) }
        corrupted = reply
        corrupted[21] ^= 1
        #expect(throws: (any Error).self) { try pending.complete(corrupted) }

        let key = bytes(first.responseKey)
        let iv = Array(reply[1 ..< 17])
        let count = reply[17 ..< 21].reduce(0) { ($0 << 8) | Int($1) }
        var plaintext = try SAPCrypto.cbc(Array(reply[21 ..< 21 + count]), key: key, iv: iv, encrypt: false)
        // Keep every field length valid while changing only the client's echoed secret.
        plaintext[1239] ^= 1
        corrupted = reply
        corrupted[21 ..< 21 + count] = try Data(SAPCrypto.cbc(plaintext, key: key, iv: iv, encrypt: true))
        #expect(throws: (any Error).self) { try pending.complete(corrupted) }
    }

    @Test
    func `opaque server record uses its declared length`() throws {
        let fixture = try fixture()
        let vector = try #require(fixture.cases.first)
        let pending = try SAPHandshake(
            certificate: Data(bytes(fixture.certificate)), entropy: vector.entropy,
            seconds: vector.seconds, microseconds: vector.microseconds,
        )
        var reply = Data(bytes(vector.reply))
        let recordOffset = reply.count - 159
        reply = reply.prefix(recordOffset + 26)
        reply[recordOffset + 21 ..< recordOffset + 25] = Data([0, 0, 0, 1])
        let session = try pending.complete(reply)
        #expect(session.f3.count == 26)
    }
}
