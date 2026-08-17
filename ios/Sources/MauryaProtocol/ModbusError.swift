public enum ModbusError: Error, Equatable, Sendable {
    case invalidQuantity(Int)
    case registerRangeOverflow(startRegister: UInt16, quantity: Int)
    case vendorPayloadTooLarge(actual: Int, maximum: Int)
    case frameTooShort(actual: Int, minimum: Int)
    case checksumMismatch
    case unsupportedFunction(UInt8)
    case lengthMismatch(expected: Int, actual: Int)
    case invalidByteCount(Int)
    case unexpectedUnitID(expected: UInt8, actual: UInt8)
    case bufferLimitExceeded(limit: Int)
    case invalidDecoderLimit
}
