import Foundation
import MauryaDevice
import MauryaProtocol

enum OTAResponseCodec {
    static func deviceInformation(_ frame: Data, unitID: UInt8) throws -> OTADeviceInformation {
        let info = try DeviceInfoCodec.decodeResponse(frame, expectedUnitID: unitID)
        return OTADeviceInformation(
            protocolVersion: info.protocolVersion,
            layoutVersion: info.layoutVersion,
            firmwareVersion: info.firmwareVersion,
            variant: info.variant,
            assetPackVersion: info.assetPackVersion,
            capabilities: info.capabilities.rawValue,
            secureVersion: info.secureVersion
        )
    }

    static func empty(_ frame: Data, command: OTACommand, unitID: UInt8) throws {
        _ = try OTAProtocolCodec.parseResponse(frame, command: command, expectedUnitID: unitID)
    }

    static func acknowledgedOffset(_ frame: Data, unitID: UInt8) throws -> UInt32 {
        let envelope = try OTAProtocolCodec.parseResponse(
            frame,
            command: .bleData,
            expectedUnitID: unitID
        )
        return try VendorTLVCodec.littleEndianUInt32(
            type: 0x20,
            in: VendorTLVCodec.decode(envelope.data)
        )
    }

    static func status(_ frame: Data, unitID: UInt8) throws -> OTABLEStatus {
        let envelope = try OTAProtocolCodec.parseResponse(
            frame,
            command: .bleStatus,
            expectedUnitID: unitID
        )
        let values = try VendorTLVCodec.decode(envelope.data)
        let stateData = try VendorTLVCodec.lastValue(for: 0x21, in: values)
        guard stateData.count == 1,
            let state = OTABLEStatus.State(rawValue: stateData[stateData.startIndex])
        else {
            throw OTAFailure.protocolViolation("Unknown OTA device state")
        }
        return OTABLEStatus(
            state: state,
            receivedBytes: try VendorTLVCodec.littleEndianUInt32(type: 0x22, in: values),
            expectedBytes: try VendorTLVCodec.littleEndianUInt32(type: 0x23, in: values),
            errorCode: try VendorTLVCodec.littleEndianUInt32(type: 0x24, in: values)
        )
    }

    static func wifiSession(_ frame: Data, unitID: UInt8) throws -> OTAWiFiSession {
        let envelope = try OTAProtocolCodec.parseResponse(
            frame,
            command: .prepare,
            expectedUnitID: unitID
        )
        let values = try VendorTLVCodec.decode(envelope.data)
        let ssidData = try VendorTLVCodec.lastValue(for: 0x10, in: values)
        guard let ssid = String(data: ssidData, encoding: .utf8) else {
            throw OTAFailure.protocolViolation("Invalid Wi-Fi session SSID")
        }
        let bssid = try VendorTLVCodec.lastValue(for: 0x11, in: values)
        let token = try VendorTLVCodec.lastValue(for: 0x12, in: values)
        guard bssid.count == 6, token.count == 16 else {
            throw OTAFailure.protocolViolation("Invalid Wi-Fi session credentials")
        }
        return OTAWiFiSession(
            ssid: ssid,
            bssid: bssid,
            token: token,
            timeoutSeconds: try VendorTLVCodec.littleEndianUInt32(type: 0x13, in: values)
        )
    }
}
