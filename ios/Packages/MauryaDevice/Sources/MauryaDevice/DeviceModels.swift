import Foundation

public enum SceneMode: UInt16, CaseIterable, Sendable {
    case `static` = 1
    case flowLeft = 2
    case flowRight = 3
    case flowPingPong = 4
}

public enum GroupMode: UInt16, CaseIterable, Sendable {
    case steady = 1
    case breathing = 2
    case strobe = 3
    case gradient = 4
}

public struct DeviceGlobalState: Equatable, Sendable {
    public var sceneMode: SceneMode
    public var sceneParameter: UInt16
    public var brightness: UInt16
    public var redGain: UInt16
    public var greenGain: UInt16
    public var blueGain: UInt16
    public var saveState: UInt16
    public var deviceAddress: UInt8

    public init(
        sceneMode: SceneMode = .static,
        sceneParameter: UInt16 = 80,
        brightness: UInt16 = 255,
        redGain: UInt16 = 255,
        greenGain: UInt16 = 176,
        blueGain: UInt16 = 240,
        saveState: UInt16 = 0,
        deviceAddress: UInt8 = 1
    ) {
        self.sceneMode = sceneMode
        self.sceneParameter = sceneParameter
        self.brightness = brightness
        self.redGain = redGain
        self.greenGain = greenGain
        self.blueGain = blueGain
        self.saveState = saveState
        self.deviceAddress = deviceAddress
    }
}

public struct DeviceGroupState: Equatable, Sendable {
    public var mode: GroupMode
    public var hue: UInt16
    public var saturation: UInt16
    public var value: UInt16
    public var parameter: UInt16

    public init(
        mode: GroupMode = .steady,
        hue: UInt16 = 30,
        saturation: UInt16 = 255,
        value: UInt16 = 255,
        parameter: UInt16 = 255
    ) {
        self.mode = mode
        self.hue = min(hue, 359)
        self.saturation = min(saturation, 255)
        self.value = min(value, 255)
        self.parameter = min(parameter, 255)
    }
}

public struct DeviceDiagnostics: Equatable, Sendable {
    public var receiveCount: UInt16
    public var receiveOverflowCount: UInt16
    public var transmitDropCount: UInt16
    public var parseErrorCount: UInt16
    public var temperatureCelsiusTimes100: Int16
    public var vddaMillivolts: UInt16

    public init(
        receiveCount: UInt16 = 0,
        receiveOverflowCount: UInt16 = 0,
        transmitDropCount: UInt16 = 0,
        parseErrorCount: UInt16 = 0,
        temperatureCelsiusTimes100: Int16 = 0,
        vddaMillivolts: UInt16 = 0
    ) {
        self.receiveCount = receiveCount
        self.receiveOverflowCount = receiveOverflowCount
        self.transmitDropCount = transmitDropCount
        self.parseErrorCount = parseErrorCount
        self.temperatureCelsiusTimes100 = temperatureCelsiusTimes100
        self.vddaMillivolts = vddaMillivolts
    }
}

public struct DeviceSnapshot: Equatable, Sendable {
    public let global: DeviceGlobalState
    public let groups: [DeviceGroupState]
    public let diagnostics: DeviceDiagnostics

    public init(
        global: DeviceGlobalState,
        groups: [DeviceGroupState],
        diagnostics: DeviceDiagnostics
    ) throws {
        guard groups.count == DeviceRegisterMap.groupCount else {
            throw DeviceMappingError.invalidGroupCount(
                expected: DeviceRegisterMap.groupCount,
                actual: groups.count
            )
        }
        self.global = global
        self.groups = groups
        self.diagnostics = diagnostics
    }
}

public enum DeviceValueFreshness: Equatable, Sendable {
    case current
    case pending
    case stale
    case failed(DeviceFailure)
}

public struct DeviceRepositoryState: Equatable, Sendable {
    public var isConnected: Bool
    public var snapshot: DeviceSnapshot?
    public var freshness: DeviceValueFreshness

    public init(
        isConnected: Bool,
        snapshot: DeviceSnapshot? = nil,
        freshness: DeviceValueFreshness = .stale
    ) {
        self.isConnected = isConnected
        self.snapshot = snapshot
        self.freshness = freshness
    }
}
