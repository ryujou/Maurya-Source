import MauryaResources
import SwiftUI

struct PaletteGroupCardView: View {
    let group: PaletteGroup
    let entry: ResourceInventoryEntry?
    let locale: PaletteLocale
    let isSelected: Bool
    let open: () -> Void
    let selectColor: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if group.imageKind == "logo" {
                Button(action: selectColor) {
                    BuiltinPaletteImageView(
                        entry: entry,
                        fallbackText: group.displayName(locale: locale),
                        size: 112,
                        isLogo: true
                    )
                    .frame(height: 112)
                    .padding(DesignTokens.Spacing.compact)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(group.displayName(locale: locale))
                .accessibilityHint("palette.select.hint")
                .accessibilityIdentifier("palette-group-logo-color-\(group.id)")
            }
            HStack(spacing: DesignTokens.Spacing.standard) {
                if group.imageKind != "logo" {
                    Button(action: selectColor) {
                        BuiltinPaletteImageView(
                            entry: entry,
                            fallbackText: group.displayName(locale: locale),
                            size: 64
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(group.displayName(locale: locale))
                    .accessibilityHint("palette.select.hint")
                    .accessibilityIdentifier("palette-group-avatar-color-\(group.id)")
                }
                Button(action: open) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.displayName(locale: locale))
                            .font(.headline)
                            .foregroundStyle(isSelected ? DesignTokens.Color.primary : DesignTokens.Color.onSurface)
                        if group.seriesLabelZh.isEmpty == false {
                            Text(locale == .japanese ? group.seriesLabelJa : group.seriesLabelZh)
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.Color.onSurfaceVariant)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("palette-group-\(group.id)")

                Button(action: selectColor) {
                    Circle()
                        .fill(groupColor)
                        .frame(width: 38, height: 38)
                        .overlay(Circle().stroke(DesignTokens.Color.onSurface, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("palette.select.hint")
                .accessibilityIdentifier("palette-group-swatch-\(group.id)")
            }
            .padding(DesignTokens.Spacing.standard)
        }
        .background(DesignTokens.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(isSelected ? DesignTokens.Color.primary : DesignTokens.Color.outline, lineWidth: isSelected ? 2 : 1)
        }
    }

    private var groupColor: Color {
        guard group.hex.count == 7, let value = UInt64(group.hex.dropFirst(), radix: 16) else {
            return .clear
        }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
