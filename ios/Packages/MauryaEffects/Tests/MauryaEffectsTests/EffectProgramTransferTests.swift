import Foundation
import Testing

@testable import MauryaEffects

struct EffectProgramTransferTests {
    @Test func androidSingleWireGoldenHasOnlyAuthoritativeFields() throws {
        let program = try fixture(id: "single")
        let data = try EffectProgramTransfer.exportSingle(program)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["schema"] as? Int == 1)
        #expect(root["kind"] as? String == "maurya-effect")
        #expect(Set(root.keys) == ["schema", "kind", "exportedBy", "program"])
        let exportedBy = try #require(root["exportedBy"] as? [String: Any])
        #expect(Set(exportedBy.keys) == ["appVersion", "programSchema"])
        let object = try #require(root["program"] as? [String: Any])
        #expect(
            Set(object.keys) == [
                "id", "nameZh", "nameJa", "sourceKind", "workspaceJson", "scriptSource", "astJson",
                "astSha256", "blockCount", "estimatedDurationMs", "createdAt", "updatedAt", "editorSchema", "programSchema",
            ])
        #expect(object["sourceKind"] as? String == "script")
    }

    @Test func importRecompilesAndDoesNotTrustExportedHash() throws {
        let original = try fixture(id: "same")
        var text = String(decoding: try EffectProgramTransfer.exportSingle(original), as: UTF8.self)
        text = text.replacingOccurrences(of: original.astSHA256, with: String(repeating: "0", count: 64))
        let preview = try EffectProgramTransfer.preview(Data(text.utf8), existingIDs: ["same"], now: { 9_000 })
        #expect(preview.errors.isEmpty)
        #expect(preview.conflictIDs == ["same"])
        #expect(preview.programs.first?.astSHA256 == original.astSHA256)
        #expect(preview.programs.first?.updatedAt == 9_000)
    }

    @Test func bundleRoundTripPreservesIDsAndCanonicalPrograms() throws {
        let programs = try (0..<8).map { try fixture(id: "sample-\($0)", colour: $0.isMultiple(of: 2) ? "#FF0000" : "#0000FF") }
        let data = try EffectProgramTransfer.exportBundle(programs)
        let preview = try EffectProgramTransfer.preview(data, existingIDs: [], now: { 8_000 })
        #expect(preview.errors.isEmpty)
        #expect(preview.programs.map(\.id) == programs.map(\.id))
        #expect(preview.programs.map(\.astSHA256) == programs.map(\.astSHA256))
    }

    @Test("Strict malicious inputs are rejected", arguments: maliciousInputs)
    func maliciousInput(_ data: Data) {
        do {
            let preview = try EffectProgramTransfer.preview(data, existingIDs: [])
            #expect(preview.programs.isEmpty)
            #expect(!preview.errors.isEmpty)
        } catch {
            #expect(error is EffectProgramError)
        }
    }

    @Test func fileAndSourceLimitsAreExact() throws {
        let oversized = Data(repeating: 0x20, count: EffectProgramTransfer.maximumFileBytes + 1)
        #expect(throws: EffectProgramError.fileTooLarge) { try EffectProgramTransfer.preview(oversized, existingIDs: []) }

        let hugeSource = "effect \"x\" { wait(1ms); }" + String(repeating: " ", count: EffectScriptCompiler.maximumSourceBytes)
        let object: [String: Any] = [
            "schema": 1, "kind": "maurya-effect",
            "program": [
                "id": "huge", "nameZh": "大", "nameJa": "大", "sourceKind": "script", "scriptSource": hugeSource,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        let preview = try EffectProgramTransfer.preview(data, existingIDs: [])
        #expect(preview.programs.isEmpty)
        #expect(preview.errors.count == 1)
    }

    @Test func revisionsAreStableAndChangeWithKnownFields() throws {
        let first = try fixture(id: "revision")
        let same = try fixture(id: "revision")
        #expect(try EffectProgramTransfer.revision(of: first) == EffectProgramTransfer.revision(of: same))
        let changed = try fixture(id: "revision", colour: "#00FF00")
        #expect(try EffectProgramTransfer.revision(of: first) != EffectProgramTransfer.revision(of: changed))
    }

    private static let maliciousInputs: [Data] = [
        Data(#"{"schema":1,"schema":1,"kind":"maurya-effect","program":{}}"#.utf8),
        Data(#"{"schema":1,"kind":"maurya-effect","unknown":1,"program":{}}"#.utf8),
        Data(#"{"schema":1,"kind":"other","program":{}}"#.utf8),
        Data(#"{"schema":2,"kind":"maurya-effect","program":{}}"#.utf8),
        Data(#"{"schema":1,"kind":"maurya-effect","program":{"nameZh":1}}"#.utf8),
        Data(
            #"{"schema":1,"kind":"maurya-effect","program":{"id":"x","nameZh":"x","nameJa":"x","sourceKind":"future","scriptSource":"x"}}"#
                .utf8),
        Data([0xFF, 0xFE]),
    ]

    private func fixture(id: String, colour: String = "#FF0000") throws -> EffectProgram {
        try Self.fixture(id: id, colour: colour)
    }

    private static func fixture(id: String, colour: String = "#FF0000") throws -> EffectProgram {
        try EffectProgramCompiler.normalise(
            EffectProgram(
                id: id, nameZh: "测试", nameJa: "テスト", createdAt: 1_000, updatedAt: 1_000,
                sourceKind: .script, scriptSource: "effect \"x\" { all.color(\"\(colour)\"); wait(100ms); }"
            ),
            now: 1_000
        )
    }
}
