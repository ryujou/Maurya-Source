import Foundation

/// Explicit-endian binary writer used by wire codecs.
public struct DataWriter: Sendable {
    public private(set) var data: Data

    public init(capacity: Int = 0) {
        data = Data()
        data.reserveCapacity(max(0, capacity))
    }

    public mutating func append(_ value: UInt8) {
        data.append(value)
    }

    public mutating func appendBigEndian(_ value: UInt16) {
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }

    public mutating func appendLittleEndian(_ value: UInt16) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    public mutating func appendLittleEndian(_ value: UInt32) {
        for shift in stride(from: 0, through: 24, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    public mutating func append(contentsOf bytes: Data) {
        data.append(bytes)
    }
}
