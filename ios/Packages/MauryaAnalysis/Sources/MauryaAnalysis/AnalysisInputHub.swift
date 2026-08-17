import Foundation
import MauryaEffects

public actor AnalysisInputHub {
    private var requiredInputs: Set<RuntimeInputKey>
    private var physical: [RuntimeInputKey: AnalysisInputSample] = [:]
    private var virtual: [RuntimeInputKey: AnalysisInputSample] = [:]
    private var activeLatchedInputs: Set<RuntimeInputKey> = []
    private var continuations: [UUID: AsyncStream<AnalysisInputSnapshot>.Continuation] = [:]

    public init(requiredInputs: Set<RuntimeInputKey> = []) {
        self.requiredInputs = requiredInputs
    }

    public func setRequiredInputs(_ inputs: Set<RuntimeInputKey>, at now: Int64) {
        requiredInputs = inputs
        physical = physical.filter { inputs.contains($0.key) }
        virtual = virtual.filter { inputs.contains($0.key) }
        activeLatchedInputs.formIntersection(inputs)
        publish(at: now)
    }

    public func updatePhysical(_ updates: [RuntimeInputKey: AnalysisInputSample], at now: Int64) {
        for (key, sample) in updates where requiredInputs.contains(key) {
            physical[key] = sample
        }
        publish(at: now)
    }

    public func mark(
        _ keys: Set<RuntimeInputKey>,
        unavailable reason: InputUnavailability,
        permission: InputPermission,
        at now: Int64
    ) {
        activeLatchedInputs.subtract(keys)
        for key in keys where requiredInputs.contains(key) {
            let fallback = physical[key]?.value ?? (key == .audioBeat ? .boolean(false) : .number(0))
            physical[key] = AnalysisInputSample(
                value: fallback,
                updatedAtMilliseconds: now,
                availability: .unavailable(reason),
                permission: permission
            )
        }
        publish(at: now)
    }

    /// Keeps the last real value from an actively registered on-change sensor
    /// fresh. No value is created when the provider has not delivered a sample.
    public func setLatchedInputsActive(
        _ keys: Set<RuntimeInputKey>,
        active: Bool,
        at now: Int64
    ) {
        let supported: Set<RuntimeInputKey> = [.sensorNear, .sensorPressure]
        let selected = keys.intersection(supported).intersection(requiredInputs)
        if active {
            activeLatchedInputs.formUnion(selected)
        } else {
            activeLatchedInputs.subtract(selected)
        }
        refreshLatchedSamples(at: now)
        publish(at: now)
    }

    public func setVirtualInput(_ key: RuntimeInputKey, value: EffectValue?, at now: Int64) {
        guard requiredInputs.contains(key) else { return }
        if let value {
            virtual[key] = AnalysisInputSample(value: value, updatedAtMilliseconds: now)
        } else {
            virtual[key] = nil
        }
        publish(at: now)
    }

    public func clearVirtualInputs(at now: Int64) {
        virtual.removeAll(keepingCapacity: true)
        publish(at: now)
    }

    public func snapshot(at now: Int64) -> AnalysisInputSnapshot {
        refreshLatchedSamples(at: now)
        return AnalysisInputSnapshot(
            capturedAtMilliseconds: now,
            requiredInputs: requiredInputs,
            samples: physical.merging(virtual) { _, override in override },
            virtualOverrides: Set(virtual.keys)
        )
    }

    public func snapshots(
        bufferingNewest limit: Int = 1
    ) -> AsyncStream<AnalysisInputSnapshot> {
        let id = UUID()
        let pair = AsyncStream.makeStream(
            of: AnalysisInputSnapshot.self,
            bufferingPolicy: .bufferingNewest(max(1, limit))
        )
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        continuations[id] = pair.continuation
        pair.continuation.yield(snapshot(at: AnalysisClock.monotonicMilliseconds()))
        return pair.stream
    }

    public func finish() {
        for continuation in continuations.values { continuation.finish() }
        continuations.removeAll()
    }

    private func publish(at now: Int64) {
        let value = snapshot(at: now)
        for continuation in continuations.values { continuation.yield(value) }
    }

    private func refreshLatchedSamples(at now: Int64) {
        for key in activeLatchedInputs {
            guard let sample = physical[key], sample.availability == .available else { continue }
            physical[key] = AnalysisInputSample(
                value: sample.value,
                updatedAtMilliseconds: now,
                availability: sample.availability,
                permission: sample.permission
            )
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id]?.finish()
        continuations[id] = nil
    }
}
