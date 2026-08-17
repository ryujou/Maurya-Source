import Foundation
import MauryaProtocol
import Testing

struct ModbusRequestTests {
    @Test func readHoldingRequestMatchesGoldenVector() throws {
        let request = try ModbusRequest.readHoldingRegisters(
            unitID: 0x01,
            startRegister: 0x0000,
            quantity: 10
        )
        #expect(request == TestFixtures.readRequest)
    }

    @Test func writeSingleEncodesBigEndianWordsAndLittleEndianCRC() {
        let request = ModbusRequest.writeSingleRegister(
            unitID: 0x01,
            register: 0x0020,
            value: 0x1234
        )
        #expect(Data(request.prefix(6)) == Data([0x01, 0x06, 0x00, 0x20, 0x12, 0x34]))
        #expect(ModbusCRC16.validates(request))
    }

    @Test func writeMultipleMatchesAndroidThirtyFiveRegisterShape() throws {
        let values = (1...35).map(UInt16.init)
        let request = try ModbusRequest.writeMultipleRegisters(
            unitID: 0x01,
            startRegister: 0x0020,
            values: values
        )

        #expect(request[request.startIndex] == 0x01)
        #expect(request[request.index(request.startIndex, offsetBy: 1)] == 0x10)
        #expect(Data(request[2...6]) == Data([0x00, 0x20, 0x00, 0x23, 0x46]))
        #expect(Data(request[7...10]) == Data([0x00, 0x01, 0x00, 0x02]))
        #expect(ModbusCRC16.validates(request))
    }

    @Test(arguments: [0, 65])
    func readQuantityOutsideProtocolBoundsIsRejected(_ quantity: Int) {
        #expect(throws: ModbusError.invalidQuantity(quantity)) {
            try ModbusRequest.readHoldingRegisters(unitID: 1, startRegister: 0, quantity: quantity)
        }
    }

    @Test func firmwareBulkLimitAcceptsExactlySixtyFourAndRejectsSixtyFive() throws {
        _ = try ModbusRequest.readHoldingRegisters(unitID: 1, startRegister: 0, quantity: 64)
        _ = try ModbusRequest.writeMultipleRegisters(
            unitID: 1,
            startRegister: 0,
            values: Array(repeating: 0, count: 64)
        )
        #expect(throws: ModbusError.invalidQuantity(65)) {
            try ModbusRequest.writeMultipleRegisters(
                unitID: 1,
                startRegister: 0,
                values: Array(repeating: 0, count: 65)
            )
        }
    }

    @Test func emptyMultipleWriteIsRejected() {
        #expect(throws: ModbusError.invalidQuantity(0)) {
            try ModbusRequest.writeMultipleRegisters(unitID: 1, startRegister: 0, values: [])
        }
    }

    @Test func registerRangesMayNotWrapPastMaximumAddress() {
        #expect(
            throws: ModbusError.registerRangeOverflow(
                startRegister: UInt16.max,
                quantity: 2
            )
        ) {
            try ModbusRequest.readHoldingRegisters(
                unitID: 1,
                startRegister: UInt16.max,
                quantity: 2
            )
        }

        #expect(
            throws: ModbusError.registerRangeOverflow(
                startRegister: UInt16.max,
                quantity: 2
            )
        ) {
            try ModbusRequest.writeMultipleRegisters(
                unitID: 1,
                startRegister: UInt16.max,
                values: [1, 2]
            )
        }
    }

    @Test func vendorPayloadLimitMatchesAndroidContract() throws {
        let maximum = ModbusRequest.maximumVendorPayloadByteCount
        let accepted = try ModbusRequest.vendor(
            unitID: 1, payload: Data(repeating: 0xA5, count: maximum))
        #expect(ModbusCRC16.validates(accepted))

        #expect(throws: ModbusError.vendorPayloadTooLarge(actual: maximum + 1, maximum: maximum)) {
            try ModbusRequest.vendor(unitID: 1, payload: Data(repeating: 0xA5, count: maximum + 1))
        }
    }
}
