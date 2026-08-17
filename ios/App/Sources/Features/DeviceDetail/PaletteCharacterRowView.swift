import MauryaResources
import SwiftUI

struct PaletteCharacterRowView: View {
    let character: PaletteCharacter
    let entry: ResourceInventoryEntry?
    let locale: PaletteLocale
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: DesignTokens.Spacing.standard) {
                BuiltinPaletteImageView(
                    entry: entry,
                    fallbackText: character.displayName(locale: locale),
                    size: 72
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(character.displayName(locale: locale))
                        .font(.headline)
                        .foregroundStyle(DesignTokens.Color.onSurface)
                    Text(character.hex)
                        .font(.footnote.monospaced())
                        .foregroundStyle(DesignTokens.Color.onSurfaceVariant)
                }
                Spacer()
                Circle()
                    .fill(selection?.color ?? .clear)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(DesignTokens.Color.onSurface, lineWidth: 1))
            }
            .padding(DesignTokens.Spacing.standard)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(DesignTokens.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("palette-character-\(character.id)")
        .accessibilityHint("palette.select.hint")
    }

    private var selection: SupportColorSelection? {
        entry.flatMap(SupportColorSelection.init(entry:))
    }
}
