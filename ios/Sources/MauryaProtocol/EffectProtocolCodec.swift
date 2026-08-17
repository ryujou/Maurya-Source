import Foundation

public enum EffectProtocolCodec {
    public static let volatileEffectCapability: UInt8 = 0x20
    public static let pixelEffectCapability: UInt8 = 0x40
    public static let rgb888PixelFormat: UInt8 = 1

    public static func beginRequest(unitID: UInt8) throws -> Data {
        try request(unitID: unitID, command: .begin)
    }

    public static func groupFrameRequest(
        unitID: UInt8,
        sessionID: UInt32,
        sequence: UInt16,
        groups: [EffectGroupState],
        geometry: EffectGeometry = .legacyFirmwareFallback
    ) throws -> Data {
        let expectedCount = Int(geometry.groupCount)
        guard groups.count == expectedCount else {
            throw EffectProtocolError.invalidGroupCount(expected: expectedCount, actual: groups.count)
        }

        var writer = DataWriter(capacity: 7 + groups.count * 6)
        writer.append(EffectCommand.groupFrame.rawValue)
        writer.appendLittleEndian(sessionID)
        writer.appendLittleEndian(sequence)
        for group in groups {
            writer.append(group.innerMode)
            writer.appendLittleEndian(group.hue)
            writer.append(group.saturation)
            writer.append(group.value)
            writer.append(group.innerParameter)
        }
        return try VendorEnvelopeCodec.request(unitID: unitID, payload: writer.data)
    }

    public static func heartbeatRequest(unitID: UInt8, sessionID: UInt32) throws -> Data {
        try sessionRequest(unitID: unitID, command: .heartbeat, sessionID: sessionID)
    }

    public static func endRequest(unitID: UInt8, sessionID: UInt32) throws -> Data {
        try sessionRequest(unitID: unitID, command: .end, sessionID: sessionID)
    }

    public static func pixelFrameRequest(
        unitID: UInt8,
        sessionID: UInt32,
        sequence: UInt16,
        pixels: [EffectRGB],
        geometry: EffectGeometry = .legacyFirmwareFallback
    ) throws -> Data {
        let expectedCount = geometry.pixelCount
        guard pixels.count == expectedCount else {
            throw EffectProtocolError.invalidPixelCount(expected: expectedCount, actual: pixels.count)
        }
        guard expectedCount <= Int(UInt8.max),
            9 + expectedCount * 3 <= ModbusRequest.maximumVendorPayloadByteCount
        else {
            throw EffectProtocolError.geometryNotWireEncodable(pixelCount: expectedCount)
        }

        var writer = DataWriter(capacity: 9 + pixels.count * 3)
        writer.append(EffectCommand.pixelFrame.rawValue)
        writer.appendLittleEndian(sessionID)
        writer.appendLittleEndian(sequence)
        writer.append(rgb888PixelFormat)
        writer.append(UInt8(expectedCount))
        for pixel in pixels {
            writer.append(pixel.red)
            writer.append(pixel.green)
            writer.append(pixel.blue)
        }
        return try VendorEnvelopeCodec.request(unitID: unitID, payload: writer.data)
    }

    public static func parseBeginResponse(
        _ frame: Data,
        expectedUnitID: UInt8? = nil
    ) throws -> UInt32 {
        let response = try VendorEnvelopeCodec.decodeResponse(
            frame,
            expectedCommand: EffectCommand.begin.rawValue,
            expectedUnitID: expectedUnitID
        )
        let values = try VendorTLVCodec.decode(response.data)
        return try VendorTLVCodec.littleEndianUInt32(type: 0x30, in: values)
    }

    public static func parseAcknowledgement(
        _ frame: Data,
        command: EffectCommand,
        expectedUnitID: UInt8? = nil
    ) throws -> VendorResponseEnvelope {
        try VendorEnvelopeCodec.decodeResponse(
            frame,
            expectedCommand: command.rawValue,
            expectedUnitID: expectedUnitID
        )
    }

    public static func parseAcceptedSequence(from response: VendorResponseEnvelope) throws -> UInt16 {
        let values = try VendorTLVCodec.decode(response.data)
        return try VendorTLVCodec.littleEndianUInt16(type: 0x31, in: values)
    }

    private static func request(unitID: UInt8, command: EffectCommand) throws -> Data {
        try VendorEnvelopeCodec.request(unitID: unitID, payload: Data([command.rawValue]))
    }

    private static func sessionRequest(
        unitID: UInt8,
        command: EffectCommand,
        sessionID: UInt32
    ) throws -> Data {
        var writer = DataWriter(capacity: 5)
        writer.append(command.rawValue)
        writer.appendLittleEndian(sessionID)
        return try VendorEnvelopeCodec.request(unitID: unitID, payload: writer.data)
    }
}
