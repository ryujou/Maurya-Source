import SwiftUI

struct MauryaElevatedCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(DesignTokens.Spacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                    .stroke(DesignTokens.Color.outline.opacity(0.45), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
    }
}
