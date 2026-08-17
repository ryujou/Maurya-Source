# Maurya port reproducible baseline

Recorded: 2026-08-09, Asia/Shanghai
Source commit: `56709f15cc0173d2c8b28fad8db68b7f48396844`
Branch: `main`
Remote verification: local `HEAD`, `origin/main`, and `git ls-remote origin
refs/heads/main` matched when this record was produced.

This is the Phase 0 local baseline. It records commands and results but does
not replace physical-device, production-service, legal, signing, or release
evidence. The implementation is currently an uncommitted worktree and must be
re-run from the eventual review commit.

## Toolchain snapshot

| Tool | Version / path |
|---|---|
| macOS | 26.6.1, arm64 |
| Git | Apple Git 2.50.1 (155) |
| Xcode | 26.6 (17F113), `/Applications/Xcode.app` |
| Swift | Apple Swift 6.3.3 |
| Java | Homebrew OpenJDK 17.0.20 |
| Gradle/Kotlin | Gradle 9.1.0, embedded Kotlin 2.2.0 |
| Android tools/platform | command-line tools 22.0, `android-36` |
| Node/npm | Node 25.9.0, npm 11.12.1 |
| ESP-IDF | 6.0.1, target ESP32-C3 |
| Python | Apple Python 3.9.6 for repository validators; ESP-IDF owns its separate environment |
| Host C compiler | Apple clang 21.0.0 |

All Xcode commands set
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Android commands
set `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`
and `ANDROID_HOME=/opt/homebrew/share/android-commandlinetools`. ESP-IDF is
activated from the locally installed 6.0.1 `export.sh`.

## Android and embedded editor

```sh
cd android
bash ./gradlew :app:testDebugUnitTest :app:assembleDebug --rerun-tasks

cd android/effect_editor
npm test -- --run
npx playwright test
```

Result: Android `BUILD SUCCESSFUL` (43 tasks), with 90 unit tests across 20 XML
suites and no failures/skips; editor Vitest 3/3 and Playwright
15/15. The editor production build and copied APK assets are scanned for the
7×6=42 contract and old 70-pixel semantics.

## Shared protocol

```sh
python3 protocol/validate_protocol.py
```

Result: 251 checks, 14 byte-exact frame vectors, geometry 7×6=42, pixel frame
140 bytes. Fixtures cover CRC/Modbus/vendor/effect/OTA/geometry boundaries and
are consumed by Swift tests rather than privately copied.

## ESP32 and embedded Web UI

From `esp32/lumia_esp32`, compile/run the seven commands documented in
`tests/host/README.md`, then:

```sh
python3 tools/test_web_assets.py
python3 tools/test_flash_layout.py
python3 tools/test_led_geometry.py

cd web_ui
npm run build && npm test
npm run build:ja && npm run test:ja

cd ..
idf.py build
```

Result: seven host C suites, three Python contract/resource suites, and both
Web UI variants passed. ESP-IDF 6.0.1 produced `lumia_esp32.bin` size
`0xf1000`; the smallest `0x110000` app partition retained `0x1f000` (11%).
No firmware was flashed and no test signing artifact is authorized for release.

## Swift packages

For root `ios` and every directory containing `ios/Packages/*/Package.swift`:

```sh
swift test --package-path <path> -Xswiftc -warnings-as-errors
swift test --package-path <path> -c release -Xswiftc -warnings-as-errors
```

Current per-configuration total: 317 tests.

| Package | Tests |
|---|---:|
| MauryaProtocol | 60 |
| MauryaBluetooth | 18 |
| MauryaDevice | 12 |
| MauryaEffects | 99 |
| MauryaResources | 20 |
| MauryaAnalysis | 16 |
| MauryaEditor | 11 |
| MauryaPlayback | 8 |
| MauryaOTA | 26 |
| MauryaShare | 47 |

Each package also passed an unsigned generic iOS 17 build with warnings as
errors. Xcode package builds use `SWIFT_SUPPRESS_WARNINGS=NO` because package
targets already enforce `-warnings-as-errors`.

## iOS App

```sh
xcodebuild -project ios/App/Maurya.xcodeproj -scheme Maurya \
  -configuration <Debug|Staging|Release> \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO \
  SWIFT_SUPPRESS_WARNINGS=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build

xcodebuild -project ios/App/Maurya.xcodeproj -scheme Maurya \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<available-iPhone-UDID>' \
  SWIFT_SUPPRESS_WARNINGS=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES test
```

Result after the completion-audit and formatting round: all three generic
builds passed. Release `.app` was 26,152 KiB; Debug and Staging were 28,300 and
26,580 KiB. iPhone 17 Pro / iOS 26.3.1 ran 55 logical tests / 74 parameterized
executions, 0 failed and 0 skipped, including all eight serialized UI journeys.
The resource-list journey visually confirms packaged role/group avatars. Two
resource/effect and accessibility journeys also passed on the iPad Pro 13-inch
simulator. All three generic products contained `PrivacyInfo.xcprivacy` plus
compiled en/zh-Hans/ja `InfoPlist.strings` from `InfoPlist.xcstrings`.

The serialized `MauryaResources` Release host measurement loaded the 560-entry
inventory in 86.726 ms with a 5,160,960-byte resident delta. Ten representative
WebP decode/crop/color iterations had a 0.185 ms median and 950,272-byte resident
delta. This is host evidence only; minimum-device memory and archived installed
size remain external release measurements.

## Static consistency checks

```sh
git diff --check
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ios-foundation.yml")'
plutil -lint ios/App/Config/Info.plist
plutil -lint ios/App/Resources/PrivacyInfo.xcprivacy
python3 -m json.tool ios/App/Resources/Localizable.xcstrings
python3 -m json.tool ios/App/Resources/InfoPlist.xcstrings
xcrun xcstringstool compile --dry-run --output-directory <tmp> \
  ios/App/Resources/Localizable.xcstrings
xcrun swift-format lint --strict --configuration ios/.swift-format <all Swift sources>
```

The protocol validator, plist/String Catalog lint and dry-run compile, strict
Swift format, workflow YAML parse, localization parity and diff check passed.
MauryaProtocol production line coverage was 99.70%; the six critical request
and vendor/effect/OTA codecs were 100%. CI contains protocol coverage, every
package's Debug/Release tests, App unit/UI tests and all three unsigned App
configurations, but has no remote run until this work is reviewed and pushed.

## Missing external evidence

`xcrun devicectl list devices` found no Apple device; no Android/ADB device and
no USB serial ESP32 were present. Therefore no local result proves BLE radio,
physical 42-pixel routing, sensor/microphone/camera behavior, WebP cross-device
interop, OTA flashing/recovery, accessibility hardware behavior, long-run
energy/thermal behavior, or production services. Those remain explicit Gates
P0/P3/P5–P14.
