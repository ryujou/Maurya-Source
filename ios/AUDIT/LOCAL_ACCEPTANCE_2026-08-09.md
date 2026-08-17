# Maurya iOS local acceptance record

Date: 2026-08-09 (Asia/Shanghai)
Android source anchor: `56709f15cc0173d2c8b28fad8db68b7f48396844`
Local `HEAD`, `origin/main`, and live `refs/heads/main`: matched at final audit
Worktree state: implementation is uncommitted and unpushed

## Meaning of this record

This record closes the repository-local implementation and simulation gates in
`IOS_PORTING_MASTER_PLAN.md`. It does not claim physical-device, production
service, legal, signing, TestFlight, or App Store completion. Those inputs are
listed with owners and due milestones in `EXTERNAL_GATES.md`.

## Cross-platform contract

- `python3 protocol/validate_protocol.py`: 251 checks passed; 14 byte-exact
  frame vectors; 7 groups × 6 pixels = 42; pixel frame = 140 bytes.
- Shared effect-algorithm and share canonical/gzip fixtures are consumed by
  Android and Swift tests from `protocol/`; no private iOS expected-value copy
  is authoritative.
- MauryaProtocol Debug/Release: 60 tests in 13 suites per configuration.
- Production-source line coverage: 99.70%; the six critical Modbus request,
  CRC, vendor envelope/TLV, effect, and OTA codecs are each 100%.

## iOS package matrix

Every row passed Debug and Release Swift Testing with warnings as errors, plus
an unsigned generic iOS Release build.

| Package | Tests per configuration |
|---|---:|
| MauryaProtocol | 60 |
| MauryaBluetooth | 18 |
| MauryaDevice | 12 |
| MauryaEditor | 11 |
| MauryaEffects | 99 |
| MauryaOTA | 26 |
| MauryaPlayback | 8 |
| MauryaResources | 20 |
| MauryaAnalysis | 16 |
| MauryaShare | 47 |
| **Total** | **317** |

All iOS Swift sources pass the repository `swift-format lint --strict`
configuration. App and package targets compile in Swift 6 mode with warnings as
errors.

## iOS App

- Debug, Staging, and Release unsigned generic iOS builds passed.
- Product sizes: Debug 28,300 KiB; Staging 26,580 KiB; Release 26,152 KiB.
- Each product contains `PrivacyInfo.xcprivacy` and compiled en/zh-Hans/ja
  `InfoPlist.strings` from the checked String Catalog.
- iPhone 17 Pro / iOS 26.3.1 simulator: 55 logical tests, 74 parameterized
  executions, 0 failed, 0 skipped. All eight UI journeys passed serially,
  including real packaged avatars in the resource list.
- iPad Pro 13-inch / iOS 26.3.1 simulator: populated resource/effect journey
  and largest accessibility text + RTL journey passed.
- Dark appearance is set through `XCUIDevice.appearance`, asserted from the
  SwiftUI environment, and visually reviewed. The final iPhone/iPad attachments
  and `xcresulttool` manifests are under `ios/App/VisualBaselines/`.
- `Info.plist`, `PrivacyInfo.xcprivacy`, both String Catalog JSON files, and
  String Catalog dry-run compilation passed.

## Android, editor, and firmware regression

- OpenJDK 17 / Android 36: `:app:testDebugUnitTest :app:assembleDebug
  --rerun-tasks` passed; 90 tests in 20 XML suites, 0 failed/skipped.
- Android editor 4.2.1: Vitest 3/3, Playwright 15/15, production Vite build,
  and npm production audit passed. The synchronized iOS editor contains 23
  files and canonical SHA-256
  `024179119dc8b43acbe6947691b1a55a69733282abb47e6b646f6a9803068f7f`.
- ESP32: seven host C suites, three Python contract/resource suites, and both
  multilingual/ja Web UI variants passed; Web UI production audit found no
  vulnerability.
- ESP-IDF 6.0.1 full build passed. `lumia_esp32.bin` is `0xf1000`; the smallest
  `0x110000` app partition retains `0x1f000` (11%). Nothing was flashed.

## Performance and privacy evidence

- The serialized Release host measurement loaded all 560 resource entries in
  86.726 ms with a 5,160,960-byte resident delta. Ten representative WebP
  decode/crop/color iterations had 0.185 ms median and 950,272-byte resident
  delta. These are host measurements, not minimum-device acceptance data.
- Production source uses the required-reason disk-capacity API only for bounded
  OTA preflight and declares Disk Space reason `E174.1`. No UserDefaults,
  AppStorage, system uptime, keyboard-state, or file-timestamp required-reason
  use was found.
- No tracking, background mode, Associated Domains, production endpoint/key, or
  entitlement has been added. Unavailable production capabilities remain
  visibly fail-closed.

## Open acceptance boundary

The total objective remains open until every applicable row in
`EXTERNAL_GATES.md` has commit-specific raw evidence. In particular, local
tests cannot prove 42-pixel physical routing, 20 Hz BLE endurance, real audio /
motion / pressure / proximity / camera behavior, Android↔iPhone interchange,
staging/AASA, signed OTA recovery, asset rights, archive signing, remote CI, or
App Store submission readiness.
