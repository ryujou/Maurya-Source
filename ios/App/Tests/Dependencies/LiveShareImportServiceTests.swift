import Foundation
import Testing

@testable import Maurya

@MainActor
struct LiveShareImportServiceTests {
    @Test(
        "Share input is canonicalized",
        arguments: [
            "K8F3Q7D2PX",
            "K8F3Q-7D2PX",
            "https://xtbang.top/maurya/s/K8F3Q7D2PX",
        ])
    func canonicalizes(_ input: String) throws {
        let service = LiveShareImportService()
        let canonicalURL = try #require(URL(string: "https://xtbang.top/maurya/s/K8F3Q7D2PX"))
        service.validate(input)

        #expect(
            service.validation
                == .valid(
                    ValidatedShareLink(
                        token: "K8F3Q7D2PX",
                        canonicalURL: canonicalURL
                    )
                )
        )
    }

    @Test func rejectsUntrustedHost() {
        let service = LiveShareImportService()
        service.validate("https://example.com/maurya/s/K8F3Q7D2PX")
        #expect(service.validation == .invalid)
    }

    @Test func cancelDismissesFailedStateBackToIdle() async {
        let service = LiveShareImportService()
        await service.fetchForPreview("not-a-share-token")
        guard case .failed = service.operation else {
            Issue.record("Expected invalid input to enter the failed state")
            return
        }

        service.cancel()

        #expect(service.operation == .idle)
    }
}
