/// Recovered E transform, with nine word mixes and eight nonlinear rounds.
struct SAPCipher: Sendable {
    private static let previousSlices = [8, 0, 0, 1, 1, 1, 4, 2, 2]
    private static let indexSources = [15, 5, 2, 10, 11, 7, 9, 13, 4, 3, 12, 8, 16, 0, 1, 14]
    private static let firstWordTables = [28, 39, 50, 61, 28, 39, 50, 61, 56, 67, 6, 17, 56, 67, 6, 17]
    private static let outputColumns = [1, 3, 1, 2, 3, 3, 2, 3, -1, 0, 2, 0, 0, 2, 1, 0, 1]
    private static let outputShifts = [24, 0, 8, 0, 8, 24, 24, 16, 0, 8, 8, 16, 0, 16, 0, 24, 16]
    private static let outputXors: [UInt8] = [
        0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0x2D, 0, 0xA0, 0x2D, 0x75, 0x32, 0, 0x2D, 0xBB, 0x2D,
    ]

    private let parameters: SAPParameters
    private let initial: SAPInitialEncoder
    private let terminal: SAPTerminal
    private let carryFrames: [[UInt8]]
    private let wordTables: [[UInt32]]
    private let nonlinearTables: [[[UInt8]]]

    init(source: [UInt8], tables: SAPStaticTables) throws {
        guard tables.byteTables.count >= 200, tables.byteTables.allSatisfy({ $0.count == 256 }),
              tables.wordTables.count >= 72, tables.wordTables.allSatisfy({ $0.count == 256 }),
              tables.carryMasks.map(\.count) == [233, 239, 241, 251]
        else {
            throw SAPError.invalidInput("Invalid E static tables")
        }
        let source = try SAPSource.prepare(source)
        let prepared = try SAPPreparedState.prepare(source, byteTables: tables.byteTables)
        let parameters = prepared.parameters
        self.parameters = parameters
        initial = prepared.initial
        wordTables = tables.wordTables
        let field = Self.updateField(parameters.initialField, rawWords: parameters.rawWords[3], masks: tables.carryMasks)
        carryFrames = [
            [0, 2, 11, 12].map { parameters.initialField[$0] },
            [6, 1, 3, 14].map { field[$0] },
            [8, 9, 13, 15].map { field[$0] },
        ]
        terminal = try SAPTerminal(wordTables: prepared.wordTables, source: source, parameters: parameters, updatedField: field)
        nonlinearTables = (0 ..< 8).map { Self.selectNonlinearTables(tables.byteTables, stage: $0) }
    }

    /// This mutation occurs once; the first carry uses the unmodified field.
    private static func updateField(_ field: [UInt8], rawWords: [UInt32], masks: [[UInt8]]) -> [UInt8] {
        let words = [rawWords[2], rawWords[0], rawWords[3], rawWords[1]].map { $0 &+ 0xDE79_2901 }
        let primes = [233, 239, 241, 251]
        let constants: [UInt8] = [0xF6, 0x19, 0x50, 0x8E]
        return (0 ..< 16).map { position in
            let table = position % 4
            let index = Int(words[position / 4] % UInt32(primes[table]))
            return field[position] ^ masks[table][index] ^ constants[table]
        }
    }

    private static func carry(_ frame: [UInt8], block: [UInt8], offset: Int, firstMask: Int) -> UInt8 {
        var value = ((Int(frame[0]) ^ 0x2D) + (Int(block[offset]) ^ firstMask) - (Int(frame[1]) ^ 0x2D)) & 255
        value ^= Int(block[offset + 1]) ^ 0x2D
        value = (value + (Int(frame[2]) ^ 0x2D) - (Int(block[offset + 2]) ^ 0x2D)) & 255
        value ^= Int(frame[3]) ^ 0x2D
        return UInt8((value + (Int(block[offset + 3]) ^ 0x2D)) & 255)
    }

    private static func selectNonlinearTables(_ tables: [[UInt8]], stage: Int) -> [[UInt8]] {
        let keyOrder = [12, 0, 1, 8, 5, 7, 9, 4, 2, 14, 11, 13, 3, 10, 15, 6]
        let positionOrder = [4, 0, 15, 8, 11, 9, 7, 12, 14, 2, 5, 3, 13, 6, 1, 10]
        let starts = [2, 4, 8, 3, 7, 2, 6, 1, 5, 0, 4, 8, 3, 7, 2, 6]
        var selected = [[UInt8]](repeating: [], count: 16)
        for lane in 0 ..< 16 {
            let position = positionOrder[lane]
            let round = (starts[position] + 2 * stage) % 9
            selected[keyOrder[lane]] = tables[40 + 16 * round + position]
        }
        return selected
    }

