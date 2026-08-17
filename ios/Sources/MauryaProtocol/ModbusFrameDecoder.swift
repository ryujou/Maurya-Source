import Foundation

/// Bounded incremental decoder for fragmented, coalesced, and noisy notifications.
public struct ModbusFrameDecoder: Sendable {
    public let maximumBufferByteCount: Int
    public let maximumFrameByteCount: Int
    public private(set) var bufferedByteCount = 0

    private var buffer = Data()

    public init(
        maximumBufferByteCount: Int = 1_024,
        maximumFrameByteCount: Int = 260
    ) throws {
        guard maximumFrameByteCount >= 5,
            maximumBufferByteCount >= maximumFrameByteCount
        else {
            throw ModbusError.invalidDecoderLimit
        }
        self.maximumBufferByteCount = maximumBufferByteCount
        self.maximumFrameByteCount = maximumFrameByteCount
    }

    public mutating func append(_ bytes: Data) throws -> ModbusDecodeBatch {
        guard buffer.count + bytes.count <= maximumBufferByteCount else {
            buffer.removeAll(keepingCapacity: true)
            bufferedByteCount = 0
            throw ModbusError.bufferLimitExceeded(limit: maximumBufferByteCount)
        }

        buffer.append(bytes)
        var frames: [Data] = []
        var discardedByteCount = 0

        while buffer.count >= 2 {
            let expectedLength: Int
            do {
                guard let length = try ModbusResponseCodec.expectedFrameLength(for: buffer) else {
                    break
                }
                expectedLength = length
            } catch ModbusError.unsupportedFunction {
                discardFirstByte()
                discardedByteCount += 1
                continue
            }

            guard expectedLength <= maximumFrameByteCount else {
                discardFirstByte()
                discardedByteCount += 1
                continue
            }

            guard buffer.count >= expectedLength else {
                if let offset = nextCompleteFrameOffset() {
                    buffer.removeFirst(offset)
                    discardedByteCount += offset
                    continue
                }
                break
            }

            let candidate = Data(buffer.prefix(expectedLength))
            guard ModbusCRC16.validates(candidate) else {
                discardFirstByte()
                discardedByteCount += 1
                continue
            }

            frames.append(candidate)
            buffer.removeFirst(expectedLength)
        }

        bufferedByteCount = buffer.count
        return ModbusDecodeBatch(frames: frames, discardedByteCount: discardedByteCount)
    }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
        bufferedByteCount = 0
    }

    private mutating func discardFirstByte() {
        buffer.removeFirst()
    }

    /// Finds a valid complete frame after a plausible but incomplete noisy prefix.
    private func nextCompleteFrameOffset() -> Int? {
        guard buffer.count > 2 else { return nil }

        for offset in 1..<(buffer.count - 1) {
            let suffix = Data(buffer.dropFirst(offset))
            guard let expectedLength = try? ModbusResponseCodec.expectedFrameLength(for: suffix),
                expectedLength <= maximumFrameByteCount,
                suffix.count >= expectedLength
            else {
                continue
            }
            if ModbusCRC16.validates(Data(suffix.prefix(expectedLength))) {
                return offset
            }
        }
        return nil
    }
}
