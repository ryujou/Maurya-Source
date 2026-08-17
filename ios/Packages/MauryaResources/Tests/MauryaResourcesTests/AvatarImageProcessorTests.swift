import CoreGraphics
import Foundation
import Testing

@testable import MauryaResources

@Suite("Avatar image processing")
struct AvatarImageProcessorTests {
    @Test func centerCropEncodesAContractValidWebP() throws {
        let image = try makeGradient(width: 240, height: 160)
        let cropped = try AvatarImageProcessor.centerCrop(image)
        let data = try AvatarImageProcessor.encodeWebP(cropped)
        let metadata = try AvatarValidator.validate(data)

        #expect(metadata.width == 96)
        #expect(metadata.height == 96)
        #expect(data.count <= 6_144)
        #expect(metadata.sha256.count == 64)
    }

    @Test func rejectsWrongOutputDimensions() throws {
        let image = try makeGradient(width: 95, height: 96)
        #expect(throws: AvatarImageProcessingError.renderFailed) {
            try AvatarImageProcessor.encodeWebP(image)
        }
    }

    @Test func cropTransformAndCandidateExtractionAreDeterministic() throws {
        let image = try makeGradient(width: 240, height: 160)
        let original = try AvatarImageProcessor.encodeWebP(AvatarImageProcessor.centerCrop(image))
        let transformedImage = try AvatarImageProcessor.crop(
            image,
            transform: AvatarCropTransform(zoom: 2, offsetX: 0.2, offsetY: -0.1, quarterTurns: 1)
        )
        let transformed = try AvatarImageProcessor.encodeWebP(transformedImage)
        #expect(original != transformed)
        #expect(try AvatarValidator.validate(transformed).width == 96)
    }

    private func makeGradient(width: Int, height: Int) throws -> CGImage {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
        for y in 0..<height {
            let red = CGFloat(y) / CGFloat(max(1, height - 1))
            context.setFillColor(CGColor(red: red, green: 0.3, blue: 1 - red, alpha: 1))
            context.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }
        return try #require(context.makeImage())
    }
}
