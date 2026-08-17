import Foundation

public enum OTAProtocolCodec {
    public static let layoutVersion: UInt8 = 2
    public static let bleOTACapability: UInt8 = 0x10
    public static let maximumFirmwareDataByteCount = 118
    public static let requiredNonceByteCount = 16
    public static let requiredSHA256ByteCount = 32

    public static func getInfoRequest(unitID: UInt8) throws -> Data {
        try commandRequest(unitID: unitID, command: .getInfo)
    }

    public static func prepareRequest(unitID: UInt8, nonce: Data) throws -> Data {
        guard nonce.count == requiredNonceByteCount else {
            throw OTAProtocolError.invalidNonceByteCount(
                actual: nonce.count,
                required: requiredNonceByteCount
            )
        }
        var writer = DataWriter(capacity: 3 + nonce.count)
        writer.append(OTACommand.prepare.rawValue)
        writer.append(0x01)
        writer.append(UInt8(nonce.count))
        writer.append(contentsOf: nonce)
        return try VendorEnvelopeCodec.request(unitID: unitID, payload: writer.data)
    }

    public static func cancelPrepareRequest(unitID: UInt8) throws -> Data {
        try commandRequest(unitID: unitID, command: .cancelPrepare)
    }

    public static func bleBeginRequest(
        unitID: UInt8,
        expectedBytes: UInt32,
        layoutVersion: UInt8 = layoutVersion,
        sha256: Data
    ) throws -> Data {
        guard expectedBytes > 0 else {
            throw OTAProtocolError.invalidFirmwareSize(expectedBytes)
        }
        guard sha256.count == requiredSHA256ByteCount else {
            throw OTAProtocolError.invalidSHA256ByteCount(
                actual: sha256.count,
                required: requiredSHA256ByteCount
            )
        }

        var writer = DataWriter(capacity: 38)
        writer.append(OTACommand.bleBegin.rawValue)
        writer.appendLittleEndian(expectedBytes)
        writer.append(layoutVersion)
        writer.append(contentsOf: sha256)
        return try VendorEnvelopeCodec.request(unitID: unitID, payload: writer.data)
    }

    public static func bleDataRequest(
        unitID: UInt8,
        offset: UInt32,
        firmwareData: Data
    ) throws -> Data {
        guard (1...maximumFirmwareDataByteCount).contains(firmwareData.count) else {
            throw OTAProtocolError.invalidFirmwareDataByteCount(
                actual: firmwareData.count,
                minimum: 1,
                maximum: maximumFirmwareDataByteCount
            )
        }
        var writer = DataWriter(capacity: 5 + firmwareData.count)
        writer.append(OTACommand.bleData.rawValue)
        writer.appendLittleEndian(offset)
        writer.append(contentsOf: firmwareData)
        return try VendorEnvelopeCodec.request(unitID: unitID, payload: writer.data)
    }

    public static func bleStatusRequest(unitID: UInt8) throws -> Data {
        try commandRequest(unitID: unitID, command: .bleStatus)
    }

    public static func bleCommitRequest(unitID: UInt8) throws -> Data {
        try commandRequest(unitID: unitID, command: .bleCommit)
    }

    public static func bleCancelRequest(unitID: UInt8) throws -> Data {
        try commandRequest(unitID: unitID, command: .bleCancel)
    }

    public static func parseResponse(
        _ frame: Data,
        command: OTACommand,
        expectedUnitID: UInt8? = nil
    ) throws -> VendorResponseEnvelope {
        try VendorEnvelopeCodec.decodeResponse(
            frame,
            expectedCommand: command.rawValue,
            expectedUnitID: expectedUnitID
        )
    }

    private static func commandRequest(unitID: UInt8, command: OTACommand) throws -> Data {
        try VendorEnvelopeCodec.request(unitID: unitID, payload: Data([command.rawValue]))
    }
}
