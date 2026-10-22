// Copyright (c) 2026 ApplePackage contributors.

/// Address-independent expansion of the session's 576 logical source bytes.
struct SAPSource: Sendable {
    var material: [UInt8]
    var auxiliaryWords0: [UInt32]
    var auxiliaryWords1: [UInt32]
    var cache2: [UInt8]
    var cache3: [UInt8]
    var projectionMask: UInt32
    var selectors: [UInt8]
    var initialCache: [UInt32]
    var terminalCache: [UInt32]

    static func prepare(_ source: [UInt8]) throws -> SAPSource {
        guard source.count == 576 else {
            throw SAPError.invalidInput("Expected 576 logical source bytes")
        }
        let schedule = makeSchedule(source)
        let tables = try makeTables(source)
        let auxiliary = makeAuxiliary(tables)
        let caches = makeCoefficientCaches(source, tables: tables, schedule: schedule)
        return SAPSource(
            material: makeMaterial(source, schedule: schedule),
            auxiliaryWords0: auxiliary.0, auxiliaryWords1: auxiliary.1,
            cache2: auxiliary.2, cache3: auxiliary.3, projectionMask: ~tables.mask,
            selectors: schedule.selectors, initialCache: caches.0, terminalCache: caches.1,
        )
    }

    private struct Schedule {
        let lengths: [[Int]]
        let selectors: [UInt8]
    }

    private struct SourceTables {
        let words: [UInt32]
        let cache: [UInt8]
        let mask: UInt32
        let seeds: [UInt32]
    }

    private static func makeSchedule(_ source: [UInt8]) -> Schedule {
        var lengths = [[Int]](repeating: [Int](repeating: 0, count: 11), count: 16)
        for column in 0 ..< 11 {
            let bank = [0xE0, 0xF0, 0xC0][column / 4]
            let moduli = [[7, 27, 47, 77], [9, 29, 49, 79], [5, 25, 45, 75]][column / 4]
            for group in 0 ..< 4 {
                let at = 4 * (column % 4) + group
                let value = Int(source[0x30 + at] ^ source[bank + at])
                for lane in 0 ..< 4 {
                    let digit = (value % moduli[lane]) & 3
                    lengths[4 * group + lane][column] = [3, 3, 5, 1][digit]
                }
            }
            var cost = lengths.reduce(0) { $0 + $1[column] }
            var row = Int(source[0x31] ^ source[0xC1]) & 15
            while cost > 32 {
                cost -= lengths[row][column] - 1
                lengths[row][column] = 1
                row = (row + 5) & 15
            }
        }
        var selectors: [UInt8] = []
        for index in 0 ..< 8 {
            let value = Int(source[0xE0 + index] ^ source[0xF0 + index])
            selectors.append(UInt8(value % 7))
            selectors.append(UInt8((value / 7) % 7))
        }
        return Schedule(lengths: lengths, selectors: selectors)
    }

    private static func makeTables(_ source: [UInt8]) throws -> SourceTables {
        let size = (Int(source[0xFA] ^ source[0xCA]) << 8) | Int(source[0xF3] ^ source[0xC3])
        guard size > 0 else {
            throw SAPError.invalidInput("Source inverse cache must not be empty")
        }
        let pairs = [(0xEA, 0xFA), (0xE4, 0xF4), (0xED, 0xFD), (0xE6, 0xF6)]
        var seed: UInt32 = 0
        for (a, b) in pairs {
            seed = (seed << 8) | UInt32(source[a] ^ source[b])
        }
        var state = seed
        var states: [UInt32] = []
        for _ in 0 ..< 13 {
            let wide = UInt64(state)
            state = UInt32(((wide &* wide) &+ 1) % 0xFFFF_FFFB)
            states.append(state)
        }
        var mask: UInt32 = 1 << Int(seed & 7)
        for lane in 1 ..< 4 {
            mask |= 1 << (8 * lane + Int(states[lane - 1] & 7))
        }
        let basis = Array(states[3 ..< 11])
        let header = states[11]
        state = states[12]
        var cache: [UInt8] = (0 ..< size).map { index in
            source[(index + 3 * Int(source[index % 576]) + 2) % 576] ^ 0xD6
        }
        var words: [UInt32] = []
        for index in 0 ..< 256 {
            var word = header ^ (state & mask)
            for bit in 0 ..< 8 where index & (1 << bit) != 0 {
                word ^= basis[bit]
            }
            words.append(word)
            cache[Int((word & ~mask) % UInt32(size))] = UInt8(index) ^ 0xD6
            let value = state ^ 0x63
            // The original signed widening contributes residue512 modulo576.
            let correction = index != 0 && state & 0x8000_0000 != 0 ? 512 : 0
            let position = (17 * Int(value >> 4) + 3 * Int(value & 15) + 176 + correction) % 576
            state = 0
            for byte in 0 ..< 4 {
                state |= UInt32(source[(position + byte) % 576]) << (8 * byte)
            }
        }
        return SourceTables(words: words, cache: cache, mask: mask, seeds: Array(states[3 ..< 12]))
    }

