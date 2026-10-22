@testable import ApplePackage
import Foundation
import XCTest

final class SAPValidationTests: XCTestCase {
    func testResourceDimensionsAndHashes() throws {
        let tables = try SAPStaticTables()
        XCTAssertEqual(tables.byteTables.count, 200)
        XCTAssertTrue(tables.byteTables.allSatisfy { $0.count == 256 })
        XCTAssertEqual(tables.wordTables.count, 72)
        XCTAssertTrue(tables.wordTables.allSatisfy { $0.count == 256 })
        XCTAssertEqual(tables.carryMasks.map(\.count), [233, 239, 241, 251])
        XCTAssertEqual(tables.f2.count, 18432)
        XCTAssertEqual(
            try SAPCrypto.sha256(tables.byteTables.flatMap(\.self)), "a40bb580f1012b06b8b257926b76bb02ec98033f6399da2143c963d36dbe0aae",
        )
        let wordBytes = tables.wordTables.flatMap { table in
            table.flatMap { word in (0 ..< 4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) } }
        }
        XCTAssertEqual(try SAPCrypto.sha256(wordBytes), "6eeffb5e403a54a3b51baa67cf0b7abc23271da404fef4cae9e06c9753833340")
        XCTAssertEqual(
            try SAPCrypto.sha256(tables.carryMasks.flatMap(\.self)), "f0396c6119faafecc811c33a61433faacbfb685d157f198da920183b240285d0",
        )
        XCTAssertEqual(try SAPCrypto.sha256(tables.f2), "f811dd378e1e8e05a9d3697111c4fb1d4afe2acdf81a1fcde69fe231bc975876")
    }

    func testInvalidLogicalSessionLengthsAreRejected() throws {
        let valid = try SyntheticSession.make()
        func construct(source: Data? = nil, input1: Data? = nil, tail: Data? = nil, f3: Data? = nil, words: [UInt32]? = nil) throws
            -> SAPSession
        {
            try SAPSession(
                source: source ?? valid.source, f2Input1: input1 ?? valid.f2Input1, f2Input2: valid.f2Input2, f2Tail: tail ?? valid.f2Tail,
                f3: f3 ?? valid.f3, randomWords: words ?? valid.randomWords, randomCursor: valid.randomCursor, seed30: valid.seed30,
                seed54: valid.seed54, f1MaterialAddress: valid.f1MaterialAddress, ivAddress: valid.ivAddress,
            )
        }
        XCTAssertThrowsError(try construct(source: Data(repeating: 0, count: 575)))
        XCTAssertThrowsError(try construct(input1: Data(repeating: 0, count: 15)))
        XCTAssertThrowsError(try construct(tail: Data(repeating: 0, count: 17)))
        XCTAssertThrowsError(try construct(f3: Data(repeating: 0, count: 16 * 1024 * 1024 + 1)))
        XCTAssertThrowsError(try construct(words: Array(valid.randomWords.dropLast())))
        let zeroSource = try construct(source: Data(repeating: 0, count: 576))
        XCTAssertThrowsError(try SAPSigner(session: zeroSource))
    }

    func testDecodedSessionIsValidatedBeforeSigning() throws {
        let valid = try SyntheticSession.make()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
        object["source"] = Data().base64EncodedString()
        let decoded = try JSONDecoder().decode(SAPSession.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try SAPSigner(session: decoded))
    }

    func testMalformedSnapshotsAreRejected() throws {
        XCTAssertThrowsError(try SAPSession(snapshot: Data("{}".utf8)))
        XCTAssertThrowsError(try SAPSession(snapshot: Data("not JSON".utf8)))
        let empty: [String: Any] = [
            "phase": "post_handshake", "context": 0, "heap_base": 0, "heap_hex": "", "data_base": 0, "data_size": 0, "data_patches": [],
            "allocator": ["heap_cursor": 0, "free_blocks": []],
        ]
        func snapshot(_ updates: [String: Any]) throws -> Data {
            var object = empty
            object.merge(updates) { _, replacement in replacement }
            return try JSONSerialization.data(withJSONObject: object)
        }
        XCTAssertThrowsError(try SAPSession(snapshot: snapshot([:])))
        XCTAssertThrowsError(try SAPSession(snapshot: snapshot(["phase": "signing"])))
        XCTAssertThrowsError(try SAPSession(snapshot: snapshot(["data_size": -1])))
        XCTAssertThrowsError(try SAPSession(snapshot: snapshot(["data_size": 67_108_865])))
        XCTAssertThrowsError(try SAPSession(snapshot: snapshot(["heap_hex": "zz"])))
        XCTAssertThrowsError(try SAPSession(snapshot: snapshot(["data_size": 64, "data_patches": [[64, "00"]]])))
        XCTAssertThrowsError(try SAPSession(snapshot: snapshot(["data_size": 64, "data_patches": [[-1, "00"]]])))
    }
}
