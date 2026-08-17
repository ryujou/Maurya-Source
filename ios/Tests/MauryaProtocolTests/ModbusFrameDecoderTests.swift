import Foundation
import MauryaProtocol
import Testing

struct ModbusFrameDecoderTests {
    @Test(arguments: Array(0...TestFixtures.readResponse.count))
    func decodesEveryTwoFragmentSplit(_ splitOffset: Int) throws {
        var decoder = try ModbusFrameDecoder()
        let splitIndex = TestFixtures.readResponse.index(
            TestFixtures.readResponse.startIndex,
            offsetBy: splitOffset
        )

        let first = try decoder.append(Data(TestFixtures.readResponse[..<splitIndex]))
        let second = try decoder.append(Data(TestFixtures.readResponse[splitIndex...]))

        #expect(first.frames + second.frames == [TestFixtures.readResponse])
        #expect(decoder.bufferedByteCount == 0)
    }

    @Test func preservesAllCoalescedFramesAndRemainder() throws {
        var decoder = try ModbusFrameDecoder()
        let partialCount = 3
        let input =
            TestFixtures.readResponse
            + TestFixtures.writeSingleResponse
            + TestFixtures.vendorResponse.prefix(partialCount)

        let first = try decoder.append(input)
        #expect(first.frames == [TestFixtures.readResponse, TestFixtures.writeSingleResponse])
        #expect(decoder.bufferedByteCount == partialCount)

        let remainder = TestFixtures.vendorResponse.dropFirst(partialCount)
        let second = try decoder.append(Data(remainder))
        #expect(second.frames == [TestFixtures.vendorResponse])
        #expect(decoder.bufferedByteCount == 0)
    }

    @Test func discardsNoiseAndRecoversFollowingFrame() throws {
        var decoder = try ModbusFrameDecoder()
        let noise = Data([0x99, 0x03, 0xFA, 0x7E])

        let batch = try decoder.append(noise + TestFixtures.exceptionResponse)

        #expect(batch.frames == [TestFixtures.exceptionResponse])
        #expect(batch.discardedByteCount == noise.count)
    }

    @Test func corruptedFrameDoesNotConsumeFollowingValidFrame() throws {
        var corrupted = TestFixtures.writeSingleResponse
        corrupted[corrupted.index(before: corrupted.endIndex)] ^= 0x01
        var decoder = try ModbusFrameDecoder()

        let batch = try decoder.append(corrupted + TestFixtures.readResponse)

        #expect(batch.frames == [TestFixtures.readResponse])
        #expect(batch.discardedByteCount >= 1)
    }

    @Test func bufferLimitIsEnforcedAndDecoderCanRecover() throws {
        var decoder = try ModbusFrameDecoder(
            maximumBufferByteCount: 260,
            maximumFrameByteCount: 260
        )
        #expect(throws: ModbusError.bufferLimitExceeded(limit: 260)) {
            try decoder.append(Data(repeating: 0xAA, count: 261))
        }
        #expect(decoder.bufferedByteCount == 0)

        let batch = try decoder.append(TestFixtures.readResponse)
        #expect(batch.frames == [TestFixtures.readResponse])
    }

    @Test func rejectsInvalidLimits() {
        #expect(throws: ModbusError.invalidDecoderLimit) {
            try ModbusFrameDecoder(maximumBufferByteCount: 260, maximumFrameByteCount: 4)
        }
        #expect(throws: ModbusError.invalidDecoderLimit) {
            try ModbusFrameDecoder(maximumBufferByteCount: 259, maximumFrameByteCount: 260)
        }
    }

    @Test func discardsFrameThatExceedsConfiguredFrameLimit() throws {
        var decoder = try ModbusFrameDecoder(
            maximumBufferByteCount: 64,
            maximumFrameByteCount: 5
        )

        let batch = try decoder.append(TestFixtures.readResponse)

        #expect(batch.frames.isEmpty)
        #expect(batch.discardedByteCount > 0)
    }

    @Test func resetClearsBufferedRemainder() throws {
        var decoder = try ModbusFrameDecoder()
        _ = try decoder.append(Data(TestFixtures.vendorResponse.prefix(3)))
        #expect(decoder.bufferedByteCount == 3)

        decoder.reset()

        #expect(decoder.bufferedByteCount == 0)
        let batch = try decoder.append(TestFixtures.readResponse)
        #expect(batch.frames == [TestFixtures.readResponse])
    }

    @Test func deterministicNoiseFuzzNeverEscapesBufferBound() throws {
        var random = DeterministicBytes(seed: 0x4D41_5552_5941)
        var decoder = try ModbusFrameDecoder(
            maximumBufferByteCount: 260,
            maximumFrameByteCount: 260
        )

        for _ in 0..<4_096 {
            let byteCount = Int(random.next() % 33)
            let bytes = Data((0..<byteCount).map { _ in random.next() })
            do {
                let batch = try decoder.append(bytes)
                #expect(batch.frames.allSatisfy { $0.count <= 260 && ModbusCRC16.validates($0) })
            } catch ModbusError.bufferLimitExceeded {
                // The documented overflow policy clears the buffer before reporting the error.
            }
            #expect(decoder.bufferedByteCount <= 260)
        }
    }
}

private struct DeterministicBytes {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt8 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return UInt8(truncatingIfNeeded: state >> 32)
    }
}
