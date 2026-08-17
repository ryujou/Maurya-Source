import Foundation
import MauryaEffects

public struct Vector3: Equatable, Codable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct Attitude: Equatable, Codable, Sendable {
    public let pitchRadians: Double
    public let rollRadians: Double
    public let yawRadians: Double

    public init(pitchRadians: Double, rollRadians: Double, yawRadians: Double) {
        self.pitchRadians = pitchRadians
        self.rollRadians = rollRadians
        self.yawRadians = yawRadians
    }
}

public struct MotionAnalyzer: Sendable {
    private var smoothedMotion = 0.0
    private var attitudeOffset = Vector3(x: 0, y: 0, z: 0)
    private var lastAttitude = Vector3(x: 0, y: 0, z: 0)

    public init() {}

    public mutating func analyzeAcceleration(
        _ accelerationInG: Vector3,
        timestampMilliseconds: Int64
    ) -> [RuntimeInputKey: AnalysisInputSample] {
        let x = accelerationInG.x.isFinite ? accelerationInG.x : 0
        let y = accelerationInG.y.isFinite ? accelerationInG.y : 0
        let z = accelerationInG.z.isFinite ? accelerationInG.z : 0
        let motion = min(max(abs(sqrt(x * x + y * y + z * z) - 1), 0), 4)
        let shake = min(max(abs(motion - smoothedMotion) * 2.5, 0), 1)
        smoothedMotion = smoothedMotion * 0.7 + motion * 0.3
        return numbers(
            [
                .sensorAccelX: x, .sensorAccelY: y, .sensorAccelZ: z,
                .sensorMotion: motion, .sensorShake: shake,
            ], timestamp: timestampMilliseconds)
    }

    public func analyzeGyroscope(
        _ radiansPerSecond: Vector3,
        timestampMilliseconds: Int64
    ) -> [RuntimeInputKey: AnalysisInputSample] {
        numbers(
            [
                .sensorGyroX: radiansPerSecond.x,
                .sensorGyroY: radiansPerSecond.y,
                .sensorGyroZ: radiansPerSecond.z,
            ], timestamp: timestampMilliseconds)
    }

    public mutating func analyzeAttitude(
        _ attitude: Attitude,
        timestampMilliseconds: Int64
    ) -> [RuntimeInputKey: AnalysisInputSample] {
        let degrees = Vector3(
            x: attitude.pitchRadians * 180 / .pi,
            y: attitude.rollRadians * 180 / .pi,
            z: attitude.yawRadians * 180 / .pi
        )
        lastAttitude = degrees
        let heading = (degrees.z.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return numbers(
            [
                .sensorPitch: degrees.x - attitudeOffset.x,
                .sensorRoll: degrees.y - attitudeOffset.y,
                .sensorYaw: degrees.z - attitudeOffset.z,
                .sensorHeading: heading,
            ], timestamp: timestampMilliseconds)
    }

    public mutating func zeroAttitude() {
        attitudeOffset = lastAttitude
    }

    private func numbers(
        _ values: [RuntimeInputKey: Double],
        timestamp: Int64
    ) -> [RuntimeInputKey: AnalysisInputSample] {
        values.mapValues { value in
            AnalysisInputSample(
                value: .number(value.isFinite ? value : 0),
                updatedAtMilliseconds: timestamp
            )
        }
    }
}
