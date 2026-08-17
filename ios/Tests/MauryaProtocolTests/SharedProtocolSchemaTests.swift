import MauryaProtocol
import Testing

struct SharedProtocolSchemaTests {
    @Test func sharedSchemaMatchesProtocolConstants() throws {
        let schema = try RepositoryProtocolFiles.schemaJSONObject()
        let ble = try #require(schema["ble"] as? [String: Any])
        let geometry = try #require(schema["geometry"] as? [String: Any])
        let modbus = try #require(schema["modbusRtu"] as? [String: Any])
        let vendor = try #require(modbus["vendorEnvelope"] as? [String: Any])
        let limits = try #require(modbus["limits"] as? [String: Any])
        let ota = try #require(schema["ota"] as? [String: Any])

        #expect(
            (ble["serviceUuid"] as? String)?.lowercased() == MauryaBluetoothUUID.service.lowercased())
        #expect(
            (ble["writeCharacteristicUuid"] as? String)?.lowercased()
                == MauryaBluetoothUUID.writeCharacteristic.lowercased())
        #expect(
            (ble["notifyCharacteristicUuid"] as? String)?.lowercased()
                == MauryaBluetoothUUID.notifyCharacteristic.lowercased())
        #expect(geometry["groupCount"] as? Int == Int(EffectGeometry.legacyFirmwareFallback.groupCount))
        #expect(
            geometry["pixelsPerGroup"] as? Int
                == Int(EffectGeometry.legacyFirmwareFallback.pixelsPerGroup))
        #expect(geometry["pixelCount"] as? Int == EffectGeometry.legacyFirmwareFallback.pixelCount)
        #expect(vendor["maximumPayloadBytes"] as? Int == ModbusRequest.maximumVendorPayloadByteCount)
        #expect(limits["maximumRegisterCount"] as? Int == ModbusRequest.maximumReadRegisterCount)
        #expect(limits["maximumRegisterCount"] as? Int == ModbusRequest.maximumWriteRegisterCount)
        #expect(
            ota["maximumBleDataChunkBytes"] as? Int == OTAProtocolCodec.maximumFirmwareDataByteCount)
        #expect(ota["layoutVersionSentByAndroid"] as? Int == Int(OTAProtocolCodec.layoutVersion))
    }
}
