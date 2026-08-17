import Foundation
import MauryaProtocol
import Testing

struct SharedGoldenVectorTests {
    @Test func crcVectorsAreConsumedFromRepositoryFile() throws {
        let document = try RepositoryProtocolFiles.goldenVectors()

        for vector in document.crc {
            let input = try vector.inputHex.hexadecimalData()
            let expectedValueData = try vector.crcValueHex.hexadecimalData()
            var valueReader = try DataReader(data: expectedValueData)
            let expectedValue = try valueReader.readUInt16BigEndian()
            let wireSuffix = try vector.wireSuffixHex.hexadecimalData()

            #expect(ModbusCRC16.checksum(of: input) == expectedValue, "CRC vector: \(vector.id)")
            #expect(
                ModbusCRC16.appendingChecksum(to: input).suffix(2) == wireSuffix,
                "CRC wire order: \(vector.id)")
        }
    }

    @Test func everyFrameVectorMatchesCodecOrParser() throws {
        let document = try RepositoryProtocolFiles.goldenVectors()
        let generated = try generatedFrames()

        for vector in document.frames {
            let expected = try vector.hex.hexadecimalData()
            #expect(expected.count == vector.completeFrameBytes, "JSON length: \(vector.id)")
            #expect(ModbusCRC16.validates(expected), "JSON CRC: \(vector.id)")

            if vector.id == "modbus-exception-illegal-value" {
                #expect(
                    try ModbusResponseCodec.decode(expected)
                        == .exception(unitID: 1, function: 0x83, code: 0x03)
                )
            } else {
                let actual = try #require(generated[vector.id], "Missing generated frame for \(vector.id)")
                #expect(actual == expected, "Frame vector: \(vector.id)")
            }
        }

        #expect(generated.count + 1 == document.frames.count)
    }

    @Test func mappingVectorsMatchFallbackGeometry() throws {
        let document = try RepositoryProtocolFiles.goldenVectors()
        let geometry = EffectGeometry.legacyFirmwareFallback

        for mapping in document.mapping {
            let calculated = try geometry.linearPixelIndex(
                groupIndex: mapping.groupOneBased - 1,
                pixelIndexInGroup: mapping.pixelInGroupOneBased - 1
            )
            #expect(calculated == mapping.linearZeroBased)
            #expect(calculated + 1 == mapping.globalOneBased)
            let reverse = try geometry.coordinates(forLinearPixelIndex: mapping.linearZeroBased)
            #expect(reverse.groupIndex + 1 == mapping.groupOneBased)
            #expect(reverse.pixelIndexInGroup + 1 == mapping.pixelInGroupOneBased)
        }
    }

    private func generatedFrames() throws -> [String: Data] {
        let groups = (0..<7).map { index in
            EffectGroupState(
                innerMode: 1,
                hue: UInt16(index * 50),
                saturation: 255,
                value: 200,
                innerParameter: UInt8(100 + index)
            )
        }
        var pixels: [EffectRGB] = []
        for index in 0..<EffectGeometry.legacyFirmwareFallback.pixelCount {
            let pixel = EffectRGB(
                red: UInt8(index),
                green: UInt8(255 - index),
                blue: UInt8((3 * index) % 256)
            )
            pixels.append(pixel)
        }

        return [
            "modbus-read-groups-first-five": try ModbusRequest.readHoldingRegisters(
                unitID: 1,
                startRegister: 0x0020,
                quantity: 5
            ),
            "modbus-write-global-brightness": ModbusRequest.writeSingleRegister(
                unitID: 1,
                register: 0x0002,
                value: 0x00FF
            ),
            "modbus-write-two-group-registers": try ModbusRequest.writeMultipleRegisters(
                unitID: 1,
                startRegister: 0x0020,
                values: [1, 2]
            ),
            "vendor-get-info-request": try OTAProtocolCodec.getInfoRequest(unitID: 1),
            "effect-begin-request": try EffectProtocolCodec.beginRequest(unitID: 1),
            "effect-heartbeat-request": try EffectProtocolCodec.heartbeatRequest(
                unitID: 1,
                sessionID: 0x1234_5678
            ),
            "effect-end-request": try EffectProtocolCodec.endRequest(
                unitID: 1,
                sessionID: 0x1234_5678
            ),
            "effect-seven-group-frame": try EffectProtocolCodec.groupFrameRequest(
                unitID: 1,
                sessionID: 0x1234_5678,
                sequence: 0x3456,
                groups: groups
            ),
            "effect-42-pixel-frame": try EffectProtocolCodec.pixelFrameRequest(
                unitID: 1,
                sessionID: 0x7856_3412,
                sequence: 0x9ABC,
                pixels: pixels
            ),
            "ota-prepare-request": try OTAProtocolCodec.prepareRequest(
                unitID: 1,
                nonce: Data((0..<16).map(UInt8.init))
            ),
            "ota-ble-begin-request": try OTAProtocolCodec.bleBeginRequest(
                unitID: 1,
                expectedBytes: 987_136,
                sha256: Data(repeating: 0, count: 32)
            ),
            "ota-ble-data-maximum-android-chunk": try OTAProtocolCodec.bleDataRequest(
                unitID: 1,
                offset: 0,
                firmwareData: Data((0..<118).map(UInt8.init))
            ),
            "ota-ble-status-request": try OTAProtocolCodec.bleStatusRequest(unitID: 1),
        ]
    }
}
