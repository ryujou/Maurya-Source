import Foundation
import Testing

@testable import MauryaBluetooth

struct WriteFragmenterTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let payloadCount: Int
        let maximumLength: Int
        let expectedChunkCounts: [Int]

        var testDescription: String {
            "\(payloadCount) bytes at MTU payload \(maximumLength)"
        }
    }

    @Test(
        "Uses maximumWriteValueLength without empty trailing chunks",
        arguments: [
            Case(payloadCount: 0, maximumLength: 20, expectedChunkCounts: []),
            Case(payloadCount: 1, maximumLength: 20, expectedChunkCounts: [1]),
            Case(payloadCount: 20, maximumLength: 20, expectedChunkCounts: [20]),
            Case(payloadCount: 21, maximumLength: 20, expectedChunkCounts: [20, 1]),
            Case(payloadCount: 140, maximumLength: 64, expectedChunkCounts: [64, 64, 12]),
        ]
    )
    func boundaries(testCase: Case) throws {
        let payload = Data((0..<testCase.payloadCount).map { UInt8(truncatingIfNeeded: $0) })
        let chunks = try WriteFragmenter.chunks(
            for: payload,
            maximumLength: testCase.maximumLength
        )

        #expect(chunks.map(\.count) == testCase.expectedChunkCounts)
        #expect(chunks.reduce(into: Data()) { $0.append($1) } == payload)
    }

    @Test("Rejects zero or negative write capacity", arguments: [0, -1])
    func rejectsInvalidMaximum(maximum: Int) {
        #expect(throws: BluetoothFailure.self) {
            try WriteFragmenter.chunks(for: Data([1]), maximumLength: maximum)
        }
    }
}
