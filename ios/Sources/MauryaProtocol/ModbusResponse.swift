import Foundation

public enum ModbusResponse: Equatable, Sendable {
    case readHoldingRegisters(unitID: UInt8, values: [UInt16])
    case writeSingleAcknowledgement(unitID: UInt8, register: UInt16, value: UInt16)
    case writeMultipleAcknowledgement(unitID: UInt8, startRegister: UInt16, quantity: UInt16)
    case vendor(unitID: UInt8, payload: Data)
    case exception(unitID: UInt8, function: UInt8, code: UInt8)
}
