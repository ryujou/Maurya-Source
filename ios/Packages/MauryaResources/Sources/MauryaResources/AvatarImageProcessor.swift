import CWebP
import CoreGraphics
import Foundation
import ImageIO
import MauryaShare

public enum AvatarImageProcessingError: Error, Sendable, Equatable {
    case invalidImage
    case renderFailed
    case encodingUnavailable
    case cannotMeetSizeLimit
}

public struct AvatarCropTransform: Sendable, Equatable {
    public var zoom: Double
    public var offsetX: Double
    public var offsetY: Double
    public var quarterTurns: Int

    public init(zoom: Double = 1, offsetX: Double = 0, offsetY: Double = 0, quarterTurns: Int = 0) {
        self.zoom = min(6, max(1, zoom))
        self.offsetX = min(2, max(-2, offsetX))
        self.offsetY = min(2, max(-2, offsetY))
        self.quarterTurns = ((quarterTurns % 4) + 4) % 4
    }
}

public enum AvatarImageProcessor: Sendable {
    public static let pixelSize = 96
    public static let maximumSourceBytes = 20 * 1_024 * 1_024

    /// Decodes with EXIF orientation, performs an aspect-fill center crop, and
    /// chooses the highest tested WebP quality that satisfies the frozen 6 KiB contract.
    public static func process(
        _ sourceData: Data,
        transform: AvatarCropTransform = .init()
    ) throws -> Data {
        try encodeWebP(crop(try decode(sourceData), transform: transform))
    }

    public static func candidateColors(
        _ sourceData: Data,
        transform: AvatarCropTransform = .init(),
        maximum: Int = 5
    ) throws -> [String] {
        let image = try crop(try decode(sourceData), transform: transform)
        guard let bytes = image.dataProvider?.data as Data? else {
            throw AvatarImageProcessingError.renderFailed
        }
        var buckets: [Int: (count: Int, red: Int, green: Int, blue: Int)] = [:]
        for pixel in stride(from: 0, to: min(bytes.count, pixelSize * pixelSize * 4), by: 16) {
            let red = Int(bytes[pixel])
            let green = Int(bytes[pixel + 1])
            let blue = Int(bytes[pixel + 2])
            let alpha = Int(bytes[pixel + 3])
            let high = max(red, green, blue)
            let low = min(red, green, blue)
            guard alpha >= 160, high >= 18, high <= 246,
                !(high - low < 7 && (high > 224 || high < 36))
            else { continue }
            let key = (red >> 4) << 8 | (green >> 4) << 4 | (blue >> 4)
            let current = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (current.count + 1, current.red + red, current.green + green, current.blue + blue)
        }
        let ranked = buckets.values.sorted { left, right in
            let leftChroma = max(left.red, left.green, left.blue) - min(left.red, left.green, left.blue)
            let rightChroma = max(right.red, right.green, right.blue) - min(right.red, right.green, right.blue)
            return left.count * (256 + leftChroma) > right.count * (256 + rightChroma)
        }
        let values = ranked.prefix(max(1, maximum)).map { bucket in
            String(
                format: "#%02X%02X%02X",
                bucket.red / bucket.count,
                bucket.green / bucket.count,
                bucket.blue / bucket.count
            )
        }
        return values.isEmpty ? ["#66CCFF"] : Array(values)
    }

    private static func decode(_ sourceData: Data) throws -> CGImage {
        guard sourceData.isEmpty == false, sourceData.count <= maximumSourceBytes,
            let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
            CGImageSourceGetCount(source) == 1
        else {
            throw AvatarImageProcessingError.invalidImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_048,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AvatarImageProcessingError.invalidImage
        }
        return image
    }

    public static func centerCrop(_ image: CGImage) throws -> CGImage {
        try crop(image, transform: .init())
    }

    public static func crop(
        _ image: CGImage,
        transform: AvatarCropTransform
    ) throws -> CGImage {
        guard image.width > 0, image.height > 0,
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: pixelSize,
                height: pixelSize,
                bitsPerComponent: 8,
                bytesPerRow: pixelSize * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw AvatarImageProcessingError.renderFailed
        }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(gray: 0, alpha: 0))
        context.fill(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        let rotated = transform.quarterTurns.isMultiple(of: 2) == false
        let logicalWidth = rotated ? image.height : image.width
        let logicalHeight = rotated ? image.width : image.height
        let scale =
            max(
                CGFloat(pixelSize) / CGFloat(logicalWidth),
                CGFloat(pixelSize) / CGFloat(logicalHeight)
            ) * CGFloat(transform.zoom)
        context.translateBy(
            x: CGFloat(pixelSize) * (0.5 + transform.offsetX),
            y: CGFloat(pixelSize) * (0.5 + transform.offsetY)
        )
        context.rotate(by: CGFloat(transform.quarterTurns) * .pi / 2)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let result = context.makeImage() else { throw AvatarImageProcessingError.renderFailed }
        return result
    }

    public static func encodeWebP(_ image: CGImage) throws -> Data {
        guard image.width == pixelSize, image.height == pixelSize else {
            throw AvatarImageProcessingError.renderFailed
        }
        let qualities: [Double] = [0.92, 0.84, 0.76, 0.68, 0.58, 0.48, 0.38, 0.28, 0.18, 0.10, 0.05, 0.02]
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw AvatarImageProcessingError.renderFailed
        }
        let byteCount = pixelSize * pixelSize * 4
        var pixels = [UInt8](repeating: 0, count: byteCount)
        guard
            let context = CGContext(
                data: &pixels,
                width: pixelSize,
                height: pixelSize,
                bitsPerComponent: 8,
                bytesPerRow: pixelSize * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw AvatarImageProcessingError.renderFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        for quality in qualities {
            var encoded: UnsafeMutablePointer<UInt8>?
            let count = pixels.withUnsafeBytes { bytes in
                WebPEncodeRGBA(
                    bytes.bindMemory(to: UInt8.self).baseAddress,
                    Int32(pixelSize),
                    Int32(pixelSize),
                    Int32(pixelSize * 4),
                    Float(quality * 100),
                    &encoded
                )
            }
            guard count > 0, let encoded else { continue }
            let result = Data(bytes: encoded, count: count)
            WebPFree(encoded)
            guard result.count <= ShareEnvelopeCodec.maximumAvatarBytes else { continue }
            _ = try AvatarValidator.validate(result)
            return result
        }
        throw AvatarImageProcessingError.cannotMeetSizeLimit
    }
}