    private static func makeAuxiliary(_ tables: SourceTables) -> ([UInt32], [UInt32], [UInt8], [UInt8]) {
        let index0: [UInt8] = [0x3C, 0x44, 0x73, 0xCC, 0x50, 0xBA, 0x9E, 0xEE]
        let index1: [UInt8] = [0x9F, 0x72, 0xE1, 0x3B, 0xDD, 0x31, 0x24, 0x8F]
        let map2: [UInt8] = [0xE3, 0x34, 0xDA, 0x73, 0xB4, 0xA0, 0x4F, 0x2B]
        let map3: [UInt8] = [0x1F, 0x35, 0x3B, 0xF7, 0xD9, 0xAD, 0xD4, 0x93]
        var words0 = [UInt32](repeating: 0, count: 256)
        var words1 = words0
        for (index, word) in tables.words.enumerated() {
            words0[Int(linearByte(UInt8(index), basis: index0))] = word ^ 0xD90B_5D96
            words1[Int(linearByte(UInt8(index), basis: index1))] = word ^ 0xAA80_95EE
        }
        let cache2 = tables.cache.map { linearByte($0, basis: map2, constant: 0xC0) }
        let cache3 = tables.cache.enumerated().map { index, value in
            linearByte(value, basis: map3, constant: 0x47) ^ UInt8((index >> 2) & 255)
        }
        return (words0, words1, cache2, cache3)
    }

    private static func linearByte(_ value: UInt8, basis: [UInt8], constant: UInt8 = 0) -> UInt8 {
        var result = constant
        for bit in 0 ..< 8 where value & (1 << bit) != 0 {
            result ^= basis[bit]
        }
        return result
    }

    private static func makeCoefficientCaches(
        _ source: [UInt8], tables: SourceTables, schedule: Schedule,
    ) -> ([UInt32], [UInt32]) {
        var caches: [[UInt32]] = []
        let descriptions: [(Int, Int, [Int], UInt32)] = [
            (10, 0x1A0, SAPParameters.initialOrder, tables.seeds[8] ^ 0xE628_18FC),
            (0, 0x40, SAPParameters.terminalOrder, 0xAF61_5514),
        ]
        for (column, base, order, bias) in descriptions {
            var result = [UInt32](repeating: 0, count: 16)
            var position = 0
            for (row, slot) in order.enumerated() {
                let length = schedule.lengths[row][column]
                if length != 1 {
                    let key = operandKey(source, row: row, position: position, length: length, base: base, column: column)
                    result[slot] = tables.words[key] ^ bias
                }
                position += length
            }
            caches.append(result)
        }
        return (caches[0], caches[1])
    }

    private static func operandKey(
        _ source: [UInt8], row: Int, position: Int, length: Int, base: Int, column: Int,
    ) -> Int {
        var key: UInt8 = 0
        for byte in 0 ..< length {
            key ^=
                source[base + position + byte]
                ^ padColumns[column][(position + byte) % 16] ^ padRows[column][row]
        }
        return Int(key)
    }

    private static func makeMaterial(_ source: [UInt8], schedule: Schedule) -> [UInt8] {
        var material = [UInt8](repeating: 0, count: 576)
        let copies = [
            (0x20, 0xF0), (0x70, 0xE0), (0x120, 0xD0), (0x130, 0x220),
            (0x140, 0x110), (0x150, 0x100), (0x160, 0x80), (0x170, 0x120),
            (0x180, 0x20), (0x190, 0x90), (0x1A0, 0x190), (0x1B0, 0x230),
            (0x1E0, 0xC0), (0x1F0, 0x30),
        ]
        for (destination, origin) in copies {
            material.replaceSubrange(destination ..< destination + 16, with: source[origin ..< origin + 16])
        }
        let descriptions = [
            (1, 0xA0, 0x200), (2, 0x200, 0x1C0), (3, 0x60, 0xC0),
            (4, 0, 0), (5, 0x1C0, 0x50), (6, 0x130, 0x80),
            (7, 0x1E0, 0xA0), (8, 0x170, 0x30), (9, 0x150, 0x100),
        ]
        let offsets = [2, 12, 6, 16, 0, 8, 22, 28, 4, 26, 18, 10, 20, 30, 24, 14]
        var walk = 0
        for (column, base, destination) in descriptions {
            var position = 0
            for row in 0 ..< 16 {
                let length = schedule.lengths[row][column]
                let key = operandKey(source, row: row, position: position, length: length, base: base, column: column)
                walk = (walk + base + position) % 576
                var first = Int(source[walk])
                walk = (walk + base + position + 1) % 576
                first = (first + Int(source[walk])) & 255
                let at = destination + offsets[row]
                material[at] = UInt8(first)
                material[at + 1] = UInt8((key - first) & 255)
                position += length
            }
        }
        // These 64 bytes had no native writer and no algorithm consumer.
        // The address-independent representation normalizes the padding to zero.
        return material
    }

