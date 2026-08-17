import MauryaEffects
import Testing

@testable import Maurya

struct EffectProgramPreviewTests {
    @Test func unsavedScriptIsCompiledAndRenderedWithoutPersisting() throws {
        let record = makeRecord(source: ##"effect "Original" { all.color("#000000"); wait(2s); }"##)

        let frame = try EffectProgramPreview.frame(
            record: record,
            document: ##"effect "Draft" { all.color("#FF0000"); wait(2s); }"##,
            elapsedMilliseconds: 100
        )

        #expect(frame.groups.count == EffectGeometry.groupCount)
        #expect(frame.groups.allSatisfy { $0.hue == 0 && $0.saturation == 255 && $0.value == 255 })
        #expect(record.program.scriptSource.contains("#000000"))
    }

    @Test func invalidDraftFailsClosedInsteadOfProducingAFrame() {
        let record = makeRecord(source: ##"effect "Original" { all.color("#000000"); wait(2s); }"##)

        #expect(throws: EffectCompileError.self) {
            try EffectProgramPreview.frame(record: record, document: "not Maurya Script")
        }
    }

    @Test func formattingCompilesBeforeReplacingEditorText() throws {
        let record = makeRecord(source: ##"effect "Original" { all.color("#000000"); wait(2s); }"##)

        let formatted = try EffectProgramPreview.formattedScript(
            record: record,
            document: ##"effect "Draft"{all.color("#FF0000");wait(2s);}"##
        )

        #expect(formatted.contains("effect \"Original\""))
        #expect(formatted.contains("wait(2s);"))
    }

    private func makeRecord(source: String) -> EffectProgramRecord {
        EffectProgramRecord(
            program: EffectProgram(
                id: "preview-test",
                nameZh: "Original",
                nameJa: "Original",
                createdAt: 0,
                updatedAt: 0,
                sourceKind: .script,
                scriptSource: source
            ),
            revision: "test"
        )
    }
}
