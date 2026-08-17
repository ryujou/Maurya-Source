import MauryaEffects
import SwiftUI

enum EffectProgramPreview {
    static func frame(
        record: EffectProgramRecord,
        document: String,
        elapsedMilliseconds: Int64 = 1_500
    ) throws -> EffectFrame {
        let original = record.program
        let draft = EffectProgram(
            id: original.id,
            nameZh: original.nameZh,
            nameJa: original.nameJa,
            workspaceJSON: original.sourceKind == .blocks ? document : original.workspaceJSON,
            astJSON: original.astJSON,
            astSHA256: original.astSHA256,
            blockCount: original.blockCount,
            estimatedDurationMilliseconds: original.estimatedDurationMilliseconds,
            createdAt: original.createdAt,
            updatedAt: original.updatedAt,
            editorSchema: original.editorSchema,
            programSchema: original.programSchema,
            sourceKind: original.sourceKind,
            scriptSource: original.sourceKind == .script ? document : original.scriptSource
        )
        let compiled = try EffectProgramCompiler.compile(draft)
        var interpreter = try EffectInterpreter(
            compiled,
            initialGroups: Array(repeating: EffectGroupState(), count: EffectGeometry.groupCount)
        )
        return try interpreter.frame(at: elapsedMilliseconds)
    }

    static func formattedScript(record: EffectProgramRecord, document: String) throws -> String {
        let original = record.program
        let draft = EffectProgram(
            id: original.id,
            nameZh: original.nameZh,
            nameJa: original.nameJa,
            workspaceJSON: original.workspaceJSON,
            createdAt: original.createdAt,
            updatedAt: original.updatedAt,
            sourceKind: .script,
            scriptSource: document
        )
        return EffectScriptFormatter.format(
            name: original.nameZh,
            compiled: try EffectProgramCompiler.compile(draft)
        )
    }
}

struct SevenGroupEffectPreview: View {
    let frame: EffectFrame

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.compact) {
            ForEach(Array(frame.groups.enumerated()), id: \.offset) { index, group in
                RoundedRectangle(cornerRadius: 8)
                    .fill(color(group))
                    .overlay {
                        Text((index + 1).formatted())
                            .font(.caption.bold())
                            .foregroundStyle(group.value > 150 ? .black : .white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .accessibilityLabel(Text("palette.group \(index + 1)"))
                    .accessibilityValue(Text("editor.preview.hsv \(group.hue) \(group.saturation) \(group.value)"))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func color(_ group: EffectGroupState) -> Color {
        Color(
            hue: Double(group.hue) / 360,
            saturation: Double(group.saturation) / 255,
            brightness: Double(group.value) / 255
        )
    }
}