    /// Fixed row/column pad factors recovered from the pinned static data image.
    private static let padColumns: [[UInt8]] = [
        [0x00, 0x2E, 0x79, 0x60, 0xA4, 0x12, 0x40, 0xAD, 0x22, 0xD5, 0xAF, 0x42, 0xB1, 0x49, 0x7B, 0x0E],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9E, 0xD7, 0xFE, 0x6F, 0x93, 0xDA, 0x38, 0x6E, 0xC0, 0xFB],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9E, 0xD7, 0xFE, 0x6F, 0x93, 0xDA, 0x38, 0x6E, 0xC0, 0xFB],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9E, 0xD7, 0xFE, 0x6F, 0x93, 0xDA, 0x38, 0x6E, 0xC0, 0xFB],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9E, 0xD7, 0xFE, 0x6F, 0x93, 0xDA, 0x38, 0x6E, 0xC0, 0xFB],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9E, 0xD7, 0xFE, 0x6F, 0x93, 0xDA, 0x38, 0x6E, 0xC0, 0xFB],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9E, 0xD7, 0xFE, 0x6F, 0x93, 0xDA, 0x38, 0x6E, 0xC0, 0xFB],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9E, 0xD7, 0xFE, 0x6F, 0x93, 0xDA, 0x38, 0x6E, 0xC0, 0xFB],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9E, 0xD7, 0xFE, 0x6F, 0x93, 0xDA, 0x38, 0x6E, 0xC0, 0xFB],
        [0x00, 0x41, 0x84, 0x24, 0x27, 0x14, 0x9E, 0xD7, 0xFE, 0x6F, 0x93, 0xDA, 0x38, 0x6E, 0xC0, 0xFB],
        [0x00, 0xBF, 0x39, 0x19, 0xE1, 0x30, 0xF6, 0x03, 0x1D, 0x72, 0xF1, 0x04, 0x63, 0x14, 0xCB, 0x50],
    ]
    private static let padRows: [[UInt8]] = [
        [0x4D, 0x01, 0xFD, 0x1F, 0xBD, 0xB5, 0xD0, 0xC4, 0xF2, 0xFF, 0x9C, 0x5F, 0x0D, 0x8F, 0x47, 0x61],
        [0x3E, 0x15, 0x55, 0x00, 0xC9, 0x2E, 0x05, 0x73, 0x67, 0x03, 0x74, 0x0A, 0x94, 0x5A, 0x91, 0x62],
        [0x91, 0xF9, 0xB5, 0x2F, 0x28, 0xA7, 0xC0, 0x2C, 0x3F, 0xD4, 0xC4, 0x56, 0xDB, 0xFE, 0x25, 0x44],
        [0x0F, 0x30, 0x9D, 0x17, 0x57, 0xE7, 0x2D, 0x4B, 0x18, 0x43, 0x99, 0x6D, 0xB3, 0xCD, 0xCC, 0x59],
        [0x94, 0xE2, 0x6C, 0xE1, 0xB3, 0x75, 0x31, 0xDA, 0xDB, 0x46, 0xD8, 0xC7, 0x18, 0xFB, 0x64, 0xEE],
        [0x45, 0xD0, 0x7F, 0x57, 0x86, 0xD5, 0x3E, 0xFD, 0x2D, 0xE3, 0x96, 0x4A, 0x45, 0x68, 0x82, 0xD4],
        [0xA4, 0xAC, 0x08, 0x0E, 0x52, 0x09, 0x46, 0x83, 0x0F, 0x9A, 0xA0, 0xB9, 0x3A, 0x82, 0x52, 0x1D],
        [0x3B, 0xBD, 0xC1, 0x21, 0x19, 0xC4, 0xF7, 0xD2, 0x66, 0x2E, 0x27, 0x1B, 0x2C, 0xDC, 0x05, 0x76],
        [0x24, 0xCF, 0x99, 0x39, 0x4D, 0x7B, 0x1E, 0x9B, 0x5B, 0x25, 0x49, 0xF0, 0x07, 0x89, 0x3C, 0xF6],
        [0x5A, 0x1F, 0x9A, 0x95, 0x67, 0x14, 0xF4, 0x7E, 0x4C, 0x41, 0xCD, 0xFE, 0x3B, 0xB8, 0x81, 0x78],
        [0x61, 0x5D, 0x85, 0xDF, 0xA9, 0x9D, 0xBC, 0x20, 0xE1, 0xD2, 0x80, 0xCD, 0x8A, 0x53, 0x04, 0x87],
    ]
}
