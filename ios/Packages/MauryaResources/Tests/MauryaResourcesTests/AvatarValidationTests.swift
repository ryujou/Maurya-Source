import Foundation
import MauryaResources
import Testing

struct AvatarValidationTests {
    @Test func extractsMetadataAndStableHash() throws {
        let data = Fixtures.WebP96()
        let metadata = try AvatarValidator.validate(data)
        #expect(metadata.width == 96)
        #expect(metadata.height == 96)
        #expect(metadata.byteCount == 30)
        #expect(metadata.codec == .extended)
        #expect(metadata.sha256.count == 64)
        #expect(try AvatarValidator.validate(data, expectedSHA256: metadata.sha256) == metadata)
    }

    @Test func rejectsWrongDimensions() {
        var data = Fixtures.WebP96()
        data[24] = 96
        #expect(throws: AvatarValidationError.invalidDimensions(width: 97, height: 96)) {
            try AvatarValidator.validate(data)
        }
    }

    @Test func rejectsOversizeBeforeParsing() {
        let data = Data(repeating: 0, count: AvatarValidator.maximumBytes + 1)
        #expect(
            throws: AvatarValidationError.sizeExceeded(
                actual: AvatarValidator.maximumBytes + 1,
                maximum: AvatarValidator.maximumBytes
            )
        ) {
            try AvatarValidator.validate(data)
        }
    }

    @Test func rejectsRIFFLengthAndHashMismatch() throws {
        var malformed = Fixtures.WebP96()
        malformed[4] = 21
        #expect(throws: AvatarValidationError.malformedWebP) { try AvatarValidator.validate(malformed) }
        let valid = Fixtures.WebP96()
        #expect(throws: AvatarValidationError.hashMismatch) {
            try AvatarValidator.validate(valid, expectedSHA256: String(repeating: "0", count: 64))
        }
    }
}
