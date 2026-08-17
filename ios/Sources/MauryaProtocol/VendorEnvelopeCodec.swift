import Foundation

public enum VendorEnvelopeCodec {
    public static func request(unitID: UInt8, payload: Data) throws -> Data {
        try ModbusRequest.vendor(unitID: unitID, payload: payload)
    }

    public static func decodeResponse(
        _ frame: Data,
        expectedCommand: UInt8? = nil,
        expectedUnitID: UInt8? = nil
    ) throws -> VendorResponseEnvelope {
        let response = try ModbusResponseCodec.decode(frame, expectedUnitID: expectedUnitID)
        guard case .vendor(let unitID, let payload) = response else {
            throw VendorProtocolError.unexpectedModbusResponse
        }
        guard payload.count >= 2 else {
            throw VendorProtocolError.responsePayloadTooShort(actual: payload.count, minimum: 2)
        }

        var reader = try DataReader(data: payload)
        let command = try reader.readUInt8()
        let status = try reader.readUInt8()
        if let expectedCommand, command != expectedCommand {
            throw VendorProtocolError.unexpectedCommand(expected: expectedCommand, actual: command)
        }
        guard status == 0 else {
            throw VendorProtocolError.commandRejected(command: command, status: status)
        }
        return VendorResponseEnvelope(
            unitID: unitID,
            command: command,
            status: status,
            data: try reader.readBytes(count: reader.remainingByteCount)
        )
    }
}
