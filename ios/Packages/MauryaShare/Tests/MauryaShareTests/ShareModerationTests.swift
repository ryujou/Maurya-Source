import Testing

@testable import MauryaShare

struct ShareModerationTests {
    @Test func safeEffectPassesLocalPrecheck() throws {
        #expect(ShareModeration.check(try effect("星空彩虹")) == .accepted)
    }

    @Test("Normalization cannot bypass trie", arguments: ["六\u{200B}四-事 件", "六\u{200E}四、事，件"])
    func normalizationCannotBypassTrie(_ name: String) throws {
        #expect(ShareModeration.check(try effect(name)) == .rejected)
    }

    @Test func sourceIsCheckedAlongsideDisplayName() throws {
        let envelope = try effect("普通灯效", source: "effect \"demo\" { // 法轮功 wait(1s); }")
        #expect(ShareModeration.check(envelope) == .rejected)
    }

    private func effect(_ name: String, source: String = "effect \"safe\" { wait(1s); }") throws -> ShareEnvelope {
        try ShareEnvelopeCodec.makeEffect(names: ShareDisplayName(zh: name, ja: ""), sourceKind: .script, source: source)
    }
}
