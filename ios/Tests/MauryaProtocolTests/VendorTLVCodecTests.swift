import Foundation
import MauryaProtocol
import Testing

struct VendorTLVCodecTests {
    @Test func roundTripsUnknownTypesAndUsesLastDuplicate() throws {
        let values = [
            VendorTLV(type: 0x30, value: Data([1, 0, 0, 0])),
            VendorTLV(type: 0xFE, value: Data([0xAA])),
            VendorTLV(type: 0x30, value: Data([2, 0, 0, 0])),
        ]
        let decoded = try VendorTLVCodec.decode(VendorTLVCodec.encode(values))

        #expect(decoded == values)
        #expect(try VendorTLVCodec.littleEndianUInt32(type: 0x30, in: decoded) == 2)
    }

    @Test func truncatedHeaderAndValueAreRejected() {
        #expect(throws: VendorProtocolError.truncatedTLVHeader(offset: 0)) {
            try VendorTLVCodec.decode(Data([0x01]))
        }
        #expect(throws: VendorProtocolError.truncatedTLVValue(type: 1, expected: 2, available: 1)) {
            try VendorTLVCodec.decode(Data([0x01, 0x02, 0xAA]))
        }
    }

    @Test func rejectsOversizedAndMissingOrMalformedValues() throws {
        #expect(throws: ModbusError.vendorPayloadTooLarge(actual: 256, maximum: 255)) {
            try VendorTLVCodec.encode([VendorTLV(type: 1, value: Data(repeating: 0, count: 256))])
        }
        #expect(throws: VendorProtocolError.missingTLV(type: 0x99)) {
            try VendorTLVCodec.lastValue(for: 0x99, in: [])
        }

        let malformed16 = [VendorTLV(type: 1, value: Data([0]))]
        #expect(throws: VendorProtocolError.invalidTLVLength(type: 1, expected: 2, actual: 1)) {
            try VendorTLVCodec.littleEndianUInt16(type: 1, in: malformed16)
        }

        let malformed32 = [VendorTLV(type: 2, value: Data([0, 0, 0]))]
        #expect(throws: VendorProtocolError.invalidTLVLength(type: 2, expected: 4, actual: 3)) {
            try VendorTLVCodec.littleEndianUInt32(type: 2, in: malformed32)
        }
    }
}
