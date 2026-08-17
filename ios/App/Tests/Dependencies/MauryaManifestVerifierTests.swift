import CryptoKit
import Foundation
import MauryaOTA
import Testing

@testable import Maurya

struct MauryaManifestVerifierTests {
    @Test func published180ReleaseNotesCorrectionKeepsSecurityFieldsSigned() throws {
        let verifier = MauryaManifestVerifier(
            strictVerifier: ExactDigestVerifier(expectedHex: Self.legacyMultilingualDigest)
        )

        try verifier.verify(
            message: Data(Self.correctedMultilingualManifest.utf8),
            detachedSignature: Data(),
            keyID: "production-1"
        )
    }

    @Test func compatibilityDoesNotPermitArtifactHashChanges() {
        let verifier = MauryaManifestVerifier(
            strictVerifier: ExactDigestVerifier(expectedHex: Self.legacyMultilingualDigest)
        )
        let tampered = Self.correctedMultilingualManifest.replacingOccurrences(
            of: "812957a8889d54b2c7678d5bef1e48c240563684759119eddcca3ec68b2e05b2",
            with: "912957a8889d54b2c7678d5bef1e48c240563684759119eddcca3ec68b2e05b2"
        )

        #expect(throws: OTAFailure.invalidSignature) {
            try verifier.verify(
                message: Data(tampered.utf8),
                detachedSignature: Data(),
                keyID: "production-1"
            )
        }
    }

    @Test func compatibilityIsRestrictedToPublished180Targets() {
        let verifier = MauryaManifestVerifier(
            strictVerifier: ExactDigestVerifier(expectedHex: Self.legacyMultilingualDigest)
        )
        let unrelated = Self.correctedMultilingualManifest.replacingOccurrences(
            of: "\"versionName\":\"1.8.0\"",
            with: "\"versionName\":\"1.9.0\""
        )

        #expect(throws: OTAFailure.invalidSignature) {
            try verifier.verify(
                message: Data(unrelated.utf8),
                detachedSignature: Data(),
                keyID: "production-1"
            )
        }
    }

    private struct ExactDigestVerifier: OTASignatureVerifying {
        let expectedHex: String

        func verify(message: Data, detachedSignature: Data, keyID: String) throws {
            let actual = SHA256.hash(data: message).map { String(format: "%02x", $0) }.joined()
            guard actual == expectedHex else { throw OTAFailure.invalidSignature }
        }
    }

    private static let legacyMultilingualDigest =
        "c12b7dd9022da5ba9da911cd9ed19303e17ac0802b7369aedc922a868be9102e"

    private static let correctedMultilingualManifest =
        #"{"assetPackVersion":1,"downloadUrl":"https://xtbang.top/maurya/ota/stable/multilingual/maurya-1.8.0.bin","layoutVersion":2,"minimumAppVersion":313,"monotonicVersion":180,"publishedAt":"2026-07-30T12:58:25+00:00","releaseNotesJa":"7組各6個のLEDを個別制御するRAMエフェクトを追加しました。従来の7グループ制御、応援カラー、設定保存は変更ありません。","releaseNotesZh":"新增7组×6颗灯珠的独立RAM灯效控制；原有7组灯效、应援色和配置保存流程保持不变。","schema":1,"secureVersion":180,"sha256":"812957a8889d54b2c7678d5bef1e48c240563684759119eddcca3ec68b2e05b2","size":987136,"variant":"multilingual","versionName":"1.8.0"}"#
}
