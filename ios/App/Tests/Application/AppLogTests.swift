import Testing

@testable import Maurya

@Suite("Release-safe log policy")
struct AppLogTests {
    @Test("Only the reviewed finite categories are available")
    func reviewedCategories() {
        #expect(AppLog.subsystem == "com.ryujou.Maurya")
        #expect(
            AppLog.categoryNames == [
                "lifecycle", "bluetooth", "effects", "sharing", "ota", "persistence",
            ])
    }
}
