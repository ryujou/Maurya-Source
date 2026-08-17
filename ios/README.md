# Maurya iOS

This directory is the native iOS migration workspace described by
[`../IOS_PORTING_MASTER_PLAN.md`](../IOS_PORTING_MASTER_PLAN.md).

## Current foundation

The repository now contains a buildable unsigned SwiftUI application shell and
several independently testable Swift 6.2 packages. Application identity and the
iOS 17 deployment decision are recorded in
[`ADR/0001-app-identity-and-deployment.md`](ADR/0001-app-identity-and-deployment.md).
Signing team and distribution profiles remain intentionally unset.

- `MauryaProtocol`: platform-independent BLE identifiers, binary I/O, Modbus
  CRC/request/response codecs, bounded incremental response decoding, and
  negotiated effect geometry. It also contains the generic vendor/TLV envelope,
  volatile Effects commands, and BLE OTA request codecs.
- `MauryaProtocolTests`: Swift Testing golden vectors and boundary tests.
- `Packages/MauryaBluetooth`: CoreBluetooth transport, lifecycle state machine,
  bounded transaction queue, notification decoding, and reconnect policy.
- `Packages/MauryaDevice`: schema-limited register mapping, device information,
  domain state, polling policy, and repository actor.
- `Packages/MauryaEffects`: effect runtime values and algorithms plus the first
  typed Blockly compiler/interpreter vertical slice.
- `Packages/MauryaShare`: strict share envelope, canonical JSON/hash, bounded
  gzip, token/URL validation, WebP structure checks, and local moderation.
- `Packages/MauryaResources`: Android-mirrored character/group resources,
  palette catalog, custom palette validation/storage, backup, and share bridge.
- `Packages/MauryaAnalysis`: Android-aligned audio DSP, motion mapping, input
  freshness aggregation, and conditional Apple audio/CoreMotion providers.
- `Packages/MauryaEditor`: offline WKWebView editor host, strict versioned
  bridge, autosave/recovery, and a hashed copy of the rebuilt Android editor.
- `Packages/MauryaPlayback`: structured 10/20 Hz effect scheduler, heartbeat,
  acknowledgement, backpressure, reconnect, lifecycle policy, and metrics.
- `Packages/MauryaOTA`: secure OTA preflight, artifact verification, BLE
  transfer/resume, checkpointing, commit, and post-reconnect confirmation.
- `App`: unsigned SwiftUI app shell with typed navigation, design tokens,
  localization, live BLE/device/share composition, and explicit states for
  features that are still not integrated.

Protocol tests consume `../protocol/maurya-protocol.json` and
`../protocol/golden-vectors.json` directly from the repository. They do not keep
an iOS-private copy of cross-platform fixtures.

The current hardware fallback is **7 groups with 6 pixels per group (42 total)**.
New firmware may report another validated geometry, but an absent capability
must resolve to that fallback.

## Requirements

- Swift 6.2 or newer (validated with Xcode 26.6 / Swift 6.3.3).
- Full Xcode is required to build the application and generic iOS package
  destinations. Physical CoreBluetooth/device tests require a signed build and
  real hardware.

## Test

```sh
cd ios
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

The explicit developer directory is needed on the current development machine
because its global `xcode-select` still points at Command Line Tools, whose
standalone Swift invocation does not expose the Swift Testing module correctly.

## Xcode integration

The app project is under `App/Maurya.xcodeproj`. Protocol, Bluetooth, Device,
and Share are composed through dependency protocols and live adapters; unfinished
features retain explicit unavailable states so they cannot masquerade as working
data. Protocol source is not copied into the app target.

The following remain outside this foundation and are required by later phases:

- Signing team, provisioning, CI, OSLog, UI/snapshot tests, and release assets.
- App composition of effects, resources, analysis, editor, playback, full share
  workflow, and OTA.
- Real-device BLE, 42-pixel routing, performance, energy, and recovery Gates.
- Complete Blockly/Maurya Script language parity and analysis input providers.
- Share networking, QR/UI, Universal Link E2E, history transactions, and WebP encoding.
- OTA workflow UI, persistence, signed artifact service, and physical-device tests.
