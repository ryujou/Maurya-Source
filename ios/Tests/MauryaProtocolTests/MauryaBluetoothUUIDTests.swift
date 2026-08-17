import MauryaProtocol
import Testing

struct MauryaBluetoothUUIDTests {
    @Test func identifiersMatchFirmwareContract() {
        #expect(MauryaBluetoothUUID.service.lowercased() == "0000ffe0-0000-1000-8000-00805f9b34fb")
        #expect(
            MauryaBluetoothUUID.writeCharacteristic.lowercased() == "0000ffe1-0000-1000-8000-00805f9b34fb"
        )
        #expect(
            MauryaBluetoothUUID.notifyCharacteristic.lowercased()
                == "0000ffe2-0000-1000-8000-00805f9b34fb")
        #expect(
            MauryaBluetoothUUID.clientCharacteristicConfiguration.lowercased()
                == "00002902-0000-1000-8000-00805f9b34fb")
    }
}
