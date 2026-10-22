/// The final 17-to-16-byte transform: lookup, projection and cache decoding.
struct SAPTerminal: Sendable {
    private static let sources = [4, 10, -1, 7, 11, 2, 0, 1, 16, 9, 3, 6, 12, 5, 15, 14]
    private static let tableOrder = [13, 5, 10, 2, 14, 1, 11, 8, 6, 9, 0, 15, 4, 7, 3, 12]
    private static let coefficientOrder = [3, 1, 6, 8, 10, 4, 0, 12, 7, 2, 13, 5, 14, 15, 9, 11]
    private static let destinations = [13, 5, 10, 2, 14, 1, 11, 8, 6, 9, 0, 15, 4, 7, 3, 12]

    private let wordTables: [[UInt32]]
    private let auxiliary: [UInt32]
    private let cache: [UInt8]
    private let laneKeys: [UInt32]
    private let projectionMask: UInt32
    private let outputSeeds: [UInt8]

    init(wordTables: [[UInt32]], source: SAPSource, parameters: SAPParameters, updatedField: [UInt8]) throws {
        guard wordTables.count == 16, wordTables.allSatisfy({ $0.count == 256 }),
              source.auxiliaryWords0.count == 256, !source.cache3.isEmpty,
              parameters.terminalCoefficients.count == 16, parameters.terminalSeeds.count == 7,
              updatedField.count == 16, source.selectors.count == 16,
              source.selectors.allSatisfy({ $0 < 7 })
        else {
            throw SAPError.invalidInput("Invalid terminal parameters")
        }
        self.wordTables = wordTables
        auxiliary = source.auxiliaryWords0
        cache = source.cache3.enumerated().map { index, byte in
            byte ^ UInt8(truncatingIfNeeded: index >> 2) ^ 0xFA
        }
        projectionMask = source.projectionMask
        outputSeeds = source.selectors.map { parameters.terminalSeeds[Int($0)] }
        laneKeys = (0 ..< 16).map { lane in
            let field = updatedField[Self.destinations[lane]] ^ 0x2D
            return parameters.terminalCoefficients[Self.coefficientOrder[lane]]
                ^ source.auxiliaryWords0[Int(field)] ^ 0xAF61_5514
        }
    }

    /// The extra coordinate couples four state bytes using byte arithmetic.
    private static func coupledCoordinate(_ state: [UInt8]) -> Int {
        let left = (((Int(state[12]) ^ 0x31) + 0x6A) ^ 0x2D) - 0x80
        var middle = ((Int(state[14]) ^ 0xD2) + 0x4C + left) & 255
        middle = (((middle ^ Int(state[13])) + 1) ^ 0x7E) & 255
        return (middle + (Int(state[15]) ^ 0x2D)) & 255
    }

    func decode(_ state: [UInt8]) -> [UInt8] {
        assert(state.count == 17)
        let coupled = Int(state[8] ^ state[13])
        let mixing = Self.coupledCoordinate(state)
        var output = outputSeeds
        for lane in 0 ..< 16 {
            let position = Self.sources[lane]
            let index = position < 0 ? coupled : Int(state[position] ^ 0x2D)
            var word = wordTables[Self.tableOrder[lane]][index]
            if position < 0 {
                // A[0] remains a session-dependent term of the four-point difference.
                word ^=
                    auxiliary[coupled ^ mixing] ^ auxiliary[mixing]
                    ^ auxiliary[coupled] ^ auxiliary[0]
            }
            word ^= laneKeys[lane]
            let cacheIndex = Int(word & projectionMask) % cache.count
            output[Self.destinations[lane]] ^= cache[cacheIndex]
        }
        return output
    }
}
