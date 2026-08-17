import MauryaResources
import SwiftUI

struct PaletteFranchiseSelectorView: View {
    let franchises: [PaletteFranchise]
    let locale: PaletteLocale
    @Binding var selection: String
    let showCustom: Bool

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.compact) {
            ForEach(franchises) { franchise in
                franchiseButton(
                    id: franchise.id,
                    title: franchise.displayLabel(locale: locale)
                )
            }
            if showCustom {
                franchiseButton(id: "custom", title: String(localized: "resources.custom"))
            }
        }
    }

    private func franchiseButton(id: String, title: String) -> some View {
        Button {
            selection = id
        } label: {
            Text(title)
                .bold()
                .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget)
                .foregroundStyle(selection == id ? DesignTokens.Color.onPrimary : DesignTokens.Color.onSurface)
                .background(selection == id ? DesignTokens.Color.primary : DesignTokens.Color.surfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                        .stroke(DesignTokens.Color.outline, lineWidth: selection == id ? 0 : 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("palette-franchise-\(id)")
        .accessibilityAddTraits(selection == id ? .isSelected : [])
    }
}
