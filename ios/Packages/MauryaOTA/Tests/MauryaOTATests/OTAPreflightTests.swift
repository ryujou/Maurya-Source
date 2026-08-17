import Foundation
import Testing

@testable import MauryaOTA

@Suite("OTA preflight hard failures")
struct OTAPreflightTests {
    @Test("Rejects secure-version rollback")
    func rollback() async throws {
        let (base, artifact) = fixture()
        let manifest = replacing(base, secureVersion: 179, monotonicVersion: 179)
        try await expectPreflightFailure(
            .secureVersionRollback(device: 180, manifest: 179),
            manifest: manifest,
            artifact: artifact
        )
    }

    @Test("Rejects incompatible layout")
    func layout() async throws {
        let (base, artifact) = fixture()
        let manifest = replacing(base, layoutVersion: 3)
        try await expectPreflightFailure(
            .incompatibleLayout(device: 2, manifest: 3),
            manifest: manifest,
            artifact: artifact
        )
    }

    @Test("Rejects HTTPS host substitution")
    func hostSubstitution() async throws {
        let (base, artifact) = fixture()
        let manifest = replacing(
            base,
            downloadURL: URL(string: "https://attacker.example/firmware.bin")!
        )
        try await expectPreflightFailure(
            .untrustedHost("attacker.example"),
            manifest: manifest,
            artifact: artifact
        )
    }

    @Test("Equal secure version is up to date and sends no firmware")
    func upToDate() async throws {
        let (base, artifact) = fixture()
        let manifest = replacing(base, secureVersion: 180, monotonicVersion: 180)
        let transport = FakeOTADeviceTransport()
        let network = try FakeOTANetwork(manifest: manifest, artifactBytes: artifact)
        let store = MemoryCheckpointStore()

        let result = try await workflow(transport: transport, network: network, store: store)
            .run(deviceID: "current")
        #expect(result.stage == .upToDate)
        #expect(await network.artifactFetchCount() == 0)
        #expect(await transport.metrics().began == 0)
    }

    @Test("RSA verifier refuses an unconfigured key ID")
    func unknownSigningKey() throws {
        let verifier = RSASHA256ManifestVerifier(publicKeys: [:])
        #expect(throws: OTAFailure.unknownSigningKey("rotated-2027")) {
            try verifier.verify(
                message: Data("manifest".utf8),
                detachedSignature: Data("signature".utf8),
                keyID: "rotated-2027"
            )
        }
    }

    @Test("Security.framework verifies the release pipeline's RSA PKCS1v1.5 SHA-256 shape")
    func validRSASignature() throws {
        let publicKey = try #require(Data(base64Encoded: Self.publicKeyBase64))
        let signature = try #require(Data(base64Encoded: Self.signatureBase64))
        let verifier = RSASHA256ManifestVerifier(publicKeys: ["fixture-2026": publicKey])

        try verifier.verify(
            message: Data("signed manifest fixture\n".utf8),
            detachedSignature: signature,
            keyID: "fixture-2026"
        )
        #expect(throws: OTAFailure.invalidSignature) {
            try verifier.verify(
                message: Data("tampered manifest\n".utf8),
                detachedSignature: signature,
                keyID: "fixture-2026"
            )
        }
    }

    private func expectPreflightFailure(
        _ expected: OTAFailure,
        manifest: OTAManifest,
        artifact: Data
    ) async throws {
        let transport = FakeOTADeviceTransport()
        let network = try FakeOTANetwork(manifest: manifest, artifactBytes: artifact)
        let store = MemoryCheckpointStore()
        do {
            _ = try await workflow(transport: transport, network: network, store: store)
                .run(deviceID: "preflight")
            Issue.record("Expected \(expected)")
        } catch let actual as OTAFailure {
            #expect(actual == expected)
        }
        #expect(await network.artifactFetchCount() == 0)
        #expect(await transport.metrics().began == 0)
    }

    private func replacing(
        _ source: OTAManifest,
        layoutVersion: UInt8? = nil,
        secureVersion: UInt32? = nil,
        monotonicVersion: UInt32? = nil,
        downloadURL: URL? = nil
    ) -> OTAManifest {
        OTAManifest(
            schema: source.schema,
            variant: source.variant,
            layoutVersion: layoutVersion ?? source.layoutVersion,
            assetPackVersion: source.assetPackVersion,
            versionName: source.versionName,
            monotonicVersion: monotonicVersion ?? source.monotonicVersion,
            secureVersion: secureVersion ?? source.secureVersion,
            size: source.size,
            sha256: source.sha256,
            downloadURL: downloadURL ?? source.downloadURL,
            minimumAppVersion: source.minimumAppVersion,
            publishedAt: source.publishedAt
        )
    }

    private static let publicKeyBase64 =
        "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwLLP2AH4LuEP5YgeyoaWmGue+wJl+HLfjTTLQ2pbn0fMx2/7MfLY/Lsde9KTA3+Lz3hgDvZKqPREuovBHc1BLvQ0iNczrCdG+Q3F/74A5A475ClABwzTnVjfBlLNVHH4YnpIdxe+hYQ8BW0zxBhdG2x+zgB7mynh3+XOrwKCdnMzfR65mW1RKlV7Jqs9ZTQXu5muk/txaSyEDcCW0ZsLdpIN79IHBMenWwATq+mlssjyNYpSi1sfmv1p+A6HU5wnuruGLVaEAfQGNHM8g+JcwGVp605ewMkBKVjihEoZ/ZaMQ0KXYPZHPyTrtC4znG2lPjipOShGyr5PctWOkj0ejwIDAQAB"
    private static let signatureBase64 =
        "F7G6UlMmxh0n3AmEm29jhY/MlQ99u7SIPU/WL0cMNT5oRT0FtTiBqeTkAKjmt6JwsdrPUC53L7Kw4VTTWnrNKDypeDfjnZg1DmVwMdlLnjjDFZ4We8S1X3AlKUUgRZtpdPjb8b2WTI8QF/AaBP0HeikYYPhb85SQL5FBG7mEisyT7i6REHS1C1cVWWdhir0HrQjjUme4cat9uc5IJvq6EogS6QqFjLVYcheH5pRLVBoGPyRA8d2QbiU2Suox/VqqQHteZHYJ1nYE8xop6SzwgqpqETA5uObxVpKEQdbABO59wl1B574Rh3hBWvg+hrvqC2ZOnOiY8CVb3EC7rNzatw=="
}
