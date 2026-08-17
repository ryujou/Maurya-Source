import MauryaAnalysis
import MauryaEffects
import Testing

struct AnalysisInputHubTests {
    @Test
    func snapshotTracksAvailabilityFreshnessAndAndroidDefaults() async {
        let hub = AnalysisInputHub(requiredInputs: [.sensorLight, .audioBeat])
        await hub.updatePhysical(
            [
                .sensorLight: .init(value: .number(100), updatedAtMilliseconds: 1_500)
            ], at: 2_000)
        await hub.mark(
            [.audioBeat],
            unavailable: .permissionDenied,
            permission: .denied,
            at: 2_000
        )
        let snapshot = await hub.snapshot(at: 2_000)

        #expect(snapshot.isStale(.sensorLight, nowMilliseconds: 2_500) == false)
        #expect(snapshot.isStale(.sensorLight, nowMilliseconds: 2_501))
        #expect(snapshot.isStale(.audioBeat, nowMilliseconds: 2_000))
        #expect(snapshot.effectRuntimeSnapshot()[.audioBeat] == .boolean(false))
        #expect(snapshot.samples[.audioBeat]?.permission == .denied)
    }

    @Test
    func virtualInputOverridesAndCanBeRemoved() async {
        let hub = AnalysisInputHub(requiredInputs: [.sensorLight])
        await hub.updatePhysical(
            [
                .sensorLight: .init(value: .number(10), updatedAtMilliseconds: 100)
            ], at: 100)
        await hub.setVirtualInput(.sensorLight, value: .number(80), at: 200)
        var snapshot = await hub.snapshot(at: 200)
        #expect(snapshot.effectRuntimeSnapshot()[.sensorLight] == .number(80))
        #expect(snapshot.virtualOverrides == [.sensorLight])

        await hub.setVirtualInput(.sensorLight, value: nil, at: 300)
        snapshot = await hub.snapshot(at: 300)
        #expect(snapshot.effectRuntimeSnapshot()[.sensorLight] == .number(10))
        #expect(snapshot.virtualOverrides.isEmpty)
    }

    @Test
    func streamIsBoundedToNewestSnapshot() async throws {
        let hub = AnalysisInputHub(requiredInputs: [.sensorLight])
        let stream = await hub.snapshots(bufferingNewest: 1)
        await hub.setVirtualInput(.sensorLight, value: .number(1), at: 1)
        await hub.setVirtualInput(.sensorLight, value: .number(2), at: 2)
        await hub.setVirtualInput(.sensorLight, value: .number(3), at: 3)
        var iterator = stream.makeAsyncIterator()
        let latest = try #require(await iterator.next())
        #expect(latest.capturedAtMilliseconds == 3)
        #expect(latest.effectRuntimeSnapshot()[.sensorLight] == .number(3))
        await hub.finish()
    }

    @Test
    func activeLatchedInputsStayFreshWithoutInventingSamples() async throws {
        let hub = AnalysisInputHub(requiredInputs: [.sensorNear, .sensorPressure, .sensorLight])
        await hub.updatePhysical(
            [
                .sensorNear: .init(value: .number(0), updatedAtMilliseconds: 100),
                .sensorPressure: .init(value: .number(1_013.25), updatedAtMilliseconds: 100),
            ],
            at: 100
        )
        await hub.setLatchedInputsActive([.sensorNear, .sensorPressure], active: true, at: 100)

        let stable = await hub.snapshot(at: 5_000)
        #expect(stable.samples[.sensorNear]?.value == .number(0))
        #expect(stable.samples[.sensorPressure]?.value == .number(1_013.25))
        #expect(stable.samples[.sensorNear]?.updatedAtMilliseconds == 5_000)
        #expect(stable.samples[.sensorPressure]?.updatedAtMilliseconds == 5_000)
        #expect(stable.isStale(.sensorNear, nowMilliseconds: 5_000) == false)
        #expect(stable.isStale(.sensorPressure, nowMilliseconds: 5_000) == false)
        #expect(stable.samples[.sensorLight] == nil)
        #expect(stable.isStale(.sensorLight, nowMilliseconds: 5_000))

        await hub.mark(
            [.sensorNear],
            unavailable: .stopped,
            permission: .notRequired,
            at: 5_100
        )
        let stopped = await hub.snapshot(at: 5_100)
        #expect(stopped.isStale(.sensorNear, nowMilliseconds: 5_100))
    }
}
