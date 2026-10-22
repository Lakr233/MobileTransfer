@testable import ApplePackage
import Foundation
import XCTest

/// All variable inputs here are synthetic and have never been server-issued.
/// The expected outputs were generated with the independently recovered Python
/// direct algorithm, using only these new inputs and the fixed algorithm tables.
final class SAPSyntheticTests: XCTestCase {
    func testSignatureCarriesVariableLengthServerRecord() async throws {
        let original = try SyntheticSession.make()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        let record = Data(repeating: 0xA5, count: 26)
        object["f3"] = record.base64EncodedString()
        let session = try JSONDecoder().decode(SAPSession.self, from: JSONSerialization.data(withJSONObject: object))
        let signer = try SAPSigner(session: session)
        let signature = try await signer.sign(Data())
        let lengthOffset = 37 + 9 + 256 + 4 + 16 + session.f2Tail.count
        XCTAssertEqual(Array(signature[lengthOffset ..< lengthOffset + 4]), [0, 0, 0, 26])
        XCTAssertEqual(signature[lengthOffset + 4 ..< lengthOffset + 4 + record.count], record)
    }

    func testThreeConsecutiveCompleteSignatures() async throws {
        let session = try SyntheticSession.make()
        XCTAssertEqual(
            try SAPCrypto.sha256([UInt8](session.source)),
            "bc89fa33012fa9d8639c174bc5fca3b9e037da8b91a1d42b0c82992963fd315a",
        )
        let signer = try SAPSigner(session: session, platform: 7)
        let expected = [
            "ba76e674c73d9db75c2986233016b94b22e062556fd029d71733726519756517",
            "4acc6269de932c753260fecfa375a6405b5b63cf621a8adace3bd7b5f0305287",
            "853914149c9de004852fffa75a4489c3cdec3f179c92903e3d94b8b2d494e4e4",
        ]
        var signatures: [Data] = []
        for (index, body) in SyntheticSession.bodies.enumerated() {
            let signature = try await signer.sign(body)
            XCTAssertEqual(signature.count, 501)
            XCTAssertEqual(try SAPCrypto.sha256([UInt8](signature)), expected[index])
            signatures.append(signature)
        }
        let calls = await signer.calls
        XCTAssertEqual(calls, 3)
        // F1/blob is cached, while each call consumes a fresh IV from the stream.
        XCTAssertEqual(signatures[0].suffix(464), signatures[1].suffix(464))
        XCTAssertNotEqual(signatures[0][1 ..< 17], signatures[1][1 ..< 17])
        let replay = try SAPSigner(session: session, platform: 7)
        let firstAgain = try await replay.sign(SyntheticSession.bodies[0])
        XCTAssertEqual(firstAgain, signatures[0])
    }

    func testF2AndEncryptionBlocks() throws {
        let session = try SyntheticSession.make()
        let tables = try SAPStaticTables()
        let f2 = try SAPF2.deriveHead([UInt8](session.f2Input1), [UInt8](session.f2Input2), tables: tables)
        XCTAssertEqual(f2, try SAPBytes.hex("ad1adda4bad5ada37fd54543681d001c"))
        let cipher = try SAPCipher(source: [UInt8](session.source), tables: tables)
        let blocks = [[UInt8](repeating: 0, count: 16), Array(UInt8(0) ... UInt8(15)), [UInt8](repeating: 255, count: 16)]
        let expected = [
            "8fcdc9e6d7c5009c7f489288231582de",
            "65810b6c7555809e4b87529110631a4c",
            "73d2bd4f671e9abe8b105aac1883036d",
        ]
        for (block, output) in zip(blocks, expected) {
            XCTAssertEqual(try cipher.encrypt(block), try SAPBytes.hex(output))
        }
    }

    func testSessionCodableRoundTripAndChangedBody() async throws {
        let original = try SyntheticSession.make()
        let encoded = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["source"] as? String, original.source.base64EncodedString())
        let decoded = try JSONDecoder().decode(SAPSession.self, from: encoded)
        let left = try SAPSigner(session: original, platform: 7)
        let right = try SAPSigner(session: decoded, platform: 7)
        let expected = try await left.sign(Data())
        let actual = try await right.sign(Data())
        XCTAssertEqual(actual, expected)
        let changed = try SAPSigner(session: decoded, platform: 7)
        let different = try await changed.sign(Data([1]))
        // Equal first-call IV/blob with a different body must change the MAC tag.
        XCTAssertEqual(actual[1 ..< 17], different[1 ..< 17])
        XCTAssertEqual(actual.suffix(464), different.suffix(464))
        XCTAssertNotEqual(actual[17 ..< 33], different[17 ..< 33])
    }
}

/// Public test recipe, independent of every captured handshake/session corpus.
enum SyntheticSession {
    static let bodies = [Data(), Data(Array("synthetic SAP\nbody-2".utf8) + [0, 255]), Data((0 ..< 256).map(UInt8.init))]

    static func make() throws -> SAPSession {
        var random = XorShift32(state: 0x5359_5031)
        var source = random.bytes(576)
        source[0xFA] = source[0xCA] ^ 10
        source[0xF3] = source[0xC3] ^ 147 // inverse cache length2707
        let input1 = random.bytes(16)
        let input2 = random.bytes(16)
        let tail = random.bytes(7)
        let label = Array("SYNTHETIC TEST SESSION / NEVER SERVER-ISSUED / ".utf8)
        let f3 = label + random.bytes(159 - label.count)
        let words = (0 ..< 624).map { _ in random.word() }
        let seed30 = random.word()
        let seed54 = random.word()
        return try SAPSession(
            source: Data(source), f2Input1: Data(input1), f2Input2: Data(input2),
            f2Tail: Data(tail), f3: Data(f3), randomWords: words, randomCursor: 624,
            seed30: seed30, seed54: seed54, f1MaterialAddress: 0x12_3450_0044,
            ivAddress: 0x0F_EED0_0050,
        )
    }

    private struct XorShift32 {
        var state: UInt32

        mutating func word() -> UInt32 {
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            return state
        }

        mutating func bytes(_ count: Int) -> [UInt8] {
            (0 ..< count).map { _ in UInt8(truncatingIfNeeded: word()) }
        }
    }
}
