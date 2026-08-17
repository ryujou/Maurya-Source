public enum EffectGeometryError: Error, Equatable, Sendable {
    case invalidDimensions(
        groupCount: UInt16,
        pixelsPerGroup: UInt16,
        maximumPixelCount: Int
    )
    case groupIndexOutOfBounds(index: Int)
    case pixelIndexInGroupOutOfBounds(index: Int)
    case linearPixelIndexOutOfBounds(index: Int)
}
