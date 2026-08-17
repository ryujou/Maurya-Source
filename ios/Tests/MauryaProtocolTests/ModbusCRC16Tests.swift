import Foundation
import MauryaProtocol
import Testing

struct ModbusCRC16Tests {
    @Test func emptyInputUsesModbusInitialValue() {
        #expect(ModbusCRC16.checksum(of: Data()) == 0xFFFF)
    }

    @Test func standardReadRequestMatchesGoldenVector() {
        #expect(ModbusCRC16.checksum(of: TestFixtures.readRequestPayload) == 0xCDC5)
        #expect(
            ModbusCRC16.appendingChecksum(to: TestFixtures.readRequestPayload) == TestFixtures.readRequest
        )
        #expect(ModbusCRC16.validates(TestFixtures.readRequest))
    }

    @Test func singleBitCorruptionFailsValidation() {
        var corrupted = TestFixtures.readRequest
        corrupted[corrupted.startIndex] ^= 0x01

        #expect(ModbusCRC16.validates(corrupted) == false)
    }

    @Test(arguments: [Data(), Data([0x01])])
    func incompleteChecksumIsRejected(_ frame: Data) {
        #expect(ModbusCRC16.validates(frame) == false)
    }
}
