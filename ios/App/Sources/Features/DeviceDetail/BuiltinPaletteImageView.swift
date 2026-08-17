import MauryaResources
import SwiftUI

struct BuiltinPaletteImageView: View {
    let entry: ResourceInventoryEntry?
    let fallbackText: String
    let size: CGFloat
    var isLogo = false

    var body: some View {
        Group {
            if let entry,
                let url = try? BuiltinPaletteLibrary.resourceURL(for: entry),
                let image = UIImage(contentsOfFile: url.path)
            {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: isLogo ? .fit : .fill)
            } else {
                ZStack {
                    Color(hex: entry?.hex ?? "#293253")
                    Text(fallbackText.prefix(2))
                        .bold()
                        .foregroundStyle(DesignTokens.Color.onSurface)
                }
            }
        }
        .frame(width: isLogo ? nil : size, height: size)
        .frame(maxWidth: isLogo ? .infinity : nil)
        .background(DesignTokens.Color.logoBackground)
        .clipShape(isLogo ? AnyShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card)) : AnyShape(Circle()))
        .accessibilityHidden(true)
    }
}

private extension Color {
    init(hex: String) {
        guard hex.count == 7, let value = UInt64(hex.dropFirst(), radix: 16) else {
            self = .clear
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
