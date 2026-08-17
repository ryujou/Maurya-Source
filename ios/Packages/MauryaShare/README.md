# MauryaShare

Swift 6 share workflow core for the Maurya iOS port. It implements the frozen v1 envelope,
Android-compatible canonical JSON/content SHA-256, strict token and Universal Link parsing,
bounded JSON/gzip validation, the portable moderation precheck, HTTPS API client, actor-isolated
import history, CoreImage QR generation, and camera-independent scan parsing.

## Integration surface

- `ShareAPIClient.production()` uses an injected `URLSession` created from
  `URLSessionConfiguration.default`. It accepts only `https://xtbang.top` without a port or user
  info, rejects redirects, keeps default platform TLS trust evaluation, disables cache/cookies,
  and applies explicit request/resource timeouts.
- Create is a single POST with an idempotency key and is never automatically retried. Metadata and
  blob GETs retry only timeout/offline/transport, 429, and 5xx failures with bounded backoff.
- Status, endpoint, media type, declared/actual response size, strict response fields, token, date,
  hash, blob length, envelope kind, gzip and business payload are all checked before preview.
- `ShareHTTPTransport` is the test/staging seam. Offline tests use actor fakes and never perform
  live requests.
- `ShareImportHistory` stores only token hashes plus local IDs, de-duplicates newest-first, caps at
  Android's 256 records, and publishes state only after an atomic replacement write succeeds.
  The App's `EffectShareImportConsuming` and `PaletteShareImportConsuming` implementations must
  commit the actual imported object and a uniquely constrained token marker in one transaction;
  marker collisions report `ShareImportConsumerError.duplicateToken`.
- `ShareWorkflow` mirrors the Android create/import orchestration without depending on the Effect
  or Palette packages: local moderation precedes upload, QR descriptors follow create, metadata and
  blob validation precede consumer preview, confirmation is explicit, and duplicate history is
  checked both before preview and immediately before the atomic consumer commit. Generation checks
  prevent cancelled or superseded operations from overwriting newer state.
- `ShareQRCodeDescriptor` canonicalizes the URL and pins 1024 px, high error correction, and a
  four-module quiet zone by default. `ShareQRCodeGenerator` renders through CoreImage.
- `AVFoundationShareQRCodePayloadProvider` owns an actor-isolated iOS 17 capture graph and accepts
  QR metadata only after strict Maurya host/path/token validation. Its stream uses
  `.bufferingNewest(1)`; `withPayloads` couples task cancellation to stream completion and stops the
  session before returning, without spawning an untracked task. The lower-level `start()`/`stop()`
  pair is available when the App needs explicit ownership and must always be balanced.
- The App checks/request camera authorization before starting and forwards background/foreground
  and `AVCaptureSession` interruption events through the provider's explicit lifecycle methods.
  The package does not observe App notifications, own permission copy, or navigate. Permission
  denial must leave manual token entry available.
- `VisionShareQRCodePayloadProvider` remains available for still-image parsing without owning a
  camera or requesting permission.

## gzip portability decision

Apple's Compression framework does not directly produce the Android-compatible gzip container.
This package therefore uses a tiny C adapter over the platform `libz`, linked by SwiftPM, while
keeping framing checks and all domain validation in Swift. This is available on both iOS 17+
and macOS 14+, avoids a third-party dependency, creates a standard single-member gzip stream,
and validates header structure, raw-deflate completion, trailing-member absence, CRC32, ISIZE,
compressed size, and a 2 MiB expansion ceiling. The optional gzip header CRC is structurally
bounded but, matching the current Android implementation, is not itself verified.

## External Phase 10 gates

- The repository still does not contain the share service implementation/OpenAPI, a reachable
  staging environment, authoritative retention/rate-limit policy, or an iOS AASA deployment.
  Therefore the fake contract suite is not network E2E and Phase 10 must not be marked complete.
- Associated Domains, AASA installation/upgrade/cold-launch/running-app coverage, and final
  Universal Link navigation belong to the App and server deployment, outside this package.
- AVFoundation camera permission copy, denial/manual entry fallback, camera-session lifecycle,
  preview-layer integration, interruption notification forwarding, and real-camera QR tests belong
  to the App. A real iPhone gate must cover grant/deny, foreground/background, phone/camera
  interruption, cancellation, repeated start/stop, low light, and malformed/foreign QR codes.
- Android export to iOS and iOS export to Android still require the staging service and two-device
  test matrix. No cross-platform result is claimed by this package's fake tests.
- No WebP encoder or decoder dependency. Imported palette data is strictly base64/hash/size
  checked and its RIFF VP8/VP8L/VP8X header must declare 96x96. Full image decode and safe 96x96
  re-encoding remain the real-device WebP spike; this package never substitutes PNG/JPEG.
- Local moderation deliberately mirrors Android's fast, incomplete pinned-list precheck. The
  server remains authoritative.

## Verification

Run from this directory:

```sh
swift test -c debug
swift test -c release
IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
swift build -c debug --triple arm64-apple-ios17.0 --sdk "$IOS_SDK"
swift build -c release --triple arm64-apple-ios17.0 --sdk "$IOS_SDK"
```

All Swift targets compile with warnings treated as errors. Tests and generic iOS cross-builds
require a full Xcode installation; when `xcode-select` points at Command Line Tools, prefix commands
with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (or select the installed Xcode).
