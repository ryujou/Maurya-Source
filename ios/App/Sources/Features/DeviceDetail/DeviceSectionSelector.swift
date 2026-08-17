import SwiftUI

struct DeviceSectionSelector: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var selection: DeviceSection

    var body: some View {
        LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.compact) {
            ForEach(DeviceSection.allCases) { section in
                MauryaModeButton(
                    title: String(localized: String.LocalizationValue(section.titleKey)),
                    isSelected: selection == section,
                    isEnabled: true,
                    action: { selection = section }
                )
                .accessibilityIdentifier("device-section-\(section.rawValue)")
            }
        }
        .accessibilityIdentifier("device-section-picker")
    }

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.compact), count: count)
    }
}
