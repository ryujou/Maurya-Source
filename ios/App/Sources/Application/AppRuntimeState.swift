import Foundation
import Observation

enum AppRuntimeConstraint: Equatable, Sendable {
    case normal
    case lowPower
    case thermal
}

@MainActor
@Observable
final class AppRuntimeState {
    private(set) var constraint: AppRuntimeConstraint

    init(constraint: AppRuntimeConstraint = .normal) {
        self.constraint = constraint
    }

    var allowsRealtimeExecution: Bool { constraint == .normal }

    func refresh(processInfo: ProcessInfo = .processInfo) {
        update(
            lowPowerModeEnabled: processInfo.isLowPowerModeEnabled,
            thermalState: processInfo.thermalState
        )
    }

    func update(lowPowerModeEnabled: Bool, thermalState: ProcessInfo.ThermalState) {
        if thermalState == .serious || thermalState == .critical {
            constraint = .thermal
        } else if lowPowerModeEnabled {
            constraint = .lowPower
        } else {
            constraint = .normal
        }
    }

    var messageKey: String {
        switch constraint {
        case .normal: "runtime.constraint.normal"
        case .lowPower: "runtime.constraint.low-power"
        case .thermal: "runtime.constraint.thermal"
        }
    }
}
