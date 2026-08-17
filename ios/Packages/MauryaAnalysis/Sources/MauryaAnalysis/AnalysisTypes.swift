import Dispatch
import MauryaEffects

public enum InputPermission: String, Codable, Sendable {
    case notRequired
    case notDetermined
    case granted
    case denied
    case restricted
}

public enum InputUnavailability: String, Codable, Sendable {
    case unsupported
    case permissionDenied
    case interrupted
    case routeUnavailable
    case stopped
}

public enum InputAvailability: Equatable, Codable, Sendable {
    case available
    case unavailable(InputUnavailability)
}

public struct AnalysisInputSample: Equatable, Sendable {
    public let value: EffectValue
    public let updatedAtMilliseconds: Int64
    public let availability: InputAvailability
    public let permission: InputPermission

    public init(
        value: EffectValue,
        updatedAtMilliseconds: Int64,
        availability: InputAvailability = .available,
        permission: InputPermission = .notRequired
    ) {
        self.value = value
        self.updatedAtMilliseconds = updatedAtMilliseconds
        self.availability = availability
        self.permission = permission
    }
}

public struct AnalysisInputSnapshot: Equatable, Sendable {
    public let capturedAtMilliseconds: Int64
    public let requiredInputs: Set<RuntimeInputKey>
    public let samples: [RuntimeInputKey: AnalysisInputSample]
    public let virtualOverrides: Set<RuntimeInputKey>

    public init(
        capturedAtMilliseconds: Int64,
        requiredInputs: Set<RuntimeInputKey>,
        samples: [RuntimeInputKey: AnalysisInputSample],
        virtualOverrides: Set<RuntimeInputKey> = []
    ) {
        self.capturedAtMilliseconds = capturedAtMilliseconds
        self.requiredInputs = requiredInputs
        self.samples = samples
        self.virtualOverrides = virtualOverrides
    }

    public func isStale(
        _ key: RuntimeInputKey,
        nowMilliseconds: Int64? = nil,
        timeoutMilliseconds: Int64 = 1_000
    ) -> Bool {
        guard let sample = samples[key], sample.availability == .available else { return true }
        let now = nowMilliseconds ?? capturedAtMilliseconds
        return now &- sample.updatedAtMilliseconds > timeoutMilliseconds
    }

    public func effectRuntimeSnapshot() -> EffectRuntimeSnapshot {
        let available = Set(
            samples.compactMap { key, sample in
                sample.availability == .available ? key : nil
            })
        return EffectRuntimeSnapshot(
            capturedAtMilliseconds: capturedAtMilliseconds,
            values: samples.mapValues(\.value),
            available: available,
            updatedAtMilliseconds: samples.mapValues(\.updatedAtMilliseconds)
        )
    }
}

public enum AnalysisClock {
    public static func monotonicMilliseconds() -> Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }
}
