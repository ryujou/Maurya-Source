import SwiftUI

struct SupportColorPreview: View {
    @Environment(\.mauryaDifferentiateWithoutColor) private var differentiateWithoutColor
    let selection: SupportColorSelection

    var body: some View {
        LabeledContent {
            Text(selection.hex)
                .font(.body.monospaced())
        } label: {
            Label {
                VStack(alignment: .leading) {
                    Text(selection.nameZh)
                    Text(selection.nameJa).foregroundStyle(.secondary)
                }
            } icon: {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                    .fill(selection.color)
                    .frame(width: 44, height: 44)
                    .overlay {
                        if differentiateWithoutColor {
                            Image(systemName: "circle.hexagongrid.fill")
                                .foregroundStyle(.primary)
                                .accessibilityHidden(true)
                        }
                    }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(selection.hex)
    }
}
