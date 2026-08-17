import Foundation
import MauryaProtocol
import Testing

struct EffectGeometryTests {
    @Test func currentFirmwareFallbackIsSevenGroupsOfSix() throws {
        let geometry = EffectGeometry.legacyFirmwareFallback

        #expect(geometry.groupCount == 7)
        #expect(geometry.pixelsPerGroup == 6)
        #expect(geometry.pixelCount == 42)
        #expect(geometry.pixelFrameByteCount == 140)
        #expect(try geometry.pixelRange(forGroupAt: 0) == 0..<6)
        #expect(try geometry.pixelRange(forGroupAt: 6) == 36..<42)
        #expect(try geometry.linearPixelIndex(groupIndex: 0, pixelIndexInGroup: 0) == 0)
        #expect(try geometry.linearPixelIndex(groupIndex: 6, pixelIndexInGroup: 5) == 41)
        let last = try geometry.coordinates(forLinearPixelIndex: 41)
        #expect(last.groupIndex == 6)
        #expect(last.pixelIndexInGroup == 5)
    }

    @Test func negotiatedGeometryIsDynamic() throws {
        let geometry = try EffectGeometry(groupCount: 4, pixelsPerGroup: 8)
        #expect(geometry.pixelCount == 32)
        #expect(try geometry.pixelRange(forGroupAt: 2) == 16..<24)
    }

    @Test func codableRoundTripPreservesValidatedGeometry() throws {
        let geometry = try EffectGeometry(groupCount: 4, pixelsPerGroup: 8)

        let encoded = try JSONEncoder().encode(geometry)
        let decoded = try JSONDecoder().decode(EffectGeometry.self, from: encoded)

        #expect(decoded == geometry)
    }

    @Test func historicalSeventyPixelShapeIsRepresentableButNeverTheFallback() throws {
        let negotiated = try EffectGeometry(groupCount: 7, pixelsPerGroup: 10)
        #expect(negotiated.pixelCount == 70)
        #expect(negotiated != .legacyFirmwareFallback)
        #expect(EffectGeometry.legacyFirmwareFallback.pixelCount == 42)
    }

    @Test func invalidDimensionsAreRejected() {
        #expect(
            throws: EffectGeometryError.invalidDimensions(
                groupCount: 0,
                pixelsPerGroup: 6,
                maximumPixelCount: EffectGeometry.maximumSupportedPixelCount
            )
        ) {
            try EffectGeometry(groupCount: 0, pixelsPerGroup: 6)
        }

        #expect(
            throws: EffectGeometryError.invalidDimensions(
                groupCount: 8,
                pixelsPerGroup: 8,
                maximumPixelCount: 63
            )
        ) {
            try EffectGeometry(groupCount: 8, pixelsPerGroup: 8, maximumPixelCount: 63)
        }

        #expect(throws: EffectGeometryError.self) {
            try EffectGeometry(groupCount: 65, pixelsPerGroup: 64)
        }
    }

    @Test(arguments: [-1, 7])
    func invalidGroupIndexIsRejected(_ index: Int) {
        #expect(throws: EffectGeometryError.groupIndexOutOfBounds(index: index)) {
            try EffectGeometry.legacyFirmwareFallback.pixelRange(forGroupAt: index)
        }
    }

    @Test(arguments: [-1, 6])
    func invalidPixelInGroupIndexIsRejected(_ index: Int) {
        #expect(throws: EffectGeometryError.pixelIndexInGroupOutOfBounds(index: index)) {
            try EffectGeometry.legacyFirmwareFallback.linearPixelIndex(
                groupIndex: 0,
                pixelIndexInGroup: index
            )
        }
    }

    @Test(arguments: [-1, 7])
    func invalidGroupIndexForLinearMappingIsRejected(_ index: Int) {
        #expect(throws: EffectGeometryError.groupIndexOutOfBounds(index: index)) {
            try EffectGeometry.legacyFirmwareFallback.linearPixelIndex(
                groupIndex: index,
                pixelIndexInGroup: 0
            )
        }
    }

    @Test(arguments: [-1, 42])
    func invalidLinearPixelIndexIsRejected(_ index: Int) {
        #expect(throws: EffectGeometryError.linearPixelIndexOutOfBounds(index: index)) {
            try EffectGeometry.legacyFirmwareFallback.coordinates(forLinearPixelIndex: index)
        }
    }

    @Test func decodingCannotBypassGeometryValidation() {
        let invalidJSON = Data(#"{"groupCount":0,"pixelsPerGroup":6}"#.utf8)
        #expect(
            throws: EffectGeometryError.invalidDimensions(
                groupCount: 0,
                pixelsPerGroup: 6,
                maximumPixelCount: EffectGeometry.maximumSupportedPixelCount
            )
        ) {
            try JSONDecoder().decode(EffectGeometry.self, from: invalidJSON)
        }
    }
}