    private static func nonlinearRound(_ state: [UInt8], tables: [[UInt8]], carry: UInt8) -> [UInt8] {
        let destinations = [0, 2, 3, 4, 5, 8, 9, 10, 11, 12, 13, 14, 15, 16]
        let tableOrder = [9, 6, 1, 0, 5, 3, 14, 7, 12, 2, 15, 11, 4, 8]
        let sources = [9, 16, 2, 3, 10, 15, 11, 5, 14, 7, 6, 0, 12, 1]
        var output = [UInt8](repeating: 0, count: 17)
        for lane in destinations.indices {
            output[destinations[lane]] = tables[tableOrder[lane]][Int(state[sources[lane]] ^ 0x2D)]
        }
        output[1] = tables[10][Int(state[8] ^ state[13])]
        output[6] = carry ^ output[3] ^ output[4] ^ output[5]
        output[7] = output[6] ^ tables[13][Int(state[4] ^ 0x2D)]
        return output
    }

    private func mix(_ state: [UInt8], previous: [UInt8], stage: Int, carry: UInt8) -> [UInt8] {
        let key = parameters.roundKeys[stage]
        var accumulators = parameters.rawWords[stage].map { $0 &+ 0xDE79_2901 }
        accumulators[0] ^= 0x9658_8D1F
        for lane in 0 ..< 16 {
            var index = state[Self.indexSources[lane]] ^ key[lane]
            if lane == 5 {
                index ^= state[6]
            }
            let table = (Self.firstWordTables[lane] - 16 * stage + 144) % 72
            accumulators[lane / 4] ^= wordTables[table][Int(index)]
        }
        let byte11 = UInt8(truncatingIfNeeded: accumulators[0] >> 16) ^ 0x75
        let byte8 = previous[16] ^ previous[8] ^ byte11 ^ state[9] ^ key[6] ^ carry
        var output = [UInt8](repeating: 0, count: 17)
        // The old target is copied from previous before each mix, cancelling
        // the old XOR previous term at every ordinary output position.
        for position in 0 ..< 17 where position != 8 {
            let word = accumulators[Self.outputColumns[position]]
            output[position] = UInt8(truncatingIfNeeded: word >> Self.outputShifts[position]) ^ Self.outputXors[position]
        }
        output[8] = byte8
        output[13] ^= byte8
        return output
    }

    func encrypt(_ block: [UInt8]) throws -> [UInt8] {
        guard block.count == 16 else {
            throw SAPError.invalidInput("E requires a sixteen-byte block")
        }
        let masked = block.map { $0 ^ 0x2D }
        var state = initial.encodeMasked(masked)
        let carries = [
            Self.carry(carryFrames[0], block: masked, offset: 0, firstMask: 0x20),
            Self.carry(carryFrames[1], block: masked, offset: 4, firstMask: 0x26),
            Self.carry(carryFrames[2], block: masked, offset: 8, firstMask: 0x28),
        ]
        var expanded = [UInt8]()
        expanded.reserveCapacity(17)
        for position in 0 ..< 17 {
            let sourcePosition: Int = (3 + 7 * position) % 16
            let unmasked: UInt8 = masked[sourcePosition] ^ 0x2D
            let incremented = UInt8((Int(unmasked) + position) & 255)
            expanded.append(incremented ^ 0x2D)
        }
        var slices = [[UInt8]](repeating: [], count: 9)
        slices[0] = expanded
        slices[8] = expanded
        for stage in 0 ..< 9 {
            let carry = carries[stage < 4 ? 0 : stage < 8 ? 1 : 2]
            let mixed = mix(state, previous: slices[Self.previousSlices[stage]], stage: stage, carry: carry)
            if stage == 8 {
                return terminal.decode(mixed).map { $0 ^ 0x2D }
            }
            slices[stage] = mixed
            state = Self.nonlinearRound(mixed, tables: nonlinearTables[stage], carry: carry)
        }
        preconditionFailure("Nine E stages must produce an output")
    }
}
