public enum OTAProtocolError: Error, Equatable, Sendable {
    case invalidNonceByteCount(actual: Int, required: Int)
    case invalidFirmwareSize(UInt32)
    case invalidSHA256ByteCount(actual: Int, required: Int)
    case invalidFirmwareDataByteCount(actual: Int, minimum: Int, maximum: Int)
}
