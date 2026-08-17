import Foundation

public enum ModbusRequest {
    /// Maurya firmware deliberately caps bulk register operations below the
    /// generic Modbus maxima. Keep this codec aligned with the shared schema and
    /// ESP32 server instead of emitting requests the device must reject.
    public static let maximumReadRegisterCount = 64
    public static let maximumWriteRegisterCount = 64
    public static let maximumVendorPayloadByteCount = 239

    public static func readHoldingRegisters(
        unitID: UInt8,
        startRegister: UInt16,
        quantity: Int
    ) throws -> Data {
        guard (1...maximumReadRegisterCount).contains(quantity) else {
            throw ModbusError.invalidQuantity(quantity)
        }
        try validateRegisterRange(startRegister: startRegister, quantity: quantity)

        var writer = DataWriter(capacity: 6)
        writer.append(unitID)
        writer.append(ModbusFunction.readHoldingRegisters.rawValue)
        writer.appendBigEndian(startRegister)
        writer.appendBigEndian(UInt16(quantity))
        return ModbusCRC16.appendingChecksum(to: writer.data)
    }

    public static func writeSingleRegister(
        unitID: UInt8,
        register: UInt16,
        value: UInt16
    ) -> Data {
        var writer = DataWriter(capacity: 6)
        writer.append(unitID)
        writer.append(ModbusFunction.writeSingleRegister.rawValue)
        writer.appendBigEndian(register)
        writer.appendBigEndian(value)
        return ModbusCRC16.appendingChecksum(to: writer.data)
    }

    public static func writeMultipleRegisters(
        unitID: UInt8,
        startRegister: UInt16,
        values: [UInt16]
    ) throws -> Data {
        guard (1...maximumWriteRegisterCount).contains(values.count) else {
            throw ModbusError.invalidQuantity(values.count)
        }
        try validateRegisterRange(startRegister: startRegister, quantity: values.count)

        let byteCount = values.count * 2
        var writer = DataWriter(capacity: 7 + byteCount)
        writer.append(unitID)
        writer.append(ModbusFunction.writeMultipleRegisters.rawValue)
        writer.appendBigEndian(startRegister)
        writer.appendBigEndian(UInt16(values.count))
        writer.append(UInt8(byteCount))
        for value in values {
            writer.appendBigEndian(value)
        }
        return ModbusCRC16.appendingChecksum(to: writer.data)
    }

    public static func vendor(unitID: UInt8, payload: Data) throws -> Data {
        guard payload.count <= maximumVendorPayloadByteCount else {
            throw ModbusError.vendorPayloadTooLarge(
                actual: payload.count,
                maximum: maximumVendorPayloadByteCount
            )
        }

        var writer = DataWriter(capacity: 3 + payload.count)
        writer.append(unitID)
        writer.append(ModbusFunction.vendor.rawValue)
        writer.append(UInt8(payload.count))
        writer.append(contentsOf: payload)
        return ModbusCRC16.appendingChecksum(to: writer.data)
    }

    private static func validateRegisterRange(
        startRegister: UInt16,
        quantity: Int
    ) throws {
        let finalRegister = Int(startRegister) + quantity - 1
        guard finalRegister <= Int(UInt16.max) else {
            throw ModbusError.registerRangeOverflow(
                startRegister: startRegister,
                quantity: quantity
            )
        }
    }
}
