import Foundation
import Testing

@testable import MauryaEditor

struct EditorBundleTests {
    @Test func bundledEditorMatchesManifest() throws {
        let bundle = try EditorBundleVerifier.verify()
        #expect(bundle.editorVersion == "4.2.1")
        #expect(bundle.bundleSHA256.count == 64)
        #expect(bundle.record(for: "index.html") != nil)
        #expect(bundle.record(for: "script.html") != nil)
    }

    @Test(arguments: ["../secret", "/absolute", "a/../b", "a\\b", "", "./index.html"])
    func unsafePathsAreRejected(_ path: String) {
        #expect(!EditorBundleVerifier.isSafeRelativePath(path))
    }

    @Test func autosaveIsAtomicAndBounded() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let file = directory.appending(path: "autosave.json")
        let store = EditorAutosaveStore(fileURL: file, maximumBytes: 16)
        try await store.save("document")
        #expect(try await store.restore() == "document")
        await #expect(throws: EditorBridgeError.invalidPayload) { try await store.save(String(repeating: "x", count: 17)) }
        try? FileManager.default.removeItem(at: directory)
    }
}
