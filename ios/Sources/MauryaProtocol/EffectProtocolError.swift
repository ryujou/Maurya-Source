public enum EffectProtocolError: Error, Equatable, Sendable {
    case invalidGroupCount(expected: Int, actual: Int)
    case invalidPixelCount(expected: Int, actual: Int)
    case geometryNotWireEncodable(pixelCount: Int)
}
