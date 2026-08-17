import Testing

@testable import Maurya

struct AppContentStateTests {
    @Test func errorStatePreservesDiagnosticMessage() {
        let state = AppContentState.error(message: "fixture failure")
        #expect(state == .error(message: "fixture failure"))
    }

    @Test(
        "Common non-error states remain distinct",
        arguments: [
            AppContentState.loading,
            .empty,
            .permissionRequired,
            .disconnected,
        ]
    )
    func commonStateIsNotError(state: AppContentState) {
        #expect(state != .error(message: "fixture failure"))
    }
}
