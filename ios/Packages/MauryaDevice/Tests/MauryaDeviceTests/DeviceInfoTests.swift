import Foundation
import MauryaDevice
import MauryaProtocol
import Testing

struct DeviceInfoTests {
    @Test("Get-info parser matches Android TLV fields and preserves unknown capability bits")
    func parsesInfo() throws {
        let frame = try vendorResponse(tlvs: [
            VendorTLV(type: 1, value: Data([1])),
            VendorTLV(type: 2, value: Data([2])),
            VendorTLV(type: 3, value: Data("esp32".utf8)),
            VendorTLV(type: 4, value: Data([3])),
            VendorTLV(type: 5, value: Data([0x7F])),
            VendorTLV(type: 6, value: Data([4, 3, 2, 1])),
            VendorTLV(type: 7, value: Data("1.7.1".utf8)),
        ])

        let info = try DeviceInfoCodec.decodeResponse(frame, expectedUnitID: 1)

        #expect(info.protocolVersion == 1)
        #expect(info.layoutVersion == 2)
        #expect(info.variant == "esp32")
        #expect(info.firmwareVersion == "1.7.1")
        #expect(info.assetPackVersion == 3)
        #expect(info.secureVersion == 0x0102_0304)
        #expect(info.capabilities.contains(.bleOTA))
        #expect(info.capabilities.contains(.volatileEffect))
        #expect(info.capabilities.contains(.pixelEffect))
        #expect(info.capabilities.unknownBits == 0x0F)
    }

    @Test("Missing required info field fails protocol parsing")
    func missingTLV() throws {
        let frame = try vendorResponse(tlvs: [])
        #expect(throws: VendorProtocolError.missingTLV(type: 1)) {
            try DeviceInfoCodec.decodeResponse(frame)
        }
    }
}
