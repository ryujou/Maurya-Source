import Foundation
import MauryaProtocol

public struct DeviceCapabilities: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let bleOTA = Self(rawValue: 0x10)
    public static let volatileEffect = Self(rawValue: 0x20)
    public static let pixelEffect = Self(rawValue: 0x40)
    public static let known: Self = [.bleOTA, .volatileEffect, .pixelEffect]

    public var unknownBits: UInt8 {
        rawValue & ~Self.known.rawValue
    }
}

public struct DeviceInfo: Equatable, Sendable {
    public let protocolVersion: UInt8
    public let layoutVersion: UInt8
    public let firmwareVersion: String
    public let variant: String
    public let assetPackVersion: UInt8
    public let capabilities: DeviceCapabilities
    public let secureVersion: UInt32

    public init(
        protocolVersion: UInt8,
        layoutVersion: UInt8,
        firmwareVersion: String,
        variant: String,
        assetPackVersion: UInt8,
        capabilities: DeviceCapabilities,
        secureVersion: UInt32
    ) {
        self.protocolVersion = protocolVersion
        self.layoutVersion = layoutVersion
        self.firmwareVersion = firmwareVersion
        self.variant = variant
        self.assetPackVersion = assetPackVersion
        self.capabilities = capabilities
        self.secureVersion = secureVersion
    }
}

public enum DeviceInfoCodec {
    public static let getInfoCommand: UInt8 = 0x01

    public static func request(unitID: UInt8) throws -> Data {
        try VendorEnvelopeCodec.request(unitID: unitID, payload: Data([getInfoCommand]))
    }

    public static func decodeResponse(_ frame: Data, expectedUnitID: UInt8? = nil) throws -> DeviceInfo {
        let envelope = try VendorEnvelopeCodec.decodeResponse(
            frame,
            expectedCommand: getInfoCommand,
            expectedUnitID: expectedUnitID
        )
        let values = try VendorTLVCodec.decode(envelope.data)
        return DeviceInfo(
            protocolVersion: try byte(type: 0x01, in: values),
            layoutVersion: try byte(type: 0x02, in: values),
            firmwareVersion: try text(type: 0x07, in: values),
            variant: try text(type: 0x03, in: values),
            assetPackVersion: try byte(type: 0x04, in: values),
            capabilities: DeviceCapabilities(rawValue: try byte(type: 0x05, in: values)),
            secureVersion: try VendorTLVCodec.littleEndianUInt32(type: 0x06, in: values)
        )
    }

    private static func byte(type: UInt8, in values: [VendorTLV]) throws -> UInt8 {
        let data = try VendorTLVCodec.lastValue(for: type, in: values)
        guard data.count == 1 else {
            throw VendorProtocolError.invalidTLVLength(type: type, expected: 1, actual: data.count)
        }
        return data[data.startIndex]
    }

    private static func text(type: UInt8, in values: [VendorTLV]) throws -> String {
        let data = try VendorTLVCodec.lastValue(for: type, in: values)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DeviceInfoError.invalidUTF8(type: type)
        }
        return text
    }
}

public enum DeviceInfoError: Error, Equatable, Sendable {
    case invalidUTF8(type: UInt8)
}
