import Foundation

public struct ModbusDecodeBatch: Equatable, Sendable {
    public let frames: [Data]
    public let discardedByteCount: Int

    public init(frames: [Data], discardedByteCount: Int) {
        self.frames = frames
        self.discardedByteCount = discardedByteCount
    }
}
