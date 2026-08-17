import MauryaResources
import SwiftUI

struct ResourceRow: View {
    @Environment(\.mauryaDifferentiateWithoutColor) private var differentiateWithoutColor
    let entry: ResourceInventoryEntry

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.compact) {
                identity
                Spacer(minLength: DesignTokens.Spacing.compact)
                metadata(alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                identity
                metadata(alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, DesignTokens.Spacing.compact)
        .accessibilityElement(children: .combine)
        .accessibilityValue(entry.hex)
    }

    private var identity: some View {
        Label {
            VStack(alignment: .leading) {
                Text(entry.nameZh)
                Text(entry.nameJa).foregroundStyle(.secondary)
            }
        } icon: {
            avatar
        }
    }

    private func metadata(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment) {
            Text(entry.hex).font(.footnote.monospaced())
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = try? BuiltinPaletteLibrary.resourceURL(for: entry),
            let image = UIImage(contentsOfFile: url.path)
        {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay {
                    if differentiateWithoutColor {
                        Circle().stroke(.primary, lineWidth: 2)
                    }
                }
                .accessibilityHidden(true)
        } else {
            Circle().fill(color).frame(width: 52, height: 52)
                .overlay {
                    Text(entry.nameZh.prefix(1))
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                }
        }
    }

    private var color: Color {
        let raw = entry.hex.dropFirst()
        guard let value = UInt64(raw, radix: 16) else { return .clear }
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
