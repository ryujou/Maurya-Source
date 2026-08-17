import Testing

@testable import MauryaShare

struct ShareTokenTests {
    @Test(
        "Canonical, short, and URL forms",
        arguments: [
            "K8F3Q7D2PX", "K8F3Q-7D2PX",
            "https://xtbang.top/maurya/s/K8F3Q7D2PX",
            "https://xtbang.top/maurya/s/K8F3Q7D2PX/",
        ])
    func acceptedForms(_ raw: String) throws {
        #expect(try ShareToken.parse(raw) == "K8F3Q7D2PX")
    }

    @Test(
        "Reject malformed or ambiguous input",
        arguments: [
            "https://example.com/maurya/s/K8F3Q7D2PX", "http://xtbang.top/maurya/s/K8F3Q7D2PX",
            "https://xtbang.top:443/maurya/s/K8F3Q7D2PX", "https://user@xtbang.top/maurya/s/K8F3Q7D2PX",
            "https://xtbang.top/maurya/s/K8F3Q7D2PX?x=1", "https://xtbang.top/maurya/s/K8F3Q7D2PX#x",
            "https://xtbang.top/maurya/s/K8F3Q7D2PX/extra", "K8F3Q7D2P0", "K8F3Q7D2PO",
        ])
    func rejectedForms(_ raw: String) {
        #expect(throws: ShareValidationError.invalidToken) { try ShareToken.parse(raw) }
    }

    @Test func shortCodeIsCanonicalized() throws {
        #expect(try ShareToken.shortCode("K8F3Q7D2PX") == "K8F3Q-7D2PX")
        #expect(try ShareToken.canonicalURL("K8F3Q-7D2PX").absoluteString == "https://xtbang.top/maurya/s/K8F3Q7D2PX")
    }
}
