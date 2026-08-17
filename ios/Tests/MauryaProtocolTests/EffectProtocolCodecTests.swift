import Foundation
import MauryaProtocol
import Testing

struct EffectProtocolCodecTests {
    @Test func parsesBeginAndAcceptedSequenceResponses() throws {
        let begin = try ModbusRequest.vendor(
            unitID: 1,
            payload: Data([0x20, 0x00, 0x30, 0x04, 0x78, 0x56, 0x34, 0x12])
        )
        #expect(try EffectProtocolCodec.parseBeginResponse(begin, expectedUnitID: 1) == 0x1234_5678)

        let frameAck = try ModbusRequest.vendor(
            unitID: 1,
            payload: Data([0x21, 0x00, 0x31, 0x02, 0x56, 0x34])
        )
        let response = try EffectProtocolCodec.parseAcknowledgement(
            frameAck,
            command: .groupFrame,
            expectedUnitID: 1
        )
        #expect(try EffectProtocolCodec.parseAcceptedSequence(from: response) == 0x3456)
    }

    @Test func geometryControlsRequiredGroupAndPixelCounts() throws {
        #expect(throws: EffectProtocolError.invalidGroupCount(expected: 7, actual: 0)) {
            try EffectProtocolCodec.groupFrameRequest(
                unitID: 1,
                sessionID: 1,
                sequence: 1,
                groups: []
            )
        }
        #expect(throws: EffectProtocolError.invalidPixelCount(expected: 42, actual: 0)) {
            try EffectProtocolCodec.pixelFrameRequest(
                unitID: 1,
                sessionID: 1,
                sequence: 1,
                pixels: []
            )
        }

        let oversizedGeometry = try EffectGeometry(groupCount: 8, pixelsPerGroup: 10)
        let pixels = Array(repeating: EffectRGB(red: 0, green: 0, blue: 0), count: 80)
        #expect(throws: EffectProtocolError.geometryNotWireEncodable(pixelCount: 80)) {
            try EffectProtocolCodec.pixelFrameRequest(
                unitID: 1,
                sessionID: 1,
                sequence: 1,
                pixels: pixels,
                geometry: oversizedGeometry
            )
        }
    }
}
