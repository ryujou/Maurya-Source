import MauryaDevice
import Testing

struct DeviceMappingTests {
    @Test("Android register snapshot maps all seven groups and signed temperature")
    func mapsSnapshot() throws {
        let snapshot = try DeviceMapper.snapshot(
            configuration: configurationFixture(),
            groupRegisters: groupsFixture()
        )

        #expect(snapshot.global.sceneMode == .flowPingPong)
        #expect(snapshot.global.deviceAddress == 7)
        #expect(snapshot.diagnostics.temperatureCelsiusTimes100 == -500)
        #expect(snapshot.diagnostics.vddaMillivolts == 3300)
        #expect(snapshot.groups.count == 7)
        #expect(snapshot.groups.first?.mode == .steady)
        #expect(snapshot.groups.last?.hue == 180)
        #expect(snapshot.groups.last?.saturation == 206)
        #expect(snapshot.groups.last?.value == 156)
        #expect(snapshot.groups.last?.parameter == 106)
    }

    @Test("Every group index maps to its five-register address", arguments: 0..<7)
    func groupAddress(index: Int) throws {
        let batch = try DeviceRegisterBatcher.groupWrite(index: index, state: DeviceGroupState())
        #expect(batch.startRegister == 0x0020 + UInt16(index * 5))
        #expect(batch.values.count == 5)
    }

    @Test("All seven groups flatten into one 35-register schema-safe write")
    func allGroupsBatch() throws {
        var groups: [DeviceGroupState] = []
        for index in 0..<7 {
            let rawMode = UInt16(index % 4 + 1)
            let mode = GroupMode(rawValue: rawMode) ?? .steady
            groups.append(
                DeviceGroupState(
                    mode: mode,
                    hue: UInt16(index),
                    saturation: UInt16(10 + index),
                    value: UInt16(20 + index),
                    parameter: UInt16(30 + index)
                ))
        }
        let batches = try DeviceRegisterBatcher.allGroupsWrite(groups)
        let batch = try #require(batches.first)

        #expect(batch.startRegister == DeviceRegisterMap.groupBase)
        #expect(batch.values.count == 35)
        #expect(Array(batch.values.prefix(5)) == [1, 0, 10, 20, 30])
        #expect(Array(batch.values.suffix(5)) == [3, 6, 16, 26, 36])
    }

    @Test("Read batching uses the schema limit of 64, never generic Modbus 125")
    func schemaReadLimit() throws {
        let batches = try DeviceRegisterBatcher.readBatches(startRegister: 0, count: 130)
        #expect(batches.map(\.count) == [64, 64, 2])
        #expect(batches.allSatisfy { $0.count <= DeviceRegisterMap.maximumRegistersPerRequest })
        #expect(DeviceRegisterMap.maximumRegistersPerRequest == 64)
    }

    @Test("Out-of-range groups are rejected", arguments: [-1, 7])
    func rejectsGroupIndex(index: Int) {
        #expect(throws: DeviceMappingError.invalidGroupIndex(index)) {
            try DeviceRegisterBatcher.groupWrite(index: index, state: DeviceGroupState())
        }
    }
}
