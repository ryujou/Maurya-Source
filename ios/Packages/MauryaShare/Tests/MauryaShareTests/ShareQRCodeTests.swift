import Testing

@testable import MauryaShare

struct ShareQRCodeTests {
    @Test func descriptorCanonicalizesPayloadAndPinsAndroidParameters() throws {
        let descriptor = try ShareQRCodeDescriptor(payload: "K8F3Q-7D2PX")
        #expect(descriptor.payload == "https://xtbang.top/maurya/s/K8F3Q7D2PX")
        #expect(descriptor.pixelSize == 1_024)
        #expect(descriptor.errorCorrection == .high)
        #expect(descriptor.quietZoneModules == 4)
    }

    @Test func renderedImageHasExactRequestedDimensions() throws {
        let image = try ShareQRCodeGenerator.render(ShareQRCodeDescriptor(payload: "K8F3Q7D2PX", pixelSize: 512))
        #expect(image.width == 512)
        #expect(image.height == 512)
    }

    @Test func visionProviderRoundTripsGeneratedCode() throws {
        let image = try ShareQRCodeGenerator.render(ShareQRCodeDescriptor(payload: "K8F3Q7D2PX", pixelSize: 512))
        #expect(try VisionShareQRCodePayloadProvider().token(from: image) == "K8F3Q7D2PX")
    }

    @Test func scannerPayloadParserRejectsForeignLinks() throws {
        let parser = StrictShareScannedPayloadParser()
        #expect(try parser.parseScannedPayload("https://xtbang.top/maurya/s/K8F3Q7D2PX") == "K8F3Q7D2PX")
        #expect(throws: ShareValidationError.invalidToken) {
            try parser.parseScannedPayload("https://example.com/maurya/s/K8F3Q7D2PX")
        }
    }
}
