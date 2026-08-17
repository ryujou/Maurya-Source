import Foundation
import MauryaProtocol

enum TestFixtures {
    static let readRequestPayload = Data([0x01, 0x03, 0x00, 0x00, 0x00, 0x0A])
    static let readRequest = Data([0x01, 0x03, 0x00, 0x00, 0x00, 0x0A, 0xC5, 0xCD])

    static let readResponse = ModbusCRC16.appendingChecksum(
        to: Data([0x01, 0x03, 0x04, 0x00, 0x0A, 0x01, 0x02])
    )
    static let writeSingleResponse = ModbusCRC16.appendingChecksum(
        to: Data([0x01, 0x06, 0x00, 0x20, 0x12, 0x34])
    )
    static let writeMultipleResponse = ModbusCRC16.appendingChecksum(
        to: Data([0x01, 0x10, 0x00, 0x20, 0x00, 0x23])
    )
    static let vendorResponse = ModbusCRC16.appendingChecksum(
        to: Data([0x01, 0x41, 0x03, 0x10, 0x20, 0x30])
    )
    static let exceptionResponse = ModbusCRC16.appendingChecksum(
        to: Data([0x01, 0x83, 0x03])
    )
}
