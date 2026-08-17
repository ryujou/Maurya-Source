import Foundation
import Testing

@testable import Maurya

@MainActor
struct AppRuntimeStateTests {
    @Test func seriousThermalStateTakesPriorityOverLowPowerMode() {
        let state = AppRuntimeState()

        state.update(lowPowerModeEnabled: true, thermalState: .serious)

        #expect(state.constraint == .thermal)
        #expect(state.allowsRealtimeExecution == false)
    }

    @Test func lowPowerModeBlocksRealtimeExecutionUntilConditionsRecover() {
        let state = AppRuntimeState()
        state.update(lowPowerModeEnabled: true, thermalState: .nominal)
        #expect(state.constraint == .lowPower)

        state.update(lowPowerModeEnabled: false, thermalState: .fair)

        #expect(state.constraint == .normal)
        #expect(state.allowsRealtimeExecution)
    }
}
