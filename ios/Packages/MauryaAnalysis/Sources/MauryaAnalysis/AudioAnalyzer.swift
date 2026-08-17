import Accelerate
import Foundation
import MauryaEffects

public struct AudioAnalysisFrame: Equatable, Sendable {
    public let timestampMilliseconds: Int64
    public let level: Double
    public let peak: Double
    public let bass: Double
    public let mid: Double
    public let treble: Double
    public let beat: Bool
    public let bpm: Double

    public var samples: [RuntimeInputKey: AnalysisInputSample] {
        let timestamp = timestampMilliseconds
        return [
            .audioLevel: .init(value: .number(level), updatedAtMilliseconds: timestamp, permission: .granted),
            .audioPeak: .init(value: .number(peak), updatedAtMilliseconds: timestamp, permission: .granted),
            .audioBass: .init(value: .number(bass), updatedAtMilliseconds: timestamp, permission: .granted),
            .audioMid: .init(value: .number(mid), updatedAtMilliseconds: timestamp, permission: .granted),
            .audioTreble: .init(value: .number(treble), updatedAtMilliseconds: timestamp, permission: .granted),
            .audioBeat: .init(value: .boolean(beat), updatedAtMilliseconds: timestamp, permission: .granted),
            .audioBPM: .init(value: .number(bpm), updatedAtMilliseconds: timestamp, permission: .granted),
        ]
    }
}

public struct AudioAnalyzer: Sendable {
    public static let sampleRate = 16_000
    public static let frameSize = 512

    private var lastAudioPeak = 0.0
    private var lastBeatAt: Int64 = 0
    private var beatIntervals: [Int64] = []
    public var sensitivity: Double

    public init(sensitivity: Double = 1) {
        self.sensitivity = min(max(sensitivity, 0.25), 4)
    }

    public mutating func setSensitivity(_ value: Double) {
        sensitivity = min(max(value, 0.25), 4)
    }

    public mutating func reset() {
        lastAudioPeak = 0
        lastBeatAt = 0
        beatIntervals.removeAll(keepingCapacity: true)
    }

    public mutating func analyzePCM16(
        _ pcm: [Int16],
        timestampMilliseconds: Int64
    ) -> AudioAnalysisFrame {
        precondition(pcm.count == Self.frameSize, "Maurya audio frames must contain exactly 512 samples")
        return analyze(
            pcm.map { Double($0) / 32_768 },
            timestampMilliseconds: timestampMilliseconds
        )
    }

    public mutating func analyze(
        _ samples: [Double],
        timestampMilliseconds: Int64
    ) -> AudioAnalysisFrame {
        precondition(samples.count == Self.frameSize, "Maurya audio frames must contain exactly 512 samples")
        var real = Array(repeating: 0.0, count: Self.frameSize)
        var imaginary = Array(repeating: 0.0, count: Self.frameSize)
        var sum = 0.0
        var peak = 0.0

        for index in samples.indices {
            let sample = samples[index].isFinite ? samples[index] : 0
            let window = 0.5 - 0.5 * cos(2 * Double.pi * Double(index) / Double(Self.frameSize - 1))
            real[index] = sample * window
            sum += sample * sample
            peak = max(peak, abs(sample))
        }
        Self.fft(real: &real, imaginary: &imaginary)

        let gain = sensitivity
        let level = min(max(sqrt(sum / Double(samples.count)) * gain, 0), 1)
        peak = min(max(peak * gain, 0), 1)
        let adaptive = max(0.08, lastAudioPeak * 0.92)
        let beat = peak > adaptive * 1.45 && timestampMilliseconds - lastBeatAt > 240
        if beat {
            if lastBeatAt > 0 {
                beatIntervals.append(timestampMilliseconds - lastBeatAt)
                if beatIntervals.count > 8 { beatIntervals.removeFirst(beatIntervals.count - 8) }
            }
            lastBeatAt = timestampMilliseconds
        }
        lastAudioPeak = max(peak, adaptive)
        let average =
            beatIntervals.isEmpty
            ? 500
            : Double(beatIntervals.reduce(0, +)) / Double(beatIntervals.count)

        return AudioAnalysisFrame(
            timestampMilliseconds: timestampMilliseconds,
            level: level,
            peak: peak,
            bass: min(Self.band(40, 250, real: real, imaginary: imaginary) * gain, 1),
            mid: min(Self.band(250, 2_000, real: real, imaginary: imaginary) * gain, 1),
            treble: min(Self.band(2_000, 7_500, real: real, imaginary: imaginary) * gain, 1),
            beat: beat,
            bpm: min(max(60_000 / average, 40), 240)
        )
    }

    private static func band(
        _ low: Double,
        _ high: Double,
        real: [Double],
        imaginary: [Double]
    ) -> Double {
        let start = max(Int(low * Double(frameSize) / Double(sampleRate)), 1)
        let end = min(Int(high * Double(frameSize) / Double(sampleRate)), frameSize / 2)
        guard start < end else { return 0 }
        var energy = 0.0
        for bin in start..<end { energy += hypot(real[bin], imaginary[bin]) }
        return min(max(energy / Double(end - start) / 20, 0), 1)
    }

    private static func fft(real: inout [Double], imaginary: inout [Double]) {
        let log2Count = vDSP_Length(real.count.trailingZeroBitCount)
        guard let setup = vDSP_create_fftsetupD(log2Count, FFTRadix(kFFTRadix2)) else { return }
        defer { vDSP_destroy_fftsetupD(setup) }
        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPDoubleSplitComplex(
                    realp: realBuffer.baseAddress!,
                    imagp: imaginaryBuffer.baseAddress!
                )
                vDSP_fft_zipD(setup, &split, 1, log2Count, FFTDirection(FFT_FORWARD))
            }
        }
    }
}
