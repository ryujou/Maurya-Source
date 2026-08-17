import Foundation
import MauryaProtocol
import Testing

struct OTAProtocolCodecTests {
    @Test func encodesRemainingCommandOnlyRequests() throws {
        for (command, frame) in [
            (OTACommand.cancelPrepare, try OTAProtocolCodec.cancelPrepareRequest(unitID: 1)),
            (OTACommand.bleCommit, try OTAProtocolCodec.bleCommitRequest(unitID: 1)),
            (OTACommand.bleCancel, try OTAProtocolCodec.bleCancelRequest(unitID: 1)),
        ] {
            #expect(ModbusCRC16.validates(frame))
            #expect(frame[frame.index(frame.startIndex, offsetBy: 3)] == command.rawValue)
        }
    }

    @Test func validatesNonceHashSizeAndFirmwareDataBounds() {
        #expect(throws: OTAProtocolError.invalidNonceByteCount(actual: 15, required: 16)) {
            try OTAProtocolCodec.prepareRequest(unitID: 1, nonce: Data(repeating: 0, count: 15))
        }
        #expect(throws: OTAProtocolError.invalidFirmwareSize(0)) {
            try OTAProtocolCodec.bleBeginRequest(
                unitID: 1,
                expectedBytes: 0,
                sha256: Data(repeating: 0, count: 32)
            )
        }
        #expect(throws: OTAProtocolError.invalidSHA256ByteCount(actual: 31, required: 32)) {
            try OTAProtocolCodec.bleBeginRequest(
                unitID: 1,
                expectedBytes: 1,
                sha256: Data(repeating: 0, count: 31)
            )
        }
        #expect(
            throws: OTAProtocolError.invalidFirmwareDataByteCount(actual: 0, minimum: 1, maximum: 118)
        ) {
            try OTAProtocolCodec.bleDataRequest(unitID: 1, offset: 0, firmwareData: Data())
        }
        #expect(
            throws: OTAProtocolError.invalidFirmwareDataByteCount(actual: 119, minimum: 1, maximum: 118)
        ) {
            try OTAProtocolCodec.bleDataRequest(
                unitID: 1,
                offset: 0,
                firmwareData: Data(repeating: 0, count: 119)
            )
        }
    }

    @Test func parsesBasicOTAResponseEnvelope() throws {
        let frame = try ModbusRequest.vendor(unitID: 1, payload: Data([0x12, 0x00]))
        let response = try OTAProtocolCodec.parseResponse(
            frame,
            command: .bleStatus,
            expectedUnitID: 1
        )
        #expect(response.command == OTACommand.bleStatus.rawValue)
        #expect(response.data.isEmpty)
    }
}
