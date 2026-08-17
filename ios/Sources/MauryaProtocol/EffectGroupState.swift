public struct EffectGroupState: Equatable, Sendable {
    public let innerMode: UInt8
    public let hue: UInt16
    public let saturation: UInt8
    public let value: UInt8
    public let innerParameter: UInt8

    public init(
        innerMode: UInt8,
        hue: UInt16,
        saturation: UInt8,
        value: UInt8,
        innerParameter: UInt8
    ) {
        self.innerMode = innerMode
        self.hue = hue
        self.saturation = saturation
        self.value = value
        self.innerParameter = innerParameter
    }
}
