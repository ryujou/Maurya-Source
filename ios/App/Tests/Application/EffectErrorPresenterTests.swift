import MauryaAnalysis
import MauryaEffects
import MauryaPlayback
import Testing

@testable import Maurya

struct EffectErrorPresenterTests {
    @Test
    func compileDiagnosticsSelectExactlyOneRequestedLanguage() {
        let error = EffectCompileError(issues: [
            EffectCompileIssue(
                code: "TEST_DIAGNOSTIC",
                messageZh: "中文诊断",
                messageJa: "日本語診断"
            )
        ])

        let chinese = EffectErrorPresenter.message(for: error, language: .simplifiedChinese)
        let japanese = EffectErrorPresenter.message(for: error, language: .japanese)
        let english = EffectErrorPresenter.message(for: error, language: .english)

        #expect(chinese == "中文诊断")
        #expect(japanese == "日本語診断")
        #expect(english.contains("TEST_DIAGNOSTIC"))
        #expect(chinese.contains("日本語") == false)
        #expect(japanese.contains("中文") == false)
        #expect(english.contains("中文") == false)
        #expect(english.contains("日本語") == false)
    }

    @Test
    func typedProgramErrorsRemainSingleLanguageAndExposeStableCode() {
        let error = EffectProgramError.invalidJSON

        let chinese = EffectErrorPresenter.message(for: error, language: .simplifiedChinese)
        let japanese = EffectErrorPresenter.message(for: error, language: .japanese)
        let english = EffectErrorPresenter.message(for: error, language: .english)

        #expect(chinese.contains("灯效操作失败"))
        #expect(japanese.contains("エフェクト操作に失敗"))
        #expect(english.contains("effect operation failed"))
        #expect([chinese, japanese, english].allSatisfy { $0.contains(error.code) })
        #expect([chinese, japanese, english].allSatisfy { $0.contains(" / ") == false })
    }

    @Test
    func everyAudioInputErrorHasSingleLanguageCauseAndNextStep() {
        let errors: [AudioInputError] = [.permissionDenied, .noInputRoute, .invalidInputFormat]

        for error in errors {
            let english = EffectErrorPresenter.message(for: error, language: .english)
            let chinese = EffectErrorPresenter.message(for: error, language: .simplifiedChinese)
            let japanese = EffectErrorPresenter.message(for: error, language: .japanese)

            #expect(english.contains(".") && english.count > 45)
            #expect(chinese.contains("。") && chinese.count > 20)
            #expect(japanese.contains("。") && japanese.count > 25)
            #expect([english, chinese, japanese].allSatisfy { $0.contains(" / ") == false })
            #expect(Set([english, chinese, japanese]).count == 3)
        }
    }

    @Test
    func everyPlaybackErrorHasSingleLanguageCauseAndNextStep() {
        let errors: [PlaybackError] = [
            .alreadyActive,
            .volatileEffectsUnsupported,
            .pixelEffectsUnsupported,
            .incompatibleGeometry(expectedGroups: 7, expectedPixels: 0, actualGroups: 6, actualPixels: 0),
            .acknowledgementSequenceMismatch(expected: 1, actual: 2),
            .disconnected,
            .staleRequiredInputs([.audioLevel]),
        ]

        for error in errors {
            let english = EffectErrorPresenter.message(for: error, language: .english)
            let chinese = EffectErrorPresenter.message(for: error, language: .simplifiedChinese)
            let japanese = EffectErrorPresenter.message(for: error, language: .japanese)

            #expect(english.contains(".") && english.count > 45)
            #expect(chinese.contains("。") && chinese.count > 20)
            #expect(japanese.contains("。") && japanese.count > 25)
            #expect([english, chinese, japanese].allSatisfy { $0.contains(" / ") == false })
            #expect(Set([english, chinese, japanese]).count == 3)
        }
    }
}
