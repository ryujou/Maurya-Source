public enum VendorProtocolError: Error, Equatable, Sendable {
    case unexpectedModbusResponse
    case responsePayloadTooShort(actual: Int, minimum: Int)
    case unexpectedCommand(expected: UInt8, actual: UInt8)
    case commandRejected(command: UInt8, status: UInt8)
    case truncatedTLVHeader(offset: Int)
    case truncatedTLVValue(type: UInt8, expected: Int, available: Int)
    case missingTLV(type: UInt8)
    case invalidTLVLength(type: UInt8, expected: Int, actual: Int)
}
