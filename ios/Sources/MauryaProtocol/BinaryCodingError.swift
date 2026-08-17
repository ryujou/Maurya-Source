public enum BinaryCodingError: Error, Equatable, Sendable {
    case outOfBounds(offset: Int, requestedByteCount: Int, availableByteCount: Int)
}
