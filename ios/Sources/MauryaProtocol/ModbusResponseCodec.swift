import Foundation

public enum ModbusResponseCodec {
    public static func expectedFrameLength(for prefix: Data) throws -> Int? {
        guard prefix.count >= 2 else { return nil }
        var reader = try DataReader(data: prefix)
        _ = try reader.readUInt8()
        let function = try reader.readUInt8()

        if function & 0x80 != 0 {
            return 5
        }

        switch function {
        case ModbusFunction.readHoldingRegisters.rawValue,
            ModbusFunction.vendor.rawValue:
            guard prefix.count >= 3 else { return nil }
            let byteCount = Int(try reader.readUInt8())
            return 5 + byteCount
        case ModbusFunction.writeSingleRegister.rawValue,
            ModbusFunction.writeMultipleRegisters.rawValue:
            return 8
        default:
            throw ModbusError.unsupportedFunction(function)
        }
    }

    public static func decode(
        _ frame: Data,
        expectedUnitID: UInt8? = nil
    ) throws -> ModbusResponse {
        guard frame.count >= 5 else {
            throw ModbusError.frameTooShort(actual: frame.count, minimum: 5)
        }
        guard ModbusCRC16.validates(frame) else {
            throw ModbusError.checksumMismatch
        }

        guard let expectedLength = try expectedFrameLength(for: frame) else {
            throw ModbusError.frameTooShort(actual: frame.count, minimum: 3)
        }
        guard frame.count == expectedLength else {
            throw ModbusError.lengthMismatch(expected: expectedLength, actual: frame.count)
        }

        var reader = try DataReader(data: frame)
        let unitID = try reader.readUInt8()
        if let expectedUnitID, unitID != expectedUnitID {
            throw ModbusError.unexpectedUnitID(expected: expectedUnitID, actual: unitID)
        }

        let function = try reader.readUInt8()
        if function & 0x80 != 0 {
            return .exception(
                unitID: unitID,
                function: function,
                code: try reader.readUInt8()
            )
        }

        switch function {
        case ModbusFunction.readHoldingRegisters.rawValue:
            let byteCount = Int(try reader.readUInt8())
            guard byteCount > 0, byteCount.isMultiple(of: 2) else {
                throw ModbusError.invalidByteCount(byteCount)
            }
            var values: [UInt16] = []
            values.reserveCapacity(byteCount / 2)
            for _ in 0..<(byteCount / 2) {
                values.append(try reader.readUInt16BigEndian())
            }
            return .readHoldingRegisters(unitID: unitID, values: values)
        case ModbusFunction.writeSingleRegister.rawValue:
            return .writeSingleAcknowledgement(
                unitID: unitID,
                register: try reader.readUInt16BigEndian(),
                value: try reader.readUInt16BigEndian()
            )
        case ModbusFunction.writeMultipleRegisters.rawValue:
            return .writeMultipleAcknowledgement(
                unitID: unitID,
                startRegister: try reader.readUInt16BigEndian(),
                quantity: try reader.readUInt16BigEndian()
            )
        case ModbusFunction.vendor.rawValue:
            let byteCount = Int(try reader.readUInt8())
            return .vendor(unitID: unitID, payload: try reader.readBytes(count: byteCount))
        default:
            throw ModbusError.unsupportedFunction(function)
        }
    }
}
