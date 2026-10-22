import Foundation

struct SAPStaticTables: Sendable {
    let byteTables: [[UInt8]]
    let wordTables: [[UInt32]]
    let carryMasks: [[UInt8]]
    let f2: [UInt8]

    init() throws {
        func load(_ name: String, size: Int, sha256: String) throws -> [UInt8] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "bin") else {
                throw SAPError.invalidResource(name)
            }
            let bytes = try [UInt8](Data(contentsOf: url))
            guard bytes.count == size, try SAPCrypto.sha256(bytes) == sha256 else {
                throw SAPError.invalidResource("length or SHA-256 mismatch for \(name)")
            }
            return bytes
        }
        let bytePool = try load(
            "byte-tables", size: 51200,
            sha256: "a40bb580f1012b06b8b257926b76bb02ec98033f6399da2143c963d36dbe0aae",
        )
        let wordPool = try load(
            "word-tables", size: 73728,
            sha256: "6eeffb5e403a54a3b51baa67cf0b7abc23271da404fef4cae9e06c9753833340",
        )
        let masks = try load(
            "carry-masks", size: 964,
            sha256: "f0396c6119faafecc811c33a61433faacbfb685d157f198da920183b240285d0",
        )
        f2 = try load(
            "f2-tables", size: 18432,
            sha256: "f811dd378e1e8e05a9d3697111c4fb1d4afe2acdf81a1fcde69fe231bc975876",
        )
        byteTables = (0 ..< 200).map { Array(bytePool[256 * $0 ..< 256 * ($0 + 1)]) }
        wordTables = try (0 ..< 72).map { table in
            try (0 ..< 256).map { try UInt32(SAPBytes.word(wordPool, at: 1024 * table + 4 * $0, width: 4)) }
        }
        var offset = 0
        carryMasks = [233, 239, 241, 251].map { length in
            defer { offset += length }
            return Array(masks[offset ..< offset + length])
        }
    }
}
