import CoreGraphics
import Darwin
import Foundation
import MauryaResources
import Testing

@Suite("Host resource measurements", .serialized)
struct ResourceMeasurementTests {
    @Test func inventoryLoadAndRepresentativeWebPDecode() throws {
        let initialResidentBytes = try residentBytes()
        let inventoryStart = ContinuousClock.now
        let library = try BuiltinPaletteLibrary.load()
        let inventoryElapsed = inventoryStart.duration(to: .now)
        let inventoryResidentBytes = try residentBytes()

        #expect(library.inventory.entries.count == 560)

        let image = try makeGradient(width: 240, height: 160)
        let webP = try AvatarImageProcessor.encodeWebP(AvatarImageProcessor.centerCrop(image))
        let decodeResidentStart = try residentBytes()
        var samples: [Duration] = []
        for _ in 0..<10 {
            let start = ContinuousClock.now
            let colors = try AvatarImageProcessor.candidateColors(webP)
            samples.append(start.duration(to: .now))
            #expect(colors.isEmpty == false)
        }
        let decodeResidentEnd = try residentBytes()
        let sortedSamples = samples.sorted()
        let medianDecode = sortedSamples[sortedSamples.count / 2]

        print("MAURYA_RESOURCE_MEASUREMENT host=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("MAURYA_RESOURCE_MEASUREMENT inventory_entries=\(library.inventory.entries.count)")
        print("MAURYA_RESOURCE_MEASUREMENT inventory_first_load_ms=\(milliseconds(inventoryElapsed))")
        print(
            "MAURYA_RESOURCE_MEASUREMENT inventory_resident_delta_bytes="
                + "\(nonnegativeDelta(inventoryResidentBytes, initialResidentBytes))"
        )
        print("MAURYA_RESOURCE_MEASUREMENT representative_webp_bytes=\(webP.count)")
        print("MAURYA_RESOURCE_MEASUREMENT decode_crop_colors_iterations=\(samples.count)")
        print("MAURYA_RESOURCE_MEASUREMENT decode_crop_colors_median_ms=\(milliseconds(medianDecode))")
        print(
            "MAURYA_RESOURCE_MEASUREMENT decode_resident_delta_bytes="
                + "\(nonnegativeDelta(decodeResidentEnd, decodeResidentStart))"
        )
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

    private func residentBytes() throws -> UInt64 {
        var information = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { throw MeasurementError.taskInfo(result) }
        return UInt64(information.resident_size)
    }

    private func nonnegativeDelta(_ final: UInt64, _ initial: UInt64) -> UInt64 {
        final >= initial ? final - initial : 0
    }

    private func milliseconds(_ duration: Duration) -> String {
        let components = duration.components
        let value =
            Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.3f", value)
    }
}

private enum MeasurementError: Error {
    case taskInfo(kern_return_t)
}
