// Copyright (c) 2026 ApplePackage contributors.

/// Session parameters derived from the natural, address-independent material.
struct SAPParameters: Sendable {
    var initialCoefficients: [UInt32]
    var terminalCoefficients: [UInt32]
    var initialField: [UInt8]
    var terminalSeeds: [UInt8]
    var rawWords: [[UInt32]]
    var roundKeys: [[UInt8]]

    static let initialOrder = [13, 0, 11, 10, 6, 12, 15, 1, 5, 14, 2, 4, 3, 8, 9, 7]
    static let terminalOrder = [13, 4, 8, 9, 14, 1, 7, 15, 12, 2, 6, 0, 11, 3, 10, 5]

    static func prepare(
        _ material: [UInt8], initialCache: [UInt32], terminalCache: [UInt32],
    ) throws -> SAPParameters {
        guard material.count == 576 else {
            throw SAPError.invalidInput("Expected 576 material bytes")
        }
        guard initialCache.count == 16, terminalCache.count == 16 else {
            throw SAPError.invalidInput("Expected sixteen coefficients in each cache")
        }
        var initial = initialCache
        var terminal = terminalCache
        for (row, slot) in initialOrder.enumerated() where initial[slot] == 0 {
            initial[slot] = pairWord(material, source: 0x180 + 4 * row, mask: 4 * (row % 4)) ^ 0xE628_18FC
        }
        for (row, slot) in terminalOrder.enumerated() where terminal[slot] == 0 {
            let source: Int
            let mask: Int
            if row < 5 {
                source = 0x130 + 4 * row
                mask = 4 * row
            } else if row < 13 {
                source = 0x134 + 4 * row
                mask = 4 * row + 4
            } else {
                source = 0x138 + 4 * row
                mask = 4 * row + 8
            }
            terminal[slot] = pairWord(material, source: source, mask: mask) ^ 0xAF61_5514
        }
        let field: [UInt8] = (0 ..< 16).map { index in
            let left = (3 * index + 7) % 16
            let right = (11 * index + 2) % 16
            let a = Int(material[0x1E0 + left] ^ material[0x70 + left])
            let b = Int(material[0x20 + right] ^ material[0x70 + right])
            return UInt8(((a - b) & 255) ^ 0x2D)
        }
        let seeds: [UInt8] = [
            material[0x1F2] ^ material[0x72], material[0x1F7] ^ material[0x1E7], 0x24,
            material[0x1EB] ^ material[0x2B], material[0x75] ^ material[0x1F5], 0x11,
            material[0x23] ^ material[0x73],
        ]
        var raw: [[UInt32]] = []
        for row in 0 ..< 9 {
            var physical: [UInt32] = []
            for column in 0 ..< 4 {
                let index = 4 * row + 36 * column
                physical.append(pairWord(material, source: 0x130 + index, mask: index) &+ 0x2186_D6FF)
            }
            raw.append([physical[1], physical[3], physical[0], physical[2]])
        }
        raw.reverse()
        let offsets = [0x100, 0x30, 0xA0, 0x80, 0x50, 0, 0xC0, 0x1C0, 0x200]
        let pairs = [
            (0, 1), (8, 9), (22, 23), (28, 29), (20, 21), (30, 31), (24, 25), (14, 15),
            (2, 3), (12, 13), (6, 7), (16, 17), (4, 5), (26, 27), (18, 19), (10, 11),
        ]
        let keys: [[UInt8]] = offsets.map { offset in
            pairs.map { a, b in UInt8((Int(material[offset + a]) + Int(material[offset + b])) & 255) }
        }
        return SAPParameters(
            initialCoefficients: initial, terminalCoefficients: terminal,
            initialField: field, terminalSeeds: seeds, rawWords: raw, roundKeys: keys,
        )
    }

    private static func pairWord(_ material: [UInt8], source: Int, mask: Int) -> UInt32 {
        var word: UInt32 = 0
        for byte in 0 ..< 4 {
            word |= UInt32(material[source + byte] ^ material[0x120 + (mask + byte) % 16]) << (8 * byte)
        }
        return word
    }
}
