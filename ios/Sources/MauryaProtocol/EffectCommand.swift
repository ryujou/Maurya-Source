public enum EffectCommand: UInt8, CaseIterable, Sendable {
    case begin = 0x20
    case groupFrame = 0x21
    case heartbeat = 0x22
    case end = 0x23
    case pixelFrame = 0x24
}
