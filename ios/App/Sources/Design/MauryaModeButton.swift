import SwiftUI

struct MauryaModeButton: View {
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .bold()
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.minimumHitTarget)
                .foregroundStyle(isSelected ? DesignTokens.Color.onPrimary : DesignTokens.Color.onSurface)
                .background(isSelected ? DesignTokens.Color.primary : DesignTokens.Color.surfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                        .stroke(DesignTokens.Color.outline, lineWidth: isSelected ? 0 : 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
