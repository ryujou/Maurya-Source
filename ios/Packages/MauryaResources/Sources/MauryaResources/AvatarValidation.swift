import CryptoKit
import Foundation
import MauryaShare

public struct AvatarMetadata: Codable, Sendable, Equatable {
    public enum Codec: String, Codable, Sendable {
        case lossy = "VP8 "
        case lossless = "VP8L"
        case extended = "VP8X"
    }

    public let width: Int
    public let height: Int
    public let byteCount: Int
    public let sha256: String
    public let codec: Codec
}

public enum AvatarValidationError: Error, Sendable, Equatable {
    case empty
    case sizeExceeded(actual: Int, maximum: Int)
    case malformedWebP
    case invalidDimensions(width: Int, height: Int)
    case hashMismatch
}

public enum AvatarValidator {
    public static let requiredDimension = 96
    public static let maximumBytes = ShareEnvelopeCodec.maximumAvatarBytes

    public static func validate(_ data: Data, expectedSHA256: String? = nil) throws -> AvatarMetadata {
        guard data.isEmpty == false else { throw AvatarValidationError.empty }
        guard data.count <= maximumBytes else {
            throw AvatarValidationError.sizeExceeded(actual: data.count, maximum: maximumBytes)
        }
        let bytes = [UInt8](data)
        guard bytes.count >= 30,
            ascii(bytes, 0..<4) == "RIFF",
            ascii(bytes, 8..<12) == "WEBP",
            littleEndian32(bytes, at: 4) == UInt32(bytes.count - 8),
            let codec = AvatarMetadata.Codec(rawValue: ascii(bytes, 12..<16)),
            let dimensions = dimensions(bytes, codec: codec)
        else {
            throw AvatarValidationError.malformedWebP
        }
        guard dimensions.width == requiredDimension, dimensions.height == requiredDimension else {
            throw AvatarValidationError.invalidDimensions(width: dimensions.width, height: dimensions.height)
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let expectedSHA256,
            constantTimeEqual(digest, expectedSHA256.lowercased()) == false
        {
            throw AvatarValidationError.hashMismatch
        }
        return AvatarMetadata(
            width: dimensions.width,
            height: dimensions.height,
            byteCount: data.count,
            sha256: digest,
            codec: codec
        )
    }

    private static func dimensions(_ bytes: [UInt8], codec: AvatarMetadata.Codec) -> (width: Int, height: Int)? {
        let chunkLength = Int(littleEndian32(bytes, at: 16))
        guard chunkLength <= bytes.count - 20,
            chunkLength + (chunkLength & 1) <= bytes.count - 20
        else { return nil }
        switch codec {
        case .extended:
            guard chunkLength >= 10 else { return nil }
            return (1 + littleEndian24(bytes, at: 24), 1 + littleEndian24(bytes, at: 27))
        case .lossless:
            guard chunkLength >= 5, bytes[20] == 0x2f else { return nil }
            let bits = littleEndian32(bytes, at: 21)
            return (Int(bits & 0x3fff) + 1, Int((bits >> 14) & 0x3fff) + 1)
        case .lossy:
            guard chunkLength >= 10,
                bytes[23] == 0x9d, bytes[24] == 0x01, bytes[25] == 0x2a
            else { return nil }
            return (littleEndian16(bytes, at: 26) & 0x3fff, littleEndian16(bytes, at: 28) & 0x3fff)
        }
    }

    private static func ascii(_ bytes: [UInt8], _ range: Range<Int>) -> String {
        String(decoding: bytes[range], as: UTF8.self)
    }

    private static func littleEndian16(_ bytes: [UInt8], at offset: Int) -> Int {
        Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
    }

    private static func littleEndian24(_ bytes: [UInt8], at offset: Int) -> Int {
        littleEndian16(bytes, at: offset) | (Int(bytes[offset + 2]) << 16)
    }

    private static func littleEndian32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8) | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }
}

public extension PaletteSharePayload {
    func validatedAvatarMetadata() throws -> AvatarMetadata {
        try AvatarValidator.validate(avatarWebP, expectedSHA256: avatarSHA256)
    }
}
