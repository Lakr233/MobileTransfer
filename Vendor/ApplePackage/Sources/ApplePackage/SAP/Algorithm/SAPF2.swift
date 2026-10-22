/// Two-input, ten-round substitution/permutation function used in the blob head.
enum SAPF2 {
    private static let keyInputOffset = 0
    private static let keySubstitutionOffset = 4096
    private static let entryOffset = 5120
    private static let finalOffset = 9216
    private static let mainOffset = 13312
    private static let linearOffset = 17408

    private static func keyAdditions(_ key: [UInt8], data: [UInt8]) -> [[UInt8]] {
        let encoded = key.enumerated().map { position, byte in
            data[keyInputOffset + 256 * position + Int(byte)]
        }
        var words = (0 ..< 4).map { position in
            let offset = 4 * position
            return UInt32(encoded[offset]) << 24 | UInt32(encoded[offset + 1]) << 16
                | UInt32(encoded[offset + 2]) << 8 | UInt32(encoded[offset + 3])
        }
        for step in SAPF2Parameters.expansion {
            var word: UInt32 = 0
            for index in step.selection {
                word ^= words[index]
            }
            word = ((word << 8) | (word >> 24)) ^ step.whitening
            var substituted: UInt32 = 0
            for position in 0 ..< 4 {
                let shift = 24 - 8 * position
                let byte = Int((word >> shift) & 255)
                substituted |= UInt32(data[keySubstitutionOffset + 256 * position + byte]) << shift
            }
            words.append(substituted)
        }
        return SAPF2Parameters.keySelections.map { row in
            row.map { selection in
                var word: UInt32 = 0
                for index in selection.words {
                    word ^= words[index]
                }
                var byte = UInt8(truncatingIfNeeded: word >> selection.shift)
                if selection.linear >= 0 {
                    byte = data[linearOffset + 256 * selection.linear + Int(byte)]
                }
                return byte ^ selection.whitening
            }
        }
    }

    private static func mainWord(_ index: Int, data: [UInt8]) -> UInt32 {
        let offset = mainOffset + 4 * index
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    static func deriveHead(_ in1: [UInt8], _ in2: [UInt8], tables: SAPStaticTables) throws -> [UInt8] {
        guard in1.count == 16, in2.count == 16 else {
            throw SAPError.invalidInput("F2 requires two sixteen-byte inputs")
        }
        guard tables.f2.count == 18432 else {
            throw SAPError.invalidInput("Invalid F2 static tables")
        }
        let data = tables.f2
        let additions = keyAdditions(in1, data: data)
        var state = additions[0]
        for position in 0 ..< 16 {
            let byte = data[entryOffset + 256 * position + Int(in2[position])]
            state[SAPF2Parameters.entryPositions[position]] ^= byte
        }
        for round in SAPF2Parameters.mainRouting.indices {
            var output = additions[round + 1]
            for position in 0 ..< 16 {
                let routing = SAPF2Parameters.mainRouting[round][position]
                let word = mainWord(256 * routing.table + Int(state[position]), data: data)
                for bytePosition in 0 ..< 4 {
                    let byte = UInt8(truncatingIfNeeded: word >> (24 - 8 * bytePosition))
                    output[routing.destinations[bytePosition]] ^= byte
                }
            }
            state = output
        }
        var output = additions[10]
        for position in 0 ..< 16 {
            let byte = data[finalOffset + 256 * position + Int(state[position])]
            output[SAPF2Parameters.finalPositions[position]] ^= byte
        }
        return output.map { $0 ^ 0x2D }
    }
}
