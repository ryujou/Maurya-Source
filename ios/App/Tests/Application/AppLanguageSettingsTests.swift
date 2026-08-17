import Foundation
import Testing

@testable import Maurya

@MainActor
struct AppLanguageSettingsTests {
    @Test func selectionPersistsWithoutUserDefaultsAndRestores() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "maurya-language-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = FileAppLanguageStore(fileURL: directory.appending(path: "language.json"))
        let settings = AppLanguageSettings(store: store)
        #expect(settings.selection == .system)

        settings.select(.japanese)
        #expect(settings.selection == .japanese)
        #expect(settings.locale.language.languageCode == .japanese)
        #expect(AppLanguageSettings(store: store).selection == .japanese)
    }

    @Test func corruptPreferenceFallsBackToSystem() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "maurya-language-corrupt-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "language.json")
        try Data("not-json".utf8).write(to: url)
        #expect(AppLanguageSettings(store: FileAppLanguageStore(fileURL: url)).selection == .system)
    }
}
