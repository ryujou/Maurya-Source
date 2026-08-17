import Foundation
import MauryaProtocol
import Testing

struct DataReaderTests {
    @Test func readsExplicitEndiannessAndAdvancesOffset() throws {
        var reader = try DataReader(data: Data([0x12, 0x34, 0x78, 0x56, 0xAB]))

        #expect(try reader.readUInt16BigEndian() == 0x1234)
        #expect(try reader.readUInt16LittleEndian() == 0x5678)
        #expect(try reader.readUInt8() == 0xAB)
        #expect(reader.remainingByteCount == 0)
    }

    @Test func readsDataCreatedFromSliceWithoutUsingRawOffsets() throws {
        let source = Data([0xFF, 0x11, 0x22, 0x33])
        let slice = source[source.index(after: source.startIndex)..<source.endIndex]
        var reader = try DataReader(data: Data(slice))

        #expect(try reader.readUInt16BigEndian() == 0x1122)
        #expect(try reader.readUInt8() == 0x33)
    }

    @Test func readsThirtyTwoBitValuesInBothByteOrders() throws {
        var reader = try DataReader(data: Data([0x12, 0x34, 0x56, 0x78, 0x78, 0x56, 0x34, 0x12]))

        #expect(try reader.readUInt32BigEndian() == 0x1234_5678)
        #expect(try reader.readUInt32LittleEndian() == 0x1234_5678)
        #expect(reader.remainingByteCount == 0)
    }

    @Test func rejectsOutOfBoundsReads() throws {
        var reader = try DataReader(data: Data([0x01]))

        #expect(
            throws: BinaryCodingError.outOfBounds(
                offset: 0,
                requestedByteCount: 2,
                availableByteCount: 1
            )
        ) {
            try reader.readBytes(count: 2)
        }
    }

    @Test func rejectsInvalidInitialOffset() {
        #expect(
            throws: BinaryCodingError.outOfBounds(
                offset: 2,
                requestedByteCount: 0,
                availableByteCount: 1
            )
        ) {
            try DataReader(data: Data([0x01]), offset: 2)
        }
    }

    @Test func rejectsNegativeOffsetsAndReadLengths() throws {
        #expect(throws: BinaryCodingError.self) {
            try DataReader(data: Data(), offset: -1)
        }

        var reader = try DataReader(data: Data())
        #expect(throws: BinaryCodingError.self) {
            try reader.readBytes(count: -1)
        }
    }
}
