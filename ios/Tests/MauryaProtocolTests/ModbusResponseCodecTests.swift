import Foundation
import MauryaProtocol
import Testing

struct ModbusResponseCodecTests {
    @Test func decodesReadHoldingRegisters() throws {
        let response = try ModbusResponseCodec.decode(TestFixtures.readResponse, expectedUnitID: 1)
        #expect(response == .readHoldingRegisters(unitID: 1, values: [0x000A, 0x0102]))
    }

    @Test func decodesWriteAcknowledgements() throws {
        #expect(
            try ModbusResponseCodec.decode(TestFixtures.writeSingleResponse)
                == .writeSingleAcknowledgement(unitID: 1, register: 0x0020, value: 0x1234)
        )
        #expect(
            try ModbusResponseCodec.decode(TestFixtures.writeMultipleResponse)
                == .writeMultipleAcknowledgement(unitID: 1, startRegister: 0x0020, quantity: 35)
        )
    }

    @Test func decodesVendorAndExceptionResponses() throws {
        #expect(
            try ModbusResponseCodec.decode(TestFixtures.vendorResponse)
                == .vendor(unitID: 1, payload: Data([0x10, 0x20, 0x30]))
        )
        #expect(
            try ModbusResponseCodec.decode(TestFixtures.exceptionResponse)
                == .exception(unitID: 1, function: 0x83, code: 0x03)
        )
    }

    @Test func rejectsOddReadByteCount() {
        let frame = ModbusCRC16.appendingChecksum(to: Data([0x01, 0x03, 0x01, 0xAA]))
        #expect(throws: ModbusError.invalidByteCount(1)) {
            try ModbusResponseCodec.decode(frame)
        }
    }

    @Test func rejectsEmptyReadPayload() {
        let frame = ModbusCRC16.appendingChecksum(to: Data([0x01, 0x03, 0x00]))
        #expect(throws: ModbusError.invalidByteCount(0)) {
            try ModbusResponseCodec.decode(frame)
        }
    }

    @Test func rejectsWrongUnitAndChecksum() {
        #expect(throws: ModbusError.unexpectedUnitID(expected: 2, actual: 1)) {
            try ModbusResponseCodec.decode(TestFixtures.readResponse, expectedUnitID: 2)
        }

        var corrupted = TestFixtures.readResponse
        corrupted[corrupted.startIndex] ^= 0x01
        #expect(throws: ModbusError.checksumMismatch) {
            try ModbusResponseCodec.decode(corrupted)
        }
    }

    @Test func rejectsShortAndLengthMismatchedFrames() {
        #expect(throws: ModbusError.frameTooShort(actual: 4, minimum: 5)) {
            try ModbusResponseCodec.decode(Data(repeating: 0, count: 4))
        }

        let truncatedRead = ModbusCRC16.appendingChecksum(to: Data([0x01, 0x03, 0x02, 0x00]))
        #expect(throws: ModbusError.lengthMismatch(expected: 7, actual: 6)) {
            try ModbusResponseCodec.decode(truncatedRead)
        }
    }
}
