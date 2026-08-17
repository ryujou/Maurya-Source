public enum OTACommand: UInt8, CaseIterable, Sendable {
    case getInfo = 0x01
    case prepare = 0x02
    case cancelPrepare = 0x03
    case bleBegin = 0x10
    case bleData = 0x11
    case bleStatus = 0x12
    case bleCommit = 0x14
    case bleCancel = 0x15
}
