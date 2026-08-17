import MauryaAnalysis
import MauryaEffects
import Testing

struct MotionAnalyzerTests {
    @Test func environmentMappingsUseAndroidUnitsAndValues() {
        #expect(CoreMotionEnvironmentMapper.androidPressure(kilopascals: 101.325) == 1_013.25)
        #expect(CoreMotionEnvironmentMapper.androidPressure(kilopascals: .infinity) == 0)
        #expect(CoreMotionEnvironmentMapper.androidNear(false) == 0)
        #expect(CoreMotionEnvironmentMapper.androidNear(true) == 1)
    }

    @Test
    func stationaryAndShakeReplayMatchesAndroid() {
        var analyzer = MotionAnalyzer()
        let stationary = analyzer.analyzeAcceleration(
            Vector3(x: 0, y: 0, z: 1),
            timestampMilliseconds: 100
        )
        let impulse = analyzer.analyzeAcceleration(
            Vector3(x: 2, y: 0, z: 0),
            timestampMilliseconds: 120
        )

        #expect(number(.sensorMotion, in: stationary) == 0)
        #expect(number(.sensorShake, in: stationary) == 0)
        #expect(number(.sensorMotion, in: impulse) == 1)
        #expect(number(.sensorShake, in: impulse) == 1)
    }

    @Test
    func attitudeUsesDegreesHeadingWrapAndZeroOffset() {
        var analyzer = MotionAnalyzer()
        let first = analyzer.analyzeAttitude(
            Attitude(pitchRadians: .pi / 6, rollRadians: -.pi / 4, yawRadians: -.pi / 2),
            timestampMilliseconds: 100
        )
        analyzer.zeroAttitude()
        let zeroed = analyzer.analyzeAttitude(
            Attitude(pitchRadians: .pi / 6, rollRadians: -.pi / 4, yawRadians: -.pi / 2),
            timestampMilliseconds: 200
        )

        #expect(abs(number(.sensorPitch, in: first) - 30) < 1e-12)
        #expect(abs(number(.sensorRoll, in: first) + 45) < 1e-12)
        #expect(abs(number(.sensorYaw, in: first) + 90) < 1e-12)
        #expect(number(.sensorHeading, in: first) == 270)
        #expect(abs(number(.sensorPitch, in: zeroed)) < 1e-12)
        #expect(abs(number(.sensorRoll, in: zeroed)) < 1e-12)
        #expect(abs(number(.sensorYaw, in: zeroed)) < 1e-12)
        #expect(number(.sensorHeading, in: zeroed) == 270)
    }

    @Test
    func gyroValuesAndNonFiniteSanitizationAreStable() {
        let analyzer = MotionAnalyzer()
        let values = analyzer.analyzeGyroscope(
            Vector3(x: 1, y: .infinity, z: -2),
            timestampMilliseconds: 300
        )
        #expect(number(.sensorGyroX, in: values) == 1)
        #expect(number(.sensorGyroY, in: values) == 0)
        #expect(number(.sensorGyroZ, in: values) == -2)
    }

    private func number(
        _ key: RuntimeInputKey,
        in samples: [RuntimeInputKey: AnalysisInputSample]
    ) -> Double {
        guard case let .number(value) = samples[key]?.value else { return .nan }
        return value
    }
}
