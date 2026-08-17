# Maurya iOS App

This directory contains the SwiftUI application target and its composition of
the repository-level Swift packages.

## Open and build

Open `Maurya.xcodeproj` in Xcode 26 or newer, or run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Maurya.xcodeproj \
  -scheme Maurya \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  SWIFT_SUPPRESS_WARNINGS=NO \
  CODE_SIGNING_ALLOWED=NO build
```

The project targets iOS 17, Swift 6 strict concurrency, iPhone and iPad. Debug,
Staging, and Release keep service URL and log level values in configuration
files. Share still uses non-routable `.invalid` placeholders; OTA uses the same
`https://xtbang.top/maurya/ota` release service and RSA public key as Android.

Unit tests use Swift Testing and cover pure route and state behavior. Run them against an installed iOS Simulator:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Maurya.xcodeproj \
  -scheme Maurya \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  SWIFT_SUPPRESS_WARNINGS=NO test
```

The explicit `SWIFT_SUPPRESS_WARNINGS=NO` avoids Xcode adding
`-suppress-warnings` to local Swift packages that already compile with
`-warnings-as-errors`.

## Present scope

- Real `NavigationStack` routes for scan, device detail, share import, and `maurya://` deep links.
- A composition root that adapts the local MauryaProtocol, MauryaBluetooth,
  MauryaDevice, and MauryaShare products. Preview/Test can inject protocol fakes.
- Foreground CoreBluetooth scan/connect/GATT readiness lifecycle, snapshot/info
  refresh, scene/global LED controls, diagnostics clearing, and read/write
  controls for all seven lighting groups.
- A searchable role/support-color browser with an accessible preview and a
  fail-closed write path that preserves the selected device group's mode and
  parameter. The device Help screen documents the exact foreground workflow.
- Strict 10-character/5-5 share token, custom deep-link, Universal Link,
  production HTTPS client, QR generation/scanning, verified preview, explicit
  confirmation, history de-duplication, and effect/palette import consumers.
- Shared design tokens and Loading, Empty, Error, Permission, and Disconnected state presentations.
- English fallback plus Simplified Chinese and Japanese localizations, with a
  persisted in-app System/简体中文/日本語 selector. Editor, resources, and share
  names follow the selected locale.

## Phase 5–9 vertical entries

- The app now links MauryaEffects, MauryaResources, MauryaAnalysis,
  MauryaEditor, MauryaPlayback, and MauryaOTA as local package products.
- The visible Features menu contains Effects, user-triggered foreground
  audio/motion analysis, and the OTA workflow. Resources/palettes and the editor
  remain contextual capabilities reached from device/effect flows; they are not
  presented as standalone home or iPad-sidebar entries.
- Bluetooth, Microphone, Motion, and Camera usage descriptions are present
  because the corresponding foreground user actions invoke those providers.
  No background mode is declared.
- OTA ships the Android production public key, uses the Android client
  compatibility version (421), and preserves strict RSA/hash/layout/variant/
  secure-version checks. A release-specific compatibility verifier accepts the
  published 1.8.0 detached signature after reconstructing only its original
  signed release-note text; artifact URL, hash, size, layout, and secure version
  remain covered by that signature.

## Still gated

- Physical-device BLE verification, throughput/energy checks, and the Phase 3
  hardware matrix. Simulator and fake-service tests do not satisfy this gate.
- Physical-device verification for telemetry conflict states and slider write
  throttling under real BLE latency.
- Custom PhotosPicker/crop/rotate/color/WebP save is implemented locally; the
  Android round-trip and visual-quality gates remain. All 560 bundled role/group
  images are enabled for the current personal local-use build and decoded on
  demand in resource rows. A separate rights review applies only if distribution
  later expands beyond personal local installation.
- Playback needs a connected compatible BLE device plus a compiled effect;
  the app does not substitute a fake transport. Background continuation is off.
- OTA still needs a connected compatible device and physical interruption/
  recovery testing. Updating the CDN manifest requires the protected release
  private key; it is not bundled in the app or repository.
- Production Share staging/OpenAPI/AASA, physical camera testing, Android↔iOS
  end-to-end exchange, and installed-app Universal Link verification.
- Automated iPhone/iPad evidence captures are under `VisualBaselines`; physical
  VoiceOver, keyboard, full snapshot-matrix review and energy evidence remain.
- Signing team, production service URLs, Associated Domains, and release metadata.

Generic unsigned builds and simulator tests do not close physical-device,
development signing, OTA recovery, installed-size, or energy gates. App Review
and public-distribution rights are outside the current personal local-use scope.

Production-dependent sections remain explicit unavailable states. The app does
not add entitlements, background modes, tracking, or unreviewed binary
dependencies; libwebp source and its BSD-3-Clause notice are bundled explicitly.
