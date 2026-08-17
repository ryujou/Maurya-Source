import Foundation
import MauryaProtocol
import Testing

struct VendorEnvelopeCodecTests {
    @Test func decodesSuccessfulResponseAndPreservesData() throws {
        let frame = try ModbusRequest.vendor(
            unitID: 1,
            payload: Data([0x20, 0x00, 0x30, 0x04, 0x78, 0x56, 0x34, 0x12])
        )
        let response = try VendorEnvelopeCodec.decodeResponse(
            frame,
            expectedCommand: 0x20,
            expectedUnitID: 1
        )

        #expect(response.command == 0x20)
        #expect(response.status == 0)
        #expect(response.data == Data([0x30, 0x04, 0x78, 0x56, 0x34, 0x12]))
    }

    @Test func rejectsCommandMismatchAndDeviceFailure() throws {
        let wrongCommand = try ModbusRequest.vendor(unitID: 1, payload: Data([0x21, 0x00]))
        #expect(throws: VendorProtocolError.unexpectedCommand(expected: 0x20, actual: 0x21)) {
            try VendorEnvelopeCodec.decodeResponse(wrongCommand, expectedCommand: 0x20)
        }

        let rejected = try ModbusRequest.vendor(unitID: 1, payload: Data([0x20, 0x01]))
        #expect(throws: VendorProtocolError.commandRejected(command: 0x20, status: 1)) {
            try VendorEnvelopeCodec.decodeResponse(rejected, expectedCommand: 0x20)
        }
    }

    @Test func rejectsNonVendorAndShortVendorResponses() throws {
        #expect(throws: VendorProtocolError.unexpectedModbusResponse) {
            try VendorEnvelopeCodec.decodeResponse(TestFixtures.readResponse)
        }

        let shortPayload = try ModbusRequest.vendor(unitID: 1, payload: Data([0x20]))
        #expect(throws: VendorProtocolError.responsePayloadTooShort(actual: 1, minimum: 2)) {
            try VendorEnvelopeCodec.decodeResponse(shortPayload)
        }
    }
}
