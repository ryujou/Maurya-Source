import MauryaDevice
import Testing

@testable import Maurya

struct DeviceGroupDraftTests {
    @Test func roundTripPreservesStrobeParameter() {
        let state = DeviceGroupState(
            mode: .strobe,
            hue: 359,
            saturation: 201,
            value: 177,
            parameter: 83
        )
        #expect(DeviceGroupDraft(state).state == state)
    }

    @Test(arguments: [(0, 250), (255, 30), (-1, 250), (256, 30)])
    func strobePeriodMatchesAndroid(_ fixture: (speed: Int, milliseconds: Int)) {
        #expect(DeviceGroupDraft.strobePeriodMilliseconds(speed: fixture.speed) == fixture.milliseconds)
    }
}
