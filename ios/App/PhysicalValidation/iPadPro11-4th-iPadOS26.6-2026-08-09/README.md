# Physical iPad Pro validation — 2026-08-09

## Device and build

- Device: iPad Pro (11-inch) (4th generation), `iPad14,3`
- OS: iPadOS 26.6 (`23G71`)
- Architecture: arm64
- App: Maurya 1.0 (1), Debug, automatic Personal Team signing
- Scheme: `MauryaUI`
- Xcode: 26.6 (`17F113`)
- Test window observed by XCTest in landscape: 1389×970 points

The Personal Team identifier was supplied only as a command-line build setting
and was not written to the project.

## Final automated result

Final physical-device run: **2 passed, 0 failed, 0 skipped**.

- `testIPadProLandscapeKeepsSidebarAndMajorRoutesUsable`
- `testScannerUnavailableRemainsRecoverableAcrossLandscapeAndLifecycle`

The first test covered the regular-width split sidebar, real bundled role/group
avatars, Effects → Editor ownership, software keyboard input, reachable Save,
Analysis, Playback, Share, and fail-closed OTA. The second covered full-screen
scanner unavailable/retry, Home/foreground recovery, and Cancel back to manual
entry. Test fixtures explicitly keep BLE, server, and OTA success unavailable.

The exported attachment manifest and three upright 2778×1940 physical-device
screenshots are in `attachments/`.

## Physical BLE result

Two additional read-only hardware checks passed on the same iPad and lamp:

- discovery found `Maurya-2601` advertising at approximately -78 dBm;
- connection reached the ready state, subscribed to the expected GATT
  characteristics, and read the device snapshot plus device information;
- the reported firmware is `1.8.0`, variant is `multilingual`, address is `1`,
  and all seven lighting groups were present;
- the test then explicitly disconnected.

The connection test passed in 12.449 seconds with 0 failures. It did not invoke
Apply Scene, Apply Global LEDs, any group Apply action, Clear Diagnostics,
Playback, or OTA. The final localized screenshot and attachment manifest are in
`ble-connect-final/`; the discovery-only evidence is in `ble/`.

## Issues found and resolved during the run

1. The global developer directory pointed at CommandLineTools. It was changed to
   `/Applications/Xcode.app/Contents/Developer` before the final run.
2. The original combined `Maurya` scheme built unit tests and UI tests together.
   On a physical device this changed local Swift-package linkage and launched an
   app that referenced an unembedded `MauryaProtocol` product framework. The new
   shared `MauryaUI` scheme builds only the app and UI-test runner.
3. Leaving the WKWebView editor published `.terminated` synchronously from
   `UIViewRepresentable.dismantleUIView`. Physical navigation exposed a Swift
   exclusivity abort during SwiftUI graph invalidation. `detach()` now performs
   non-observable teardown; a replacement coordinator still publishes its own
   loading state.
4. The first device snapshot rendered dynamically constructed localization keys
   literally. Dynamic mode labels now resolve through `String.LocalizationValue`;
   the final physical screenshot shows `Static` and `Steady` instead of raw keys.

## Deliberately not claimed by this run

- The physical ESP32 was discovered, connected, and read, but never written.
- BLE writes, playback traffic, disconnect/reconnect fault injection, and
  endurance behavior were not exercised.
- Camera success was not simulated or claimed.
- Microphone, motion, pressure/proximity, energy, VoiceOver, pointer, external
  keyboard, Stage Manager resize, and OTA recovery remain separate manual or
  hardware gates.
