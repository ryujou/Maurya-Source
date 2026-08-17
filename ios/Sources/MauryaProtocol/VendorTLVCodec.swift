import Foundation

public enum VendorTLVCodec {
    public static func encode(_ values: [VendorTLV]) throws -> Data {
        var writer = DataWriter()
        for tlv in values {
            guard tlv.value.count <= Int(UInt8.max) else {
                throw ModbusError.vendorPayloadTooLarge(
                    actual: tlv.value.count,
                    maximum: Int(UInt8.max)
                )
            }
            writer.append(tlv.type)
            writer.append(UInt8(tlv.value.count))
            writer.append(contentsOf: tlv.value)
        }
        return writer.data
    }

    public static func decode(_ data: Data) throws -> [VendorTLV] {
        var reader = try DataReader(data: data)
        var values: [VendorTLV] = []

        while reader.remainingByteCount > 0 {
            let headerOffset = reader.offset
            guard reader.remainingByteCount >= 2 else {
                throw VendorProtocolError.truncatedTLVHeader(offset: headerOffset)
            }
            let type = try reader.readUInt8()
            let length = Int(try reader.readUInt8())
            guard reader.remainingByteCount >= length else {
                throw VendorProtocolError.truncatedTLVValue(
                    type: type,
                    expected: length,
                    available: reader.remainingByteCount
                )
            }
            values.append(VendorTLV(type: type, value: try reader.readBytes(count: length)))
        }
        return values
    }

    /// Matches the existing Android consumer rule for duplicate TLV types.
    public static func lastValue(for type: UInt8, in values: [VendorTLV]) throws -> Data {
        guard let value = values.last(where: { $0.type == type })?.value else {
            throw VendorProtocolError.missingTLV(type: type)
        }
        return value
    }

    public static func littleEndianUInt16(type: UInt8, in values: [VendorTLV]) throws -> UInt16 {
        let value = try lastValue(for: type, in: values)
        guard value.count == 2 else {
            throw VendorProtocolError.invalidTLVLength(type: type, expected: 2, actual: value.count)
        }
        var reader = try DataReader(data: value)
        return try reader.readUInt16LittleEndian()
    }

    public static func littleEndianUInt32(type: UInt8, in values: [VendorTLV]) throws -> UInt32 {
        let value = try lastValue(for: type, in: values)
        guard value.count == 4 else {
            throw VendorProtocolError.invalidTLVLength(type: type, expected: 4, actual: value.count)
        }
        var reader = try DataReader(data: value)
        return try reader.readUInt32LittleEndian()
    }
}
