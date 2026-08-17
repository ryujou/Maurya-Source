import Foundation

public enum ShareModerationResult: Sendable, Equatable {
    case accepted
    case rejected
}

public enum ShareModeration {
    private static let words = [
        "六四事件", "天安门事件", "八九民运", "文化大革命", "反革命",
        "推翻共产党", "打倒共产党", "共产党下台", "中国共产党下台",
        "习近平下台", "习包子", "毛腊肉", "法轮功", "藏独", "疆独", "台独建国",
        "民主中国阵线", "中国民主党", "新唐人电视台", "大纪元时报",
    ].map(normalize)

    public static func check(_ envelope: ShareEnvelope) -> ShareModerationResult {
        var text = envelope.displayName.zh + "\n" + envelope.displayName.ja
        if case let .effect(payload) = envelope.payload { text += "\n" + payload.source }
        let normalized = normalize(text)
        let compact = String(
            normalized.unicodeScalars.filter { scalar in
                CharacterSet.whitespacesAndNewlines.contains(scalar) == false
                    && CharacterSet.punctuationCharacters.contains(scalar) == false && CharacterSet.symbols.contains(scalar) == false
                    && scalar != "_"
            })
        return words.contains(where: { normalized.contains($0) || compact.contains($0) }) ? .rejected : .accepted
    }

    private static func normalize(_ value: String) -> String {
        let normalized = value.precomposedStringWithCompatibilityMapping.lowercased(with: Locale(identifier: "en_US_POSIX"))
        return String(
            normalized.unicodeScalars.filter { scalar in
                let code = scalar.value
                let zeroWidth =
                    (0x200B...0x200F).contains(code) || code == 0x2060 || (0xFE00...0xFE0F).contains(code) || code == 0xFEFF
                    || (0xE0100...0xE01EF).contains(code)
                return !zeroWidth && CharacterSet.controlCharacters.contains(scalar) == false
            })
    }
}
