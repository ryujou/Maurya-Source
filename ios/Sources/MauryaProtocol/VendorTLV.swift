import Foundation

public struct VendorTLV: Equatable, Sendable {
    public let type: UInt8
    public let value: Data

    public init(type: UInt8, value: Data) {
        self.type = type
        self.value = value
    }
}
