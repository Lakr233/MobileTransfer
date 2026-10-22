// Copyright (c) 2026 ApplePackage contributors.

/// Sixteen finite byte maps obtained by projecting the source word table.
struct SAPInitialEncoder: Sendable {
    let tables: [[UInt8]]

    private static let destinations = [4, 5, 1, 13, 15, 0, 9, 8, 16, -1, 12, 10, 11, 3, 2, 14]

    static func prepare(
        auxiliary: [UInt32], coefficients: [UInt32], caches: [[UInt8]], projectionMask: UInt32,
    ) throws -> SAPInitialEncoder {
        guard auxiliary.count == 256, coefficients.count == 16, caches.count == 16 else {
            throw SAPError.invalidInput("Invalid initial encoder table dimensions")
        }
        guard let size = caches.first?.count, size > 0, caches.allSatisfy({ $0.count == size }) else {
            throw SAPError.invalidInput("Initial byte caches must have the same nonzero length")
        }
        var tables: [[UInt8]] = []
        for source in 0 ..< 16 {
            let coefficient = SAPParameters.initialOrder[source]
            let cache = (5 * source) % 16
            var table: [UInt8] = []
            table.reserveCapacity(256)
            for byte in 0 ..< 256 {
                let word = auxiliary[byte ^ 0x2D] ^ coefficients[coefficient]
                let index = Int(((word ^ 0x4CA8_8D12) & projectionMask) % UInt32(size))
                table.append(caches[cache][index])
            }
            tables.append(table)
        }
        return SAPInitialEncoder(tables: tables)
    }

    func encodeMasked(_ block: [UInt8]) -> [UInt8] {
        precondition(block.count == 16, "Expected sixteen masked input bytes")
        var output = [UInt8](repeating: 0, count: 17)
        for source in 0 ..< 16 {
            let destination = Self.destinations[source]
            if destination >= 0 {
                output[destination] = tables[source][Int(block[source])]
            }
        }
        output[6] = output[4] ^ output[14] ^ output[15]
        output[7] = output[6] ^ tables[9][Int(block[9])]
        return output
    }
}

/// Complete E initialization without encoded descriptors or guest memory.
struct SAPPreparedState: Sendable {
    let parameters: SAPParameters
    let initial: SAPInitialEncoder
    let wordTables: [[UInt32]]

    static func prepare(_ source: SAPSource, byteTables: [[UInt8]]) throws -> SAPPreparedState {
        guard byteTables.count == 200, byteTables.allSatisfy({ $0.count == 256 }) else {
            throw SAPError.invalidInput("Expected 200 static 256-byte tables")
        }
        let material = source.material
        let parameters = try SAPParameters.prepare(
            material, initialCache: source.initialCache, terminalCache: source.terminalCache,
        )
        var wordTables: [[UInt32]] = []
        var caches: [[UInt8]] = []
        for slot in 0 ..< 16 {
            let a = Int(material[0x1F0 + slot] ^ material[0x70 + slot])
            let b = Int(material[0x20 + slot] ^ material[0x70 + slot])
            let wordMask = (a + b) & 255
            let byteTable = byteTables[40 + (79 * slot) % 144]
            wordTables.append(byteTable.map { source.auxiliaryWords0[Int($0) ^ wordMask] })
            let index = (13 * slot) % 16
            let left = Int(material[0x1E0 + index] ^ material[0x70 + index])
            let right = Int(material[0x20 + index] ^ material[0x70 + index])
            let sourceMask = ((left - right) & 255) ^ 0xFE
            let cacheTable = byteTables[184 + (9 * slot) % 16]
            caches.append(source.cache2.map { cacheTable[Int($0) ^ sourceMask] })
        }
        let initial = try SAPInitialEncoder.prepare(
            auxiliary: source.auxiliaryWords1, coefficients: parameters.initialCoefficients,
            caches: caches, projectionMask: source.projectionMask,
        )
        return SAPPreparedState(parameters: parameters, initial: initial, wordTables: wordTables)
    }
}
