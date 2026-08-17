import Foundation
import Testing

@testable import MauryaBluetooth

struct ResponseMatcherTests {
    @Test("Accepts normal and exception responses for the active request")
    func expectedFunctions() {
        let request = Data([1, 0x03])
        #expect(ModbusResponseMatcher.matches(request: request, response: Data([1, 0x03])))
        #expect(ModbusResponseMatcher.matches(request: request, response: Data([1, 0x83])))
    }

    @Test("Rejects another unit or function")
    func rejectsUnrelatedFrames() {
        let request = Data([1, 0x03])
        #expect(ModbusResponseMatcher.matches(request: request, response: Data([2, 0x03])) == false)
        #expect(ModbusResponseMatcher.matches(request: request, response: Data([1, 0x06])) == false)
        #expect(ModbusResponseMatcher.matches(request: Data(), response: Data()) == false)
    }

    @Test("Vendor responses must echo the active command")
    func vendorCommandMustMatch() {
        let request = Data([1, 0x41, 1, 0x20])
        #expect(ModbusResponseMatcher.matches(request: request, response: Data([1, 0x41, 2, 0x20])))
        #expect(
            ModbusResponseMatcher.matches(request: request, response: Data([1, 0x41, 2, 0x21])) == false
        )
    }
}
