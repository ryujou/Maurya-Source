# MauryaEditor

`MauryaEditor` is the Phase 7 iOS 17+ SwiftUI/WKWebView host for the existing Blockly and CodeMirror editors. It intentionally uses `WKWebView` because the iOS 26 SwiftUI WebKit API does not replace the required JavaScript-to-native message handler.

## Security and bridge contract

- The editor is served offline at `maurya-editor://bundle/` by a read-only `WKURLSchemeHandler`. Only paths present in `manifest.json` are served.
- HTTP(S), file URLs, unknown schemes, new windows, downloads, non-main-frame navigations, camera, and microphone capture are denied.
- The website data store is non-persistent. CSP disables networking, frames, objects, and forms.
- JavaScript is injected into the page content world only for the main frame. The handler validates the expected origin plus bridge version, per-WebView nonce, request ID, message bytes, document bytes, nesting depth, node count, and command-specific schema.
- Native-to-JavaScript traffic goes through `callAsyncJavaScript` with an argument dictionary and a fixed dispatcher. There is no arbitrary JavaScript, selector, URL, or file API.
- The command allowlist is `load`, `export`, `import`, `undo`, `redo`, `resize`, `fit`, `run`, `editField`, `insertWaitAfter`, `diagnostic`, and `clearDiagnostics`. Events are `ready`, `workspaceChanged`, `sourceChanged`, `saveRequested`, `runRequested`, `haptic`, and correlated `response`.
- The model, WebKit delegates, lifecycle, and handler cleanup are `MainActor`-isolated. Teardown cancels outstanding tasks, stops loading, removes scripts/message handlers, and detaches delegates.
- Optional autosave is debounced and atomically written with complete file protection. Web content process termination reloads the verified bundle and restores the latest autosave.

## Rebuilding and synchronizing the editor

The source of truth remains `android/effect_editor`; never edit the minified files in this package.

```sh
cd android/effect_editor
npm ci
npx playwright install chromium
npm test

cd ../../ios/Packages/MauryaEditor
node Tools/sync-editor-bundle.mjs
swift test
```

The sync tool copies the Android app's reproducible Vite output from `android/app/src/main/assets/effect-editor`, records editor version `4.2.1`, per-file size/MIME/SHA-256, and the canonical bundle SHA-256. Runtime verification occurs before loading any page. Current bundle SHA-256: `06329b4cb6dddd62014fb3fd01979cf11ba92cff63ab45cfdc4e18be25ae18bf`.

Generic iOS build:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme MauryaEditor -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

## Integration example

```swift
@StateObject private var model = MauryaEditorModel(autosaveURL: autosaveURL)

MauryaEditorView(
    model: model,
    configuration: .init(editor: .blocks, language: .simplifiedChinese, initialDocument: workspaceJSON)
)
```

Use `model.onEvent` for workspace/source changes, run/save requests, haptics, and export responses. Use `try model.send(...)` only after `phase == .ready`.
`model.bundleVersion` and `model.bundleSHA256` are suitable for About and diagnostic surfaces.

## Phase 7 device gates (not claimed by package tests)

Before app integration is accepted, run these on real supported iPhones and iPads:

- WebView lifecycle: load/edit/export/run, background/foreground, memory-pressure process termination, reload recovery, and repeated presentation/dismissal without retained handlers.
- Keyboard and layout: software/hardware keyboards, Chinese/Japanese IME composition, safe areas, split view, rotation, visual viewport changes, maximum Dynamic Type, pinch/drag, and long-press field editing without document loss.
- VoiceOver: meaningful editor/control announcements, focus order, modal field-editor focus containment, rotor navigation, and no inaccessible icon-only controls.
- Security: attempts for HTTP(S), file, unknown schemes, `window.open`, downloads, iframe messages, wrong nonce/version, oversized/deep payloads, unknown commands, and web media capture all fail closed.
- Performance: measure first ready time, import/export latency near the 1 MB cap, typing/drag frame pacing, peak memory, autosave I/O, rotation, and 30 reload cycles on the lowest supported device.

Swift parser/state-machine tests and a generic build do not substitute for these UI, accessibility, keyboard, performance, or real-device gates.
