import Foundation
import Testing

@testable import Maurya

struct DeepLinkParserTests {
    @Test(
        "Supported deep links map to routes",
        arguments: [
            ("maurya://device/lumia-01", AppRoute.deviceDetail(id: "lumia-01")),
            ("maurya://share/K8F3Q7D2PX", AppRoute.shareImport(token: "K8F3Q7D2PX")),
            ("https://xtbang.top/maurya/s/K8F3Q7D2PX", AppRoute.shareImport(token: "K8F3Q7D2PX")),
            ("maurya://share", AppRoute.shareImport(token: nil)),
        ]
    )
    func supportedURL(rawURL: String, expectedRoute: AppRoute) throws {
        let url = try #require(URL(string: rawURL))
        #expect(DeepLinkParser.route(from: url) == expectedRoute)
    }

    @Test(
        "Unsupported or malformed deep links are rejected",
        arguments: [
            "https://example.com/device/lumia-01",
            "maurya://device",
            "maurya://device/one/two",
            "maurya://unknown/value",
            "maurya://share/K8F3Q7D2P0",
            "https://xtbang.top/maurya/s/K8F3Q7D2PX?tracking=1",
        ]
    )
    func unsupportedURL(rawURL: String) throws {
        let url = try #require(URL(string: rawURL))
        #expect(DeepLinkParser.route(from: url) == nil)
    }
}
