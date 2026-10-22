@testable import ApplePackage
import Foundation
import XCTest

/// Optional local-only regression. No captured session/source/signature is part
/// of this repository. Set SAP_CORPUS_ROOT to a separate ipatool_sap research tree.
final class SAPCorpusTests: XCTestCase {
    func testExternalConsecutiveAndHoldoutCorpus() async throws {
        guard let path = ProcessInfo.processInfo.environment["SAP_CORPUS_ROOT"], !path.isEmpty else {
            throw XCTSkip("Set SAP_CORPUS_ROOT to run the external 1,152-signature corpus")
        }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let cases = try jsonLines(CorpusCase.self, root.appendingPathComponent("vectors/vectors-b.jsonl"))
        XCTAssertEqual(Set(cases.map(\.session)), Set(0 ..< 8))
        var consecutiveCount = 0
        var holdoutCount = 0
        for session in 0 ..< 8 {
            let suffix = String(format: "%02d", session)
            let saved = try Data(
                contentsOf: root.appendingPathComponent("reconstruction/validation/fixtures/allocator/session-\(suffix).json"),
            )
            let signer = try SAPSigner(snapshot: saved)
            let ordered = cases.filter { $0.session == session }.sorted { $0.index < $1.index }
            XCTAssertEqual(ordered.count, 128)
            for item in ordered {
                let actual = try await signer.sign(Data(SAPBytes.hex(item.body)))
                let expected = try Data(SAPBytes.hex(item.signature))
                guard actual == expected else {
                    XCTFail("Consecutive signature mismatch: session \(session), index \(item.index)")
                    return
                }
                consecutiveCount += 1
            }
            let calls = await signer.calls
            XCTAssertEqual(calls, 128)
            let references = try jsonLines(
                HoldoutCase.self, root.appendingPathComponent("reconstruction/implementation/fixtures/holdout/reference-\(suffix).jsonl"),
            )
            XCTAssertEqual(references.count, 16)
            for (index, item) in references.enumerated() {
                // The external holdout oracle started a fresh session per body.
                let fresh = try SAPSigner(snapshot: saved)
                let actual = try await fresh.sign(Data(SAPBytes.hex(item.bodyHex)))
                let expected = try Data(SAPBytes.hex(item.signatureHex))
                guard actual == expected else {
                    XCTFail("Holdout signature mismatch: session \(session), case \(index)")
                    return
                }
                holdoutCount += 1
            }
        }
        XCTAssertEqual(consecutiveCount, 1024)
        XCTAssertEqual(holdoutCount, 128)
    }

    private func jsonLines<T: Decodable>(_ type: T.Type, _ url: URL) throws -> [T] {
        try Data(contentsOf: url).split(separator: 10).filter { !$0.isEmpty }.map {
            try JSONDecoder().decode(type, from: Data($0))
        }
    }

    private struct CorpusCase: Decodable {
        let session: Int
        let index: Int
        let body: String
        let signature: String
    }

    private struct HoldoutCase: Decodable {
        let bodyHex: String
        let signatureHex: String
        enum CodingKeys: String, CodingKey {
            case bodyHex = "body_hex", signatureHex = "signature_hex"
        }
    }
}
