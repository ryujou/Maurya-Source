/// Bluetooth SIG base UUID identifiers exposed by the Maurya ESP32 GATT server.
///
/// String values keep this pure Swift module independent of CoreBluetooth.
/// The iOS transport layer constructs `CBUUID` values from these identifiers.
public enum MauryaBluetoothUUID {
    public static let service = "0000FFE0-0000-1000-8000-00805F9B34FB"
    public static let writeCharacteristic = "0000FFE1-0000-1000-8000-00805F9B34FB"
    public static let notifyCharacteristic = "0000FFE2-0000-1000-8000-00805F9B34FB"
    public static let clientCharacteristicConfiguration = "00002902-0000-1000-8000-00805F9B34FB"
}
