public struct EffectGeometry: Codable, Equatable, Hashable, Sendable {
    public static let maximumSupportedPixelCount = 4_096

    /// Canonical geometry for current devices and older firmware with no geometry TLV.
    public static let legacyFirmwareFallback = EffectGeometry(
        validatedGroupCount: 7,
        pixelsPerGroup: 6
    )

    public let groupCount: UInt16
    public let pixelsPerGroup: UInt16

    public init(
        groupCount: UInt16,
        pixelsPerGroup: UInt16,
        maximumPixelCount: Int = maximumSupportedPixelCount
    ) throws {
        let pixelCount = Int(groupCount) * Int(pixelsPerGroup)
        guard groupCount > 0,
            pixelsPerGroup > 0,
            maximumPixelCount > 0,
            pixelCount <= maximumPixelCount
        else {
            throw EffectGeometryError.invalidDimensions(
                groupCount: groupCount,
                pixelsPerGroup: pixelsPerGroup,
                maximumPixelCount: maximumPixelCount
            )
        }
        self.groupCount = groupCount
        self.pixelsPerGroup = pixelsPerGroup
    }

    public var pixelCount: Int {
        Int(groupCount) * Int(pixelsPerGroup)
    }

    public var pixelFrameByteCount: Int {
        14 + pixelCount * 3
    }

    public func pixelRange(forGroupAt index: Int) throws -> Range<Int> {
        guard (0..<Int(groupCount)).contains(index) else {
            throw EffectGeometryError.groupIndexOutOfBounds(index: index)
        }
        let lowerBound = index * Int(pixelsPerGroup)
        return lowerBound..<(lowerBound + Int(pixelsPerGroup))
    }

    public func linearPixelIndex(groupIndex: Int, pixelIndexInGroup: Int) throws -> Int {
        guard (0..<Int(groupCount)).contains(groupIndex) else {
            throw EffectGeometryError.groupIndexOutOfBounds(index: groupIndex)
        }
        guard (0..<Int(pixelsPerGroup)).contains(pixelIndexInGroup) else {
            throw EffectGeometryError.pixelIndexInGroupOutOfBounds(index: pixelIndexInGroup)
        }
        return groupIndex * Int(pixelsPerGroup) + pixelIndexInGroup
    }

    public func coordinates(forLinearPixelIndex index: Int) throws -> (
        groupIndex: Int,
        pixelIndexInGroup: Int
    ) {
        guard (0..<pixelCount).contains(index) else {
            throw EffectGeometryError.linearPixelIndexOutOfBounds(index: index)
        }
        return (index / Int(pixelsPerGroup), index % Int(pixelsPerGroup))
    }

    private init(validatedGroupCount: UInt16, pixelsPerGroup: UInt16) {
        groupCount = validatedGroupCount
        self.pixelsPerGroup = pixelsPerGroup
    }

    private enum CodingKeys: String, CodingKey {
        case groupCount
        case pixelsPerGroup
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let groupCount = try container.decode(UInt16.self, forKey: .groupCount)
        let pixelsPerGroup = try container.decode(UInt16.self, forKey: .pixelsPerGroup)
        try self.init(groupCount: groupCount, pixelsPerGroup: pixelsPerGroup)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupCount, forKey: .groupCount)
        try container.encode(pixelsPerGroup, forKey: .pixelsPerGroup)
    }
}
