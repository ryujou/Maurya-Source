import Foundation
import Observation

enum AppLanguageChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case simplifiedChinese
    case japanese

    var id: Self { self }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        case .japanese: Locale(identifier: "ja")
        }
    }

    var titleKey: String {
        switch self {
        case .system: "language.system"
        case .simplifiedChinese: "language.chinese"
        case .japanese: "language.japanese"
        }
    }
}

struct FileAppLanguageStore: Sendable {
    let fileURL: URL

    init(
        fileURL: URL = URL.applicationSupportDirectory
            .appending(path: "Maurya/Preferences", directoryHint: .isDirectory)
            .appending(path: "language.json")
    ) {
        self.fileURL = fileURL
    }

    func load() -> AppLanguageChoice {
        guard let data = try? Data(contentsOf: fileURL),
            let choice = try? JSONDecoder().decode(AppLanguageChoice.self, from: data)
        else {
            return .system
        }
        return choice
    }

    func save(_ choice: AppLanguageChoice) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(choice).write(to: fileURL, options: .atomic)
    }
}

@MainActor
@Observable
final class AppLanguageSettings {
    private(set) var selection: AppLanguageChoice
    private(set) var persistenceError: String?
    private let store: FileAppLanguageStore

    init(store: FileAppLanguageStore = FileAppLanguageStore()) {
        self.store = store
        selection = store.load()
    }

    var locale: Locale { selection.locale }

    var effectPresentationLanguage: EffectPresentationLanguage {
        switch selection {
        case .simplifiedChinese:
            .simplifiedChinese
        case .japanese:
            .japanese
        case .system:
            EffectPresentationLanguage(locale: .autoupdatingCurrent)
        }
    }

    func select(_ choice: AppLanguageChoice) {
        guard choice != selection else { return }
        do {
            try store.save(choice)
            selection = choice
            persistenceError = nil
        } catch {
            persistenceError = String(describing: error)
        }
    }
}
