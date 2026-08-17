import Foundation
import MauryaAnalysis
import MauryaEffects
import MauryaPlayback

enum EffectPresentationLanguage: Sendable {
    case english
    case simplifiedChinese
    case japanese

    init(locale: Locale) {
        switch locale.language.languageCode {
        case .chinese:
            self = .simplifiedChinese
        case .japanese:
            self = .japanese
        default:
            self = .english
        }
    }

    var localizationIdentifier: String {
        switch self {
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        case .japanese: "ja"
        }
    }
}

enum EffectErrorPresenter {
    static func message(
        for error: any Error,
        language: EffectPresentationLanguage
    ) -> String {
        if let audioError = error as? AudioInputError {
            let key: String
            let fallback: String
            switch audioError {
            case .permissionDenied:
                key = "effects.error.audio.permission-denied"
                fallback = "Microphone access was denied. Allow microphone access in Settings, then try again."
            case .noInputRoute:
                key = "effects.error.audio.no-input-route"
                fallback = "No audio input is available. Connect or select a microphone, then try again."
            case .invalidInputFormat:
                key = "effects.error.audio.invalid-format"
                fallback = "The microphone format is unsupported. Change the audio route, then try again."
            }
            return localized(key, fallback: fallback, language: language)
        }

        if let playbackError = error as? PlaybackError {
            let key: String
            let fallback: String
            switch playbackError {
            case .alreadyActive:
                key = "effects.error.playback.already-active"
                fallback = "Another effect session is active. Stop it before starting this effect."
            case .volatileEffectsUnsupported:
                key = "effects.error.playback.volatile-unsupported"
                fallback = "The connected firmware does not support temporary effects. Update the device or use manual controls."
            case .pixelEffectsUnsupported:
                key = "effects.error.playback.pixel-unsupported"
                fallback = "The connected firmware does not support pixel effects. Choose a group effect or update the device."
            case .incompatibleGeometry:
                key = "effects.error.playback.geometry"
                fallback = "The effect geometry does not match the connected device. Reconnect and choose a compatible effect."
            case .acknowledgementSequenceMismatch:
                key = "effects.error.playback.sequence"
                fallback = "The device response was out of sequence. Stop, reconnect, and try again."
            case .disconnected:
                key = "effects.error.playback.disconnected"
                fallback = "The device disconnected during playback. Reconnect before trying again."
            case .staleRequiredInputs:
                key = "effects.error.playback.stale-inputs"
                fallback = "Required sensor or audio input is stale. Restore permission or input availability, then restart playback."
            }
            return localized(key, fallback: fallback, language: language)
        }

        if let compileError = error as? EffectCompileError,
            let issue = compileError.issues.first
        {
            switch language {
            case .simplifiedChinese:
                return issue.message(for: .simplifiedChinese)
            case .japanese:
                return issue.message(for: .japanese)
            case .english:
                return localized(
                    "effects.error.compile.generic",
                    fallback: "The effect could not be compiled. Review the highlighted source and try again.",
                    language: language
                ) + " [\(issue.code)]"
            }
        }

        if let programError = error as? EffectProgramError {
            return localized(
                "effects.error.program.generic",
                fallback: "The effect operation failed. Review the file or program and try again.",
                language: language
            ) + " [\(programError.code)]"
        }

        if let executionError = error as? EffectAsyncExecutionError {
            return localized(
                "effects.error.execution.generic",
                fallback: "Effect processing stopped before it completed. Try again.",
                language: language
            ) + " [\(executionError.code)]"
        }

        if error is EffectRuntimeError {
            return localized(
                "effects.error.runtime.generic",
                fallback: "The effect stopped because its runtime input or operation was invalid.",
                language: language
            )
        }

        if let localizedError = error as? LocalizedError,
            let description = localizedError.errorDescription
        {
            return description
        }
        return String(describing: error)
    }

    private static func localized(
        _ key: String,
        fallback: String,
        language: EffectPresentationLanguage
    ) -> String {
        let localizedBundle = Bundle.main.path(
            forResource: language.localizationIdentifier,
            ofType: "lproj"
        ).flatMap(Bundle.init(path:))
        return (localizedBundle ?? .main).localizedString(
            forKey: key,
            value: fallback,
            table: nil
        )
    }
}
