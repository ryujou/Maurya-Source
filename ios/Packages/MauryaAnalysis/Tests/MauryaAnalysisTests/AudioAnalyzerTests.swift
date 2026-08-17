import Foundation
import MauryaAnalysis
import Testing

struct AudioAnalyzerTests {
    struct ToneFixture: Sendable {
        let frequency: Double
        let expectedLevel: Double
        let expectedPeak: Double
        let expectedBass: Double
        let expectedMid: Double
        let expectedTreble: Double
    }

    @Test(arguments: [
        ToneFixture(
            frequency: 125,
            expectedLevel: 0.35353979389843904,
            expectedPeak: 0.5,
            expectedBass: 0.9145604795768648,
            expectedMid: 0.000025266572401022314,
            expectedTreble: 0.0000042718847469183405
        ),
        ToneFixture(
            frequency: 1_000,
            expectedLevel: 0.35353952730103727,
            expectedPeak: 0.5,
            expectedBass: 0.000004193228699520463,
            expectedMid: 0.11438374897616466,
            expectedTreble: 0.000002883631674426755
        ),
        ToneFixture(
            frequency: 4_000,
            expectedLevel: 0.3535533905932738,
            expectedPeak: 0.5,
            expectedBass: 0.00000047605516843930785,
            expectedMid: 0.0000007949507078479899,
            expectedTreble: 0.03639839067436526
        ),
    ])
    func androidToneGolden(fixture: ToneFixture) {
        let pcm = (0..<AudioAnalyzer.frameSize).map { index in
            Int16(16_384 * sin(2 * .pi * fixture.frequency * Double(index) / 16_000))
        }
        var analyzer = AudioAnalyzer()
        let result = analyzer.analyzePCM16(pcm, timestampMilliseconds: 1_000)

        #expect(abs(result.level - fixture.expectedLevel) < 1e-12)
        #expect(abs(result.peak - fixture.expectedPeak) < 1e-12)
        #expect(abs(result.bass - fixture.expectedBass) < 1e-12)
        #expect(abs(result.mid - fixture.expectedMid) < 1e-12)
        #expect(abs(result.treble - fixture.expectedTreble) < 1e-12)
    }

    @Test
    func silenceMatchesAndroidDefaults() {
        var analyzer = AudioAnalyzer()
        let result = analyzer.analyzePCM16(
            Array(repeating: 0, count: AudioAnalyzer.frameSize),
            timestampMilliseconds: 1_000
        )

        #expect(result.level == 0)
        #expect(result.peak == 0)
        #expect(result.bass == 0)
        #expect(result.mid == 0)
        #expect(result.treble == 0)
        #expect(result.beat == false)
        #expect(result.bpm == 120)
    }

    @Test
    func beatRefractoryPeriodAndBPMMatchAndroid() {
        var analyzer = AudioAnalyzer()
        let first = Array(repeating: Int16(6_554), count: AudioAnalyzer.frameSize)
        let second = Array(repeating: Int16(16_384), count: AudioAnalyzer.frameSize)

        let initial = analyzer.analyzePCM16(first, timestampMilliseconds: 1_000)
        let suppressed = analyzer.analyzePCM16(first, timestampMilliseconds: 1_200)
        _ = analyzer.analyzePCM16(
            Array(repeating: 0, count: AudioAnalyzer.frameSize),
            timestampMilliseconds: 1_300
        )
        let next = analyzer.analyzePCM16(second, timestampMilliseconds: 1_500)

        #expect(initial.beat)
        #expect(suppressed.beat == false)
        #expect(next.beat)
        #expect(next.bpm == 120)
    }

    @Test
    func sensitivityIsClampedLikeAndroid() {
        var analyzer = AudioAnalyzer(sensitivity: 99)
        let result = analyzer.analyzePCM16(
            Array(repeating: 16_384, count: AudioAnalyzer.frameSize),
            timestampMilliseconds: 1_000
        )
        #expect(result.level == 1)
        #expect(result.peak == 1)
    }
}

struct StreamingPCMResamplerTests {
    @Test
    func converts48KHzTo16KHzWithoutAssumingHardwareRate() {
        var resampler = StreamingPCMResampler(inputSampleRate: 48_000)
        let source = (0...1_536).map(Double.init)
        let output = resampler.append(source)

        #expect(output.count == 512)
        #expect(output == (0..<512).map { Double($0 * 3) })
    }

    @Test
    func chunkBoundariesDoNotChangeResamplingOutput() {
        let source = (0..<4_411).map { sin(Double($0) / 31) }
        var contiguous = StreamingPCMResampler(inputSampleRate: 44_100)
        let expected = contiguous.append(source)

        var chunked = StreamingPCMResampler(inputSampleRate: 44_100)
        var actual: [Double] = []
        actual += chunked.append(Array(source[0..<17]))
        actual += chunked.append(Array(source[17..<997]))
        actual += chunked.append(Array(source[997...]))

        #expect(actual.count == expected.count)
        let maximumError = zip(actual, expected).map { abs($0 - $1) }.max() ?? 0
        #expect(maximumError < 1e-9)
    }

    @Test
    func nonFiniteInputIsSanitizedBeforeAnalysis() {
        var resampler = StreamingPCMResampler(inputSampleRate: 16_000)
        let output = resampler.append([.nan, .infinity, -.infinity, 1])

        #expect(output == [0, 0, 0])
    }
}
