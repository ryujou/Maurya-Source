import Testing

@testable import MauryaAnalysis

@Suite("PCM ring buffer")
struct PCMRingBufferTests {
    @Test("Bounded storage keeps the newest complete frame")
    func overwriteKeepsNewestFrame() {
        let frameSize = AudioAnalyzer.frameSize
        let ring = PCMRingBuffer(capacity: frameSize)
        let first = (0..<frameSize).map { Float($0) }
        let second = (0..<frameSize).map { Float($0 + frameSize) }

        #expect(first.withUnsafeBufferPointer { ring.append($0.baseAddress!, count: $0.count) })
        #expect(second.withUnsafeBufferPointer { ring.append($0.baseAddress!, count: $0.count) })
        #expect(ring.popFrame() == second.map(Double.init))
        #expect(ring.popFrame() == nil)
    }

    @Test("Clear removes buffered PCM")
    func clearRemovesFrame() {
        let values = Array(repeating: Float(0.25), count: AudioAnalyzer.frameSize)
        let ring = PCMRingBuffer(capacity: values.count)

        #expect(values.withUnsafeBufferPointer { ring.append($0.baseAddress!, count: $0.count) })
        ring.clear()
        #expect(ring.popFrame() == nil)
    }
}
