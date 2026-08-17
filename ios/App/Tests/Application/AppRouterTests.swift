import Foundation
import Testing

@testable import Maurya

@MainActor
struct AppRouterTests {
    @Test func navigationActionsAppendExpectedRoutes() {
        let router = AppRouter()

        router.showDevice(id: "device-42")
        router.showShareImport(token: "TOKEN")

        #expect(
            router.path == [
                .deviceDetail(id: "device-42"),
                .shareImport(token: "TOKEN"),
            ])
    }

    @Test func featureRoutesAreNavigable() {
        let router = AppRouter()
        let routes: [AppRoute] = [
            .resources, .effects, .editor, .analysis, .playback, .ota,
            .reviewerGuide, .legalPrivacy,
        ]

        for route in routes { router.show(route) }

        #expect(router.path == routes)
    }

    @Test func validDeepLinkReplacesExistingPath() throws {
        let router = AppRouter(path: [.deviceDetail(id: "old")])
        let url = try #require(URL(string: "maurya://share/K8F3Q7D2PX"))

        let handled = router.handle(url: url)

        #expect(handled)
        #expect(router.path == [.shareImport(token: "K8F3Q7D2PX")])
    }

    @Test func invalidDeepLinkPreservesExistingPath() throws {
        let originalPath = [AppRoute.deviceDetail(id: "current")]
        let router = AppRouter(path: originalPath)
        let url = try #require(URL(string: "https://example.com/share/CODE"))

        let handled = router.handle(url: url)

        #expect(handled == false)
        #expect(router.path == originalPath)
    }
}
