import CZlib
import Foundation

enum Gzip {
    static func compress(_ input: Data, maximumOutput: Int) throws -> Data {
        let bound = maurya_gzip_bound(input.count)
        guard bound > 0 else { throw ShareValidationError.invalidGzip }
        var output = Data(count: bound)
        var outputLength = bound
        let status = input.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                maurya_gzip_compress(
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress,
                    input.count,
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                    &outputLength
                )
            }
        }
        guard status == 0 else { throw ShareValidationError.invalidGzip }
        guard outputLength <= maximumOutput else { throw ShareValidationError.compressedSizeExceeded }
        output.removeSubrange(outputLength..<output.count)
        return output
    }

    static func decompress(_ bytes: Data, maximumOutput: Int) throws -> Data {
        guard bytes.count >= 18 else { throw ShareValidationError.invalidGzip }
        let source = [UInt8](bytes)
        guard source[0] == 0x1f, source[1] == 0x8b, source[2] == 8 else {
            throw ShareValidationError.invalidGzip
        }
        let flags = source[3]
        guard flags & 0xe0 == 0 else { throw ShareValidationError.invalidGzip }
        var offset = 10

        func requireAvailable(_ count: Int) throws {
            guard count >= 0, offset <= source.count - 8, count <= source.count - 8 - offset else {
                throw ShareValidationError.invalidGzip
            }
        }
        if flags & 0x04 != 0 {
            try requireAvailable(2)
            let length = Int(source[offset]) | (Int(source[offset + 1]) << 8)
            offset += 2
            try requireAvailable(length)
            offset += length
        }
        func skipZeroTerminated() throws {
            while true {
                try requireAvailable(1)
                if source[offset] == 0 { offset += 1; return }
                offset += 1
            }
        }
        if flags & 0x08 != 0 { try skipZeroTerminated() }
        if flags & 0x10 != 0 { try skipZeroTerminated() }
        if flags & 0x02 != 0 {
            try requireAvailable(2)
            offset += 2
        }

        let deflateLength = source.count - offset
        var output = Data(count: maximumOutput + 1)
        var outputLength = output.count
        var consumedLength = 0
        let status = source.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                maurya_raw_inflate(
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress?.advanced(by: offset),
                    deflateLength,
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                    &outputLength,
                    &consumedLength
                )
            }
        }
        if status == -5 || outputLength > maximumOutput {
            throw ShareValidationError.uncompressedSizeExceeded
        }
        guard status == 0 else { throw ShareValidationError.invalidGzip }
        let trailer = offset + consumedLength
        guard trailer + 8 == source.count else { throw ShareValidationError.invalidGzip }
        output.removeSubrange(outputLength..<output.count)
        let expectedCRC = littleEndian32(source, at: trailer)
        let expectedSize = littleEndian32(source, at: trailer + 4)
        let actualCRC = output.withUnsafeBytes { buffer in
            maurya_crc32(buffer.bindMemory(to: UInt8.self).baseAddress, output.count)
        }
        guard expectedCRC == actualCRC, expectedSize == UInt32(truncatingIfNeeded: output.count) else {
            throw ShareValidationError.invalidGzip
        }
        return output
    }

    private static func littleEndian32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8) | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }
}
