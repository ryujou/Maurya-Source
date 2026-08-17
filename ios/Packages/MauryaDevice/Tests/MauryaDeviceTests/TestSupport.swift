import Foundation
import MauryaDevice
import MauryaProtocol

func readResponse(unitID: UInt8 = 1, values: [UInt16]) -> Data {
    var payload = Data([unitID, 0x03, UInt8(values.count * 2)])
    for value in values {
        payload.append(UInt8(value >> 8))
        payload.append(UInt8(value & 0xFF))
    }
    return ModbusCRC16.appendingChecksum(to: payload)
}

func vendorResponse(unitID: UInt8 = 1, command: UInt8 = 1, tlvs: [VendorTLV]) throws -> Data {
    let encoded = try VendorTLVCodec.encode(tlvs)
    let vendorPayload = Data([command, 0]) + encoded
    return ModbusCRC16.appendingChecksum(
        to: Data([unitID, 0x41, UInt8(vendorPayload.count)]) + vendorPayload
    )
}

actor QueueTransport: DeviceTransport {
    private var responses: [Result<Data, any Error>]
    private(set) var requests: [Data] = []
    private(set) var timeouts: [Duration] = []

    init(_ responses: [Result<Data, any Error>]) {
        self.responses = responses
    }

    func transact(_ request: Data, timeout: Duration) async throws -> Data {
        requests.append(request)
        timeouts.append(timeout)
        guard responses.isEmpty == false else {
            throw DeviceFailure(.transport, detail: "No queued response")
        }
        return try responses.removeFirst().get()
    }
}

actor SuspendedTransport: DeviceTransport {
    private var continuation: CheckedContinuation<Data, any Error>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasRequest = false

    func transact(_ request: Data, timeout: Duration) async throws -> Data {
        _ = request
        _ = timeout
        hasRequest = true
        let waiters = requestWaiters
        requestWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitForRequest() async {
        if hasRequest { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func succeed(with response: Data) {
        continuation?.resume(returning: response)
        continuation = nil
    }
}

func configurationFixture() -> [UInt16] {
    var values = Array(repeating: UInt16(0), count: DeviceRegisterMap.configurationRegisterCount)
    values[0] = 4
    values[1] = 100
    values[2] = 220
    values[3] = 255
    values[4] = 176
    values[5] = 240
    values[10] = 1
    values[11] = 7
    values[12] = 11
    values[13] = 12
    values[14] = 13
    values[15] = 14
    values[16] = 0xFE0C
    values[17] = 3300
    return values
}

func groupsFixture() -> [UInt16] {
    var values: [UInt16] = []
    for index in 0..<DeviceRegisterMap.groupCount {
        values.append(UInt16(index % 4 + 1))
        values.append(UInt16(index * 30))
        values.append(UInt16(200 + index))
        values.append(UInt16(150 + index))
        values.append(UInt16(100 + index))
    }
    return values
}
