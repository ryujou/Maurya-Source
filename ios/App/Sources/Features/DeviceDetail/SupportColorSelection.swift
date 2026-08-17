import MauryaResources
import SwiftUI

struct SupportColorSelection: Equatable, Sendable {
    let entry: ResourceInventoryEntry?
    let nameZh: String
    let nameJa: String
    let hex: String
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let hue: UInt16
    let saturation: UInt16
    let value: UInt16

    init?(entry: ResourceInventoryEntry) {
        let text = entry.hex.dropFirst()
        guard text.count == 6, let rgb = UInt32(text, radix: 16) else { return nil }
        self.entry = entry
        red = UInt8((rgb >> 16) & 0xFF)
        green = UInt8((rgb >> 8) & 0xFF)
        blue = UInt8(rgb & 0xFF)

        guard let hsv = Self.deviceHSV(hex: entry.hex) else { return nil }
        nameZh = entry.nameZh
        nameJa = entry.nameJa
        hex = entry.hex
        hue = hsv.hue
        saturation = hsv.saturation
        value = hsv.value
    }

    init?(custom: CustomPaletteEntry) {
        entry = nil
        nameZh = custom.names.zh
        nameJa = custom.names.ja
        hex = custom.color.rawValue
        let text = hex.dropFirst()
        guard text.count == 6, let rgb = UInt32(text, radix: 16),
            let hsv = Self.deviceHSV(hex: hex)
        else { return nil }
        red = UInt8((rgb >> 16) & 0xFF)
        green = UInt8((rgb >> 8) & 0xFF)
        blue = UInt8(rgb & 0xFF)
        hue = hsv.hue
        saturation = hsv.saturation
        value = hsv.value
    }

    static func deviceHSV(hex: String) -> (hue: UInt16, saturation: UInt16, value: UInt16)? {
        let text = hex.dropFirst()
        guard text.count == 6, let rgb = UInt32(text, radix: 16) else { return nil }
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        let maximum = max(r, g, b)
        let minimum = min(r, g, b)
        let delta = maximum - minimum
        let computedHue: Double
        if delta == 0 {
            computedHue = 0
        } else if maximum == r {
            computedHue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == g {
            computedHue = 60 * (((b - r) / delta) + 2)
        } else {
            computedHue = 60 * (((r - g) / delta) + 4)
        }
        return (
            UInt16((computedHue < 0 ? computedHue + 360 : computedHue).rounded()) % 360,
            UInt16((maximum == 0 ? 0 : delta / maximum * 255).rounded()),
            UInt16((maximum * 255).rounded())
        )
    }

    var color: Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}
