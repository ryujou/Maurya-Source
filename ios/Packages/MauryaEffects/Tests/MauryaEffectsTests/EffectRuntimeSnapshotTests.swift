import Testing

@testable import MauryaEffects

struct EffectRuntimeSnapshotTests {
    @Test
    func defaultsAvailabilityAndTimestampsFromValues() {
        let snapshot = EffectRuntimeSnapshot(
            capturedAtMilliseconds: 2_000,
            values: [.sensorLight: .number(100)]
        )

        #expect(snapshot.available == [.sensorLight])
        #expect(snapshot.updatedAtMilliseconds == [.sensorLight: 2_000])
        #expect(snapshot[.sensorLight] == .number(100))
    }

    @Test
    func missingInputsMatchAndroidDefaultTypes() {
        #expect(EffectRuntimeSnapshot.empty[.audioBeat] == .boolean(false))
        #expect(EffectRuntimeSnapshot.empty[.audioLevel] == .number(0))
        #expect(EffectRuntimeSnapshot.empty[.sensorPressure] == .number(0))
    }

    @Test
    func freshnessBoundaryMatchesAndroidStrictGreaterThanRule() {
        let snapshot = EffectRuntimeSnapshot(
            capturedAtMilliseconds: 2_000,
            values: [.sensorLight: .number(100)],
            updatedAtMilliseconds: [.sensorLight: 1_500]
        )

        #expect(snapshot.isStale(.sensorLight, nowMilliseconds: 2_000) == false)
        #expect(snapshot.isStale(.sensorLight, nowMilliseconds: 2_500) == false)
        #expect(snapshot.isStale(.sensorLight, nowMilliseconds: 2_501))
        #expect(snapshot.isStale(.audioLevel, nowMilliseconds: 2_000))
    }

    @Test
    func unavailableInputIsStaleEvenWithAValue() {
        let snapshot = EffectRuntimeSnapshot(
            capturedAtMilliseconds: 100,
            values: [.sensorLight: .number(80)],
            available: [],
            updatedAtMilliseconds: [.sensorLight: 100]
        )

        #expect(snapshot[.sensorLight] == .number(80))
        #expect(snapshot.isStale(.sensorLight, nowMilliseconds: 100))
    }
}
