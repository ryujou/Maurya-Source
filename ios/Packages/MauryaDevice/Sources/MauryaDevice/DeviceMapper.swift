public enum DeviceMapper {
    public static func snapshot(
        configuration: [UInt16],
        groupRegisters: [UInt16]
    ) throws -> DeviceSnapshot {
        guard configuration.count >= DeviceRegisterMap.configurationRegisterCount else {
            throw DeviceMappingError.insufficientRegisters(
                expected: DeviceRegisterMap.configurationRegisterCount,
                actual: configuration.count
            )
        }
        guard groupRegisters.count >= DeviceRegisterMap.groupRegisterCount else {
            throw DeviceMappingError.insufficientRegisters(
                expected: DeviceRegisterMap.groupRegisterCount,
                actual: groupRegisters.count
            )
        }
        guard let sceneMode = SceneMode(rawValue: configuration[0]) else {
            throw DeviceMappingError.invalidSceneMode(configuration[0])
        }
        guard let address = UInt8(exactly: configuration[11]) else {
            throw DeviceMappingError.invalidDeviceAddress(configuration[11])
        }

        let groups = try (0..<DeviceRegisterMap.groupCount).map { index in
            let base = index * DeviceRegisterMap.groupStride
            guard let mode = GroupMode(rawValue: groupRegisters[base]) else {
                throw DeviceMappingError.invalidGroupMode(group: index, value: groupRegisters[base])
            }
            return DeviceGroupState(
                mode: mode,
                hue: groupRegisters[base + 1],
                saturation: groupRegisters[base + 2],
                value: groupRegisters[base + 3],
                parameter: groupRegisters[base + 4]
            )
        }

        return try DeviceSnapshot(
            global: DeviceGlobalState(
                sceneMode: sceneMode,
                sceneParameter: configuration[1],
                brightness: configuration[2],
                redGain: configuration[3],
                greenGain: configuration[4],
                blueGain: configuration[5],
                saveState: configuration[10],
                deviceAddress: address
            ),
            groups: groups,
            diagnostics: DeviceDiagnostics(
                receiveCount: configuration[12],
                receiveOverflowCount: configuration[13],
                transmitDropCount: configuration[14],
                parseErrorCount: configuration[15],
                temperatureCelsiusTimes100: Int16(bitPattern: configuration[16]),
                vddaMillivolts: configuration[17]
            )
        )
    }
}
