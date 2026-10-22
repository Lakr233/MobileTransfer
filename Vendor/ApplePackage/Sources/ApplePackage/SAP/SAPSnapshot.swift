import Foundation

private struct SnapshotPatch: Decodable {
    let offset: Int
    let hex: String
    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        offset = try values.decode(Int.self)
        hex = try values.decode(String.self)
    }
}

private struct SnapshotAllocator: Decodable {
    let heapCursor: UInt64
    let freeBlocks: [[UInt64]]
    enum CodingKeys: String, CodingKey {
        case heapCursor = "heap_cursor", freeBlocks = "free_blocks"
    }
}

private struct OriginalSnapshot: Decodable {
    let phase: String
    let context: UInt64
    let heapBase: UInt64
    let heapHex: String
    let dataBase: UInt64
    let dataSize: Int
    let dataPatches: [SnapshotPatch]
    let allocator: SnapshotAllocator
    enum CodingKeys: String, CodingKey {
        case phase, context, allocator
        case heapBase = "heap_base", heapHex = "heap_hex", dataBase = "data_base"
        case dataSize = "data_size", dataPatches = "data_patches"
    }
}

enum SAPSnapshot {
    static func decode(_ snapshot: Data, ivAddress: UInt64) throws -> SAPSession {
        let saved = try JSONDecoder().decode(OriginalSnapshot.self, from: snapshot)
        guard saved.phase == "post_handshake", (0 ... 67_108_864).contains(saved.dataSize) else {
            throw SAPError.invalidInput("requires complete post_handshake snapshot")
        }
        let heap = try SAPBytes.hex(saved.heapHex)
        var data = [UInt8](repeating: 0, count: saved.dataSize)
        for patch in saved.dataPatches {
            let bytes = try SAPBytes.hex(patch.hex)
            guard patch.offset >= 0, patch.offset <= data.count - bytes.count else {
                throw SAPError.invalidInput("data patch outside saved region")
            }
            data.replaceSubrange(patch.offset ..< patch.offset + bytes.count, with: bytes)
        }
        func read(_ address: UInt64, _ width: Int) throws -> UInt64 {
            for (base, bytes) in [(saved.heapBase, heap), (saved.dataBase, data)] {
                if address >= base, address - base <= UInt64(bytes.count),
                   width <= bytes.count - Int(address - base)
                {
                    return try SAPBytes.word(bytes, at: Int(address - base), width: width)
                }
            }
            throw SAPError.invalidInput("context pointer outside saved regions")
        }
        func memory(_ address: UInt64, _ count: Int) throws -> Data {
            guard count >= 0, address >= saved.heapBase, address - saved.heapBase <= UInt64(heap.count),
                  count <= heap.count - Int(address - saved.heapBase)
            else {
                throw SAPError.invalidInput("session pointer outside saved heap")
            }
            let offset = Int(address - saved.heapBase)
            return Data(heap[offset ..< offset + count])
        }
        let header = (saved.context ^ 0x751F_4695_9884_2008) &+ 0x8AE0_B96A_677B_DFF8
        let pointer = try read(header &+ 0x20, 8)
        let selector = try read(saved.dataBase &+ 0x46CD4, 4) & 0x5B31_E844
        let seedAddress = try read(saved.dataBase &+ 0x46CC8, 8) &+ selector
        let key = try (UInt32(truncatingIfNeeded: pointer) &* 0x5B31_E847) ^ UInt32(read(seedAddress, 4))
        var raw = try (0 ..< 0x310).map { try UInt8(read(pointer &+ UInt64($0), 1)) }
        for i in 1 ..< 98 {
            let position = Int(((key &+ UInt32(i)) ^ key) &* 0x0100_0193) % i
            let left = Array(raw[8 * i ..< 8 * i + 8])
            let right = Array(raw[8 * position ..< 8 * position + 8])
            raw.replaceSubrange(8 * i ..< 8 * i + 8, with: right)
            raw.replaceSubrange(8 * position ..< 8 * position + 8, with: left)
        }
        for i in raw.indices {
            let lowKey = Int(key & 255)
            raw[i] = UInt8(truncatingIfNeeded: (155 * Int(raw[i])) ^ lowKey ^ ((i + lowKey) * (i - lowKey)))
        }
        func word(_ offset: Int, _ width: Int = 8) throws -> UInt64 {
            try SAPBytes.word(raw, at: offset, width: width)
        }
        let f2Length = try Int(word(0x288, 4))
        guard (16 ... 32).contains(f2Length), try word(0x230, 4) == 159 else {
            throw SAPError.invalidInput("decoded F2/F3 length mismatch")
        }
        let source = try memory(word(0x2A0), 576)
        let f2Input1 = try memory(word(0x2B0), 16)
        let f2Input2 = try memory(word(0x280), 16)
        let tail = try memory(word(0x280) &+ 16, f2Length - 16).map { $0 ^ 0x2D }
        let f3 = try memory(word(0x228), 159).map { $0 ^ 0x2D }
        let cachedF1 = try word(0x2E0)
        guard cachedF1 == 0 else {
            throw SAPError.invalidInput("requires an unused post-handshake snapshot, before the first signature")
        }
        var cursor = saved.allocator.heapCursor
        var freeBlocks = saved.allocator.freeBlocks
        guard freeBlocks.allSatisfy({ $0.count == 2 }) else {
            throw SAPError.invalidInput("invalid allocator free block")
        }
        func allocate(_ size: UInt64) throws -> UInt64 {
            let reserved = (max(1, size) + 15) & ~UInt64(15)
            for i in freeBlocks.indices where freeBlocks[i][1] >= reserved {
                let address = freeBlocks[i][0]
                if freeBlocks[i][1] == reserved {
                    freeBlocks.remove(at: i)
                } else {
                    freeBlocks[i] = [address &+ reserved, freeBlocks[i][1] - reserved]
                }
                return address
            }
            let (address, overflow) = saved.heapBase.addingReportingOverflow(cursor)
            let (next, nextOverflow) = cursor.addingReportingOverflow(reserved)
            guard !overflow, !nextOverflow else { throw SAPError.invalidInput("allocator address overflow") }
            cursor = next
            return address
        }
        _ = try allocate(UInt64(f2Length + 4))
        let firstMaterial = try allocate(256) &+ 68
        let words = try (0 ..< 624).map { try UInt32(SAPBytes.word(data, at: 0x46CE8 + 4 * $0, width: 4)) }
        return try SAPSession(
            source: source, f2Input1: f2Input1, f2Input2: f2Input2,
            f2Tail: Data(tail), f3: Data(f3), randomWords: words,
            randomCursor: UInt32(SAPBytes.word(data, at: 0x476B4, width: 4)),
            seed30: UInt32(SAPBytes.word(heap, at: 0x30, width: 4)),
            seed54: UInt32(SAPBytes.word(heap, at: 0x54, width: 4)),
            f1MaterialAddress: firstMaterial, ivAddress: ivAddress,
        )
    }
}
