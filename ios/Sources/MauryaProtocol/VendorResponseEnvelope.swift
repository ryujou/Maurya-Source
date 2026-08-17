import Foundation

public struct VendorResponseEnvelope: Equatable, Sendable {
    public let unitID: UInt8
    public let command: UInt8
    public let status: UInt8
    public let data: Data

    public init(unitID: UInt8, command: UInt8, status: UInt8, data: Data) {
        self.unitID = unitID
        self.command = command
        self.status = status
        self.data = data
    }
}
