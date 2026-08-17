import Foundation

public enum DeviceRegisterMap {
    public static let defaultDeviceAddress: UInt8 = 0x01

    public static let sceneMode: UInt16 = 0x0000
    public static let sceneParameter: UInt16 = 0x0001
    public static let globalBrightness: UInt16 = 0x0002
    public static let redGain: UInt16 = 0x0003
    public static let greenGain: UInt16 = 0x0004
    public static let blueGain: UInt16 = 0x0005
    public static let saveState: UInt16 = 0x000A
    public static let deviceAddress: UInt16 = 0x000B
    public static let receiveCount: UInt16 = 0x000C
    public static let receiveOverflowCount: UInt16 = 0x000D
    public static let transmitDropCount: UInt16 = 0x000E
    public static let parseErrorCount: UInt16 = 0x000F
    public static let temperatureCelsiusTimes100: UInt16 = 0x0010
    public static let vddaMillivolts: UInt16 = 0x0011

    public static let groupBase: UInt16 = 0x0020
    public static let groupStride = 5
    public static let groupCount = 7
    public static let groupRegisterCount = groupCount * groupStride
    public static let configurationRegisterCount = 22

    /// Device schema limit. This intentionally does not use Modbus's generic 125-register limit.
    public static let maximumRegistersPerRequest = 64
    public static let diagnosticClearKey: UInt16 = 0xA55A
}

public struct RegisterReadBatch: Equatable, Sendable {
    public let startRegister: UInt16
    public let count: Int

    public init(startRegister: UInt16, count: Int) throws {
        guard (1...DeviceRegisterMap.maximumRegistersPerRequest).contains(count) else {
            throw DeviceMappingError.invalidBatchCount(count)
        }
        guard Int(startRegister) + count - 1 <= Int(UInt16.max) else {
            throw DeviceMappingError.registerRangeOverflow(startRegister: startRegister, count: count)
        }
        self.startRegister = startRegister
        self.count = count
    }
}

public struct RegisterWriteBatch: Equatable, Sendable {
    public let startRegister: UInt16
    public let values: [UInt16]

    public init(startRegister: UInt16, values: [UInt16]) throws {
        guard (1...DeviceRegisterMap.maximumRegistersPerRequest).contains(values.count) else {
            throw DeviceMappingError.invalidBatchCount(values.count)
        }
        guard Int(startRegister) + values.count - 1 <= Int(UInt16.max) else {
            throw DeviceMappingError.registerRangeOverflow(
                startRegister: startRegister,
                count: values.count
            )
        }
        self.startRegister = startRegister
        self.values = values
    }
}

public enum DeviceRegisterBatcher {
    public static func readBatches(startRegister: UInt16, count: Int) throws -> [RegisterReadBatch] {
        guard count > 0 else { throw DeviceMappingError.invalidBatchCount(count) }
        guard Int(startRegister) + count - 1 <= Int(UInt16.max) else {
            throw DeviceMappingError.registerRangeOverflow(startRegister: startRegister, count: count)
        }

        var result: [RegisterReadBatch] = []
        var remaining = count
        var start = startRegister
        while remaining > 0 {
            let size = min(remaining, DeviceRegisterMap.maximumRegistersPerRequest)
            result.append(try RegisterReadBatch(startRegister: start, count: size))
            start += UInt16(size)
            remaining -= size
        }
        return result
    }

    public static func snapshotReads() throws -> [RegisterReadBatch] {
        [
            try RegisterReadBatch(
                startRegister: DeviceRegisterMap.sceneMode,
                count: DeviceRegisterMap.configurationRegisterCount
            ),
            try RegisterReadBatch(
                startRegister: DeviceRegisterMap.groupBase,
                count: DeviceRegisterMap.groupRegisterCount
            ),
        ]
    }

    public static func sceneWrite(_ state: DeviceGlobalState) throws -> RegisterWriteBatch {
        try RegisterWriteBatch(
            startRegister: DeviceRegisterMap.sceneMode,
            values: [state.sceneMode.rawValue, min(state.sceneParameter, 255)]
        )
    }

    public static func globalLEDWrite(_ state: DeviceGlobalState) throws -> RegisterWriteBatch {
        try RegisterWriteBatch(
            startRegister: DeviceRegisterMap.globalBrightness,
            values: [state.brightness, state.redGain, state.greenGain, state.blueGain].map { min($0, 255) }
        )
    }

    public static func groupWrite(index: Int, state: DeviceGroupState) throws -> RegisterWriteBatch {
        guard (0..<DeviceRegisterMap.groupCount).contains(index) else {
            throw DeviceMappingError.invalidGroupIndex(index)
        }
        return try RegisterWriteBatch(
            startRegister: DeviceRegisterMap.groupBase + UInt16(index * DeviceRegisterMap.groupStride),
            values: groupValues(state)
        )
    }

    public static func allGroupsWrite(_ groups: [DeviceGroupState]) throws -> [RegisterWriteBatch] {
        guard groups.count == DeviceRegisterMap.groupCount else {
            throw DeviceMappingError.invalidGroupCount(
                expected: DeviceRegisterMap.groupCount,
                actual: groups.count
            )
        }
        return [
            try RegisterWriteBatch(
                startRegister: DeviceRegisterMap.groupBase,
                values: groups.flatMap(groupValues)
            )
        ]
    }

    private static func groupValues(_ state: DeviceGroupState) -> [UInt16] {
        [
            state.mode.rawValue,
            min(state.hue, 359),
            min(state.saturation, 255),
            min(state.value, 255),
            min(state.parameter, 255),
        ]
    }
}

public enum DeviceMappingError: Error, Equatable, Sendable {
    case invalidBatchCount(Int)
    case registerRangeOverflow(startRegister: UInt16, count: Int)
    case invalidGroupCount(expected: Int, actual: Int)
    case invalidGroupIndex(Int)
    case insufficientRegisters(expected: Int, actual: Int)
    case invalidSceneMode(UInt16)
    case invalidGroupMode(group: Int, value: UInt16)
    case invalidDeviceAddress(UInt16)
}
