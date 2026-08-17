import MauryaEffects
import MauryaShare
import SwiftUI
import UIKit

struct SharePayloadPreview: View {
    let envelope: ShareEnvelope

    var body: some View {
        switch envelope.payload {
        case let .palette(payload):
            HStack(spacing: DesignTokens.Spacing.standard) {
                if let image = UIImage(data: payload.avatarWebP) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                        .accessibilityLabel("share.preview.avatar")
                }
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: payload.hex) ?? .clear)
                    .frame(width: 72, height: 72)
                    .overlay(Text(payload.hex).font(.caption.monospaced()).padding(4))
                    .accessibilityLabel(Text("share.preview.color"))
                    .accessibilityValue(payload.hex)
            }
        case let .effect(payload):
            if let frame = try? effectFrame(payload) {
                SevenGroupEffectPreview(frame: frame)
            } else {
                ContentUnavailableView(
                    "share.preview.effect.unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("share.preview.effect.unavailable.message")
                )
            }
        }
    }

    private func effectFrame(_ payload: EffectSharePayload) throws -> EffectFrame {
        let sourceKind: MauryaEffects.EffectSourceKind = payload.sourceKind == .blocks ? .blocks : .script
        let program = EffectProgram(
            id: "share-preview",
            nameZh: envelope.displayName.zh,
            nameJa: envelope.displayName.ja,
            workspaceJSON: sourceKind == .blocks ? payload.source : "",
            createdAt: 0,
            updatedAt: 0,
            editorSchema: payload.editorSchema,
            programSchema: payload.programSchema,
            sourceKind: sourceKind,
            scriptSource: sourceKind == .script ? payload.source : ""
        )
        let compiled = try EffectProgramCompiler.compile(program)
        var interpreter = try EffectInterpreter(
            compiled,
            initialGroups: Array(repeating: EffectGroupState(), count: EffectGeometry.groupCount)
        )
        return try interpreter.frame(at: 1_500)
    }
}

private extension Color {
    init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >> 8) & 0xff) / 255,
            blue: Double(rgb & 0xff) / 255
        )
    }
}
