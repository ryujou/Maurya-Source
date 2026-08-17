import CoreGraphics
import CoreImage
import Foundation

#if canImport(Vision)
    import Vision
#endif

public enum ShareQRCodeError: Error, Sendable, Equatable {
    case invalidSize
    case generationFailed
    case noValidPayload
}

public enum ShareQRErrorCorrection: String, Sendable, Equatable {
    case high = "H"
}

public struct ShareQRCodeDescriptor: Sendable, Equatable {
    public let payload: String
    public let pixelSize: Int
    public let errorCorrection: ShareQRErrorCorrection
    public let quietZoneModules: Int

    public init(
        payload: String,
        pixelSize: Int = 1_024,
        errorCorrection: ShareQRErrorCorrection = .high,
        quietZoneModules: Int = 4
    ) throws {
        self.payload = try ShareToken.canonicalURL(payload).absoluteString
        guard pixelSize > 0, pixelSize <= 4_096, quietZoneModules >= 0 else {
            throw ShareQRCodeError.invalidSize
        }
        self.pixelSize = pixelSize
        self.errorCorrection = errorCorrection
        self.quietZoneModules = quietZoneModules
    }
}

public enum ShareQRCodeGenerator {
    public static func render(_ descriptor: ShareQRCodeDescriptor) throws -> CGImage {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw ShareQRCodeError.generationFailed
        }
        filter.setValue(Data(descriptor.payload.utf8), forKey: "inputMessage")
        filter.setValue(descriptor.errorCorrection.rawValue, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { throw ShareQRCodeError.generationFailed }

        let modules = Int(output.extent.width)
        let totalModules = modules + descriptor.quietZoneModules * 2
        let scale = descriptor.pixelSize / totalModules
        guard scale >= 1 else { throw ShareQRCodeError.invalidSize }
        let renderedSize = modules * scale
        let offset = (descriptor.pixelSize - renderedSize) / 2
        let transformed = output.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let codeImage = context.createCGImage(transformed, from: transformed.extent),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let bitmap = CGContext(
                data: nil,
                width: descriptor.pixelSize,
                height: descriptor.pixelSize,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw ShareQRCodeError.generationFailed
        }
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: descriptor.pixelSize, height: descriptor.pixelSize))
        bitmap.interpolationQuality = .none
        bitmap.draw(
            codeImage,
            in: CGRect(x: offset, y: offset, width: renderedSize, height: renderedSize)
        )
        guard let image = bitmap.makeImage() else { throw ShareQRCodeError.generationFailed }
        return image
    }
}

public protocol ShareScannedPayloadParsing: Sendable {
    func parseScannedPayload(_ payload: String) throws -> String
}

public struct StrictShareScannedPayloadParser: ShareScannedPayloadParsing, Sendable {
    public init() {}

    public func parseScannedPayload(_ payload: String) throws -> String {
        try ShareToken.parse(payload)
    }
}

#if canImport(Vision)
    /// Parses still images without owning a camera session or requesting permission.
    /// The App remains responsible for AVFoundation capture and camera authorization.
    public struct VisionShareQRCodePayloadProvider: Sendable {
        public init() {}

        public func token(from image: CGImage) throws -> String {
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            for observation in request.results ?? [] {
                if let payload = observation.payloadStringValue,
                    let token = try? ShareToken.parse(payload)
                {
                    return token
                }
            }
            throw ShareQRCodeError.noValidPayload
        }
    }
#endif
