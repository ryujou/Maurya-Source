import SwiftUI

private struct MauryaDifferentiateWithoutColorKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var mauryaDifferentiateWithoutColor: Bool {
        get { self[MauryaDifferentiateWithoutColorKey.self] }
        set { self[MauryaDifferentiateWithoutColorKey.self] = newValue }
    }
}

enum DesignTokens {
    enum Color {
        // Mirrors the Android Material theme so both apps read as the same product.
        static let background = SwiftUI.Color(red: 7 / 255, green: 9 / 255, blue: 18 / 255)
        static let surface = SwiftUI.Color(red: 16 / 255, green: 19 / 255, blue: 30 / 255)
        static let surfaceHigh = SwiftUI.Color(red: 23 / 255, green: 27 / 255, blue: 41 / 255)
        static let elevatedSurface = surfaceHigh
        static let primary = SwiftUI.Color(red: 184 / 255, green: 197 / 255, blue: 255 / 255)
        static let primaryContainer = SwiftUI.Color(red: 41 / 255, green: 50 / 255, blue: 83 / 255)
        static let onPrimary = background
        static let accent = primary
        static let secondary = SwiftUI.Color(red: 200 / 255, green: 170 / 255, blue: 112 / 255)
        static let success = SwiftUI.Color(red: 124 / 255, green: 230 / 255, blue: 174 / 255)
        static let warning = secondary
        static let failure = SwiftUI.Color(red: 1, green: 111 / 255, blue: 111 / 255)
        static let onSurface = SwiftUI.Color(red: 241 / 255, green: 243 / 255, blue: 250 / 255)
        static let onSurfaceVariant = SwiftUI.Color(red: 190 / 255, green: 196 / 255, blue: 216 / 255)
        static let outline = SwiftUI.Color(red: 58 / 255, green: 64 / 255, blue: 84 / 255)
        static let logoBackground = SwiftUI.Color(red: 246 / 255, green: 247 / 255, blue: 251 / 255)
    }

    enum Spacing {
        static let compact = 8.0
        static let standard = 16.0
        static let roomy = 24.0
    }

    enum Radius {
        static let card = 16.0
        static let control = 12.0
    }

    enum Size {
        static let minimumHitTarget = 44.0
    }

    enum Icon {
        static let scan = "antenna.radiowaves.left.and.right"
        static let device = "lightbulb.led.wide"
        static let share = "square.and.arrow.down"
        static let unavailable = "wrench.and.screwdriver"
    }
}
