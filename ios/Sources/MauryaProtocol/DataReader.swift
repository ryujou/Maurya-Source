import Foundation

/// Bounds-checked sequential binary reader that works with both `Data` and slices.
public struct DataReader: Sendable {
    public let data: Data
    public private(set) var offset: Int

    public init(data: Data, offset: Int = 0) throws {
        guard offset >= 0, offset <= data.count else {
            throw BinaryCodingError.outOfBounds(
                offset: offset,
                requestedByteCount: 0,
                availableByteCount: data.count
            )
        }
        self.data = data
        self.offset = offset
    }

    public var remainingByteCount: Int {
        data.count - offset
    }

    public mutating func readUInt8() throws -> UInt8 {
        let bytes = try readBytes(count: 1)
        return bytes[bytes.startIndex]
    }

    public mutating func readUInt16BigEndian() throws -> UInt16 {
        let high = UInt16(try readUInt8())
        let low = UInt16(try readUInt8())
        return (high << 8) | low
    }

    public mutating func readUInt16LittleEndian() throws -> UInt16 {
        let low = UInt16(try readUInt8())
        let high = UInt16(try readUInt8())
        return low | (high << 8)
    }

    public mutating func readUInt32BigEndian() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            value = (value << 8) | UInt32(try readUInt8())
        }
        return value
    }

    public mutating func readUInt32LittleEndian() throws -> UInt32 {
        var value: UInt32 = 0
        for shift in stride(from: 0, through: 24, by: 8) {
            value |= UInt32(try readUInt8()) << UInt32(shift)
        }
        return value
    }

    public mutating func readBytes(count: Int) throws -> Data {
        guard count >= 0, count <= remainingByteCount else {
            throw BinaryCodingError.outOfBounds(
                offset: offset,
                requestedByteCount: count,
                availableByteCount: remainingByteCount
            )
        }

        let lowerBound = data.index(data.startIndex, offsetBy: offset)
        let upperBound = data.index(lowerBound, offsetBy: count)
        offset += count
        return Data(data[lowerBound..<upperBound])
    }
}
