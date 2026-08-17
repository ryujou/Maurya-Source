import Foundation
import MauryaOTA

/// Verifies current release manifests strictly and contains one narrow
/// compatibility path for the already-published 1.8.0 manifests. The server's
/// 1.8.0 release notes were corrected after signing, while every security-
/// sensitive field and the detached signature remained unchanged. The fallback
/// reconstructs that exact signed message and therefore does not weaken the
/// signature covering the artifact URL, hash, size, variant, layout, or secure
/// version.
struct MauryaManifestVerifier: OTASignatureVerifying {
    private let strictVerifier: any OTASignatureVerifying

    init(publicKeys: [String: Data]) {
        strictVerifier = RSASHA256ManifestVerifier(publicKeys: publicKeys)
    }

    init(strictVerifier: any OTASignatureVerifying) {
        self.strictVerifier = strictVerifier
    }

    func verify(message: Data, detachedSignature: Data, keyID: String) throws {
        do {
            try strictVerifier.verify(
                message: message,
                detachedSignature: detachedSignature,
                keyID: keyID
            )
        } catch OTAFailure.invalidSignature {
            guard let legacyMessage = Self.legacy180SignedMessage(for: message) else {
                throw OTAFailure.invalidSignature
            }
            try strictVerifier.verify(
                message: legacyMessage,
                detachedSignature: detachedSignature,
                keyID: keyID
            )
        }
    }

    static func legacy180SignedMessage(for message: Data) -> Data? {
        guard
            let object = try? JSONSerialization.jsonObject(with: message),
            var manifest = object as? [String: Any],
            (manifest["schema"] as? NSNumber)?.intValue == 1,
            (manifest["secureVersion"] as? NSNumber)?.intValue == 180,
            (manifest["monotonicVersion"] as? NSNumber)?.intValue == 180,
            let variant = manifest["variant"] as? String,
            let version = manifest["versionName"] as? String,
            Self.isKnown180Target(variant: variant, version: version),
            let chinese = manifest["releaseNotesZh"] as? String,
            let japanese = manifest["releaseNotesJa"] as? String,
            Self.isCorrectedReleaseNotePair(chinese: chinese, japanese: japanese)
        else { return nil }

        manifest["releaseNotesZh"] = Self.legacyChineseReleaseNotes
        manifest["releaseNotesJa"] = Self.legacyJapaneseReleaseNotes
        guard
            var canonical = try? JSONSerialization.data(
                withJSONObject: manifest,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
        else { return nil }
        canonical.append(0x0A)
        return canonical
    }

    private static func isKnown180Target(variant: String, version: String) -> Bool {
        (variant == "multilingual" && version == "1.8.0")
            || (variant == "ja" && version == "1.8.0-jp")
    }

    private static func isCorrectedReleaseNotePair(chinese: String, japanese: String) -> Bool {
        let sevenBySix =
            chinese == "新增7组×6颗灯珠的独立RAM灯效控制；原有7组灯效、应援色和配置保存流程保持不变。"
            && japanese == "7組各6個のLEDを個別制御するRAMエフェクトを追加しました。従来の7グループ制御、応援カラー、設定保存は変更ありません。"
        let fortyTwo =
            chinese == "新增42颗灯珠独立RAM灯效控制；原有7组灯效、应援色和配置保存流程保持不变。"
            && japanese == "42個のLEDを個別制御するRAMエフェクトを追加しました。従来の7グループ制御、応援カラー、設定保存は変更ありません。"
        return sevenBySix || fortyTwo
    }

    private static let legacyChineseReleaseNotes =
        "新增70颗灯珠独立RAM灯效控制；原有7组灯效、应援色和配置保存流程保持不变。"
    private static let legacyJapaneseReleaseNotes =
        "70個のLEDを個別制御するRAMエフェクトを追加しました。従来の7グループ制御、応援カラー、設定保存は変更ありません。"
}
