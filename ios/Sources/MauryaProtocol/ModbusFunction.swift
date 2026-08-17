public enum ModbusFunction: UInt8, CaseIterable, Sendable {
    case readHoldingRegisters = 0x03
    case writeSingleRegister = 0x06
    case writeMultipleRegisters = 0x10
    case vendor = 0x41
}
