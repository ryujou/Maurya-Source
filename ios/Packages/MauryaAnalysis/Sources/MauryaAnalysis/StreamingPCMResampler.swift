import Foundation

/// Deterministic streaming linear resampler used off the audio realtime thread.
public struct StreamingPCMResampler: Sendable {
    public static let analysisSampleRate = 16_000.0

    private let inputSampleRate: Double
    private let outputSampleRate: Double
    private var samples: [Double] = []
    private var position = 0.0

    public init(inputSampleRate: Double, outputSampleRate: Double = analysisSampleRate) {
        self.inputSampleRate =
            inputSampleRate.isFinite && inputSampleRate > 0
            ? inputSampleRate
            : Self.analysisSampleRate
        self.outputSampleRate =
            outputSampleRate.isFinite && outputSampleRate > 0
            ? outputSampleRate
            : Self.analysisSampleRate
    }

    public mutating func append(_ input: [Double]) -> [Double] {
        samples.append(contentsOf: input.lazy.map { $0.isFinite ? $0 : 0 })
        let step = inputSampleRate / outputSampleRate
        var output: [Double] = []
        output.reserveCapacity(Int(Double(input.count) / step) + 1)

        while position + 1 < Double(samples.count) {
            let lowerIndex = Int(position)
            let fraction = position - Double(lowerIndex)
            let lower = samples[lowerIndex]
            let upper = samples[lowerIndex + 1]
            output.append(lower + ((upper - lower) * fraction))
            position += step
        }

        let consumed = min(Int(position), max(0, samples.count - 1))
        if consumed > 0 {
            samples.removeFirst(consumed)
            position -= Double(consumed)
        }
        return output
    }

    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        position = 0
    }
}
