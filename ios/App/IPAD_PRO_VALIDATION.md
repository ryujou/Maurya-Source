# iPad Pro personal-device validation

Updated: 2026-08-09 (Asia/Shanghai)

This checklist validates the personal, locally installed build. It does not
require TestFlight or App Store submission. The project targets both iPhone and
iPad (`TARGETED_DEVICE_FAMILY = "1,2"`), and the iPad Info.plist declaration
allows portrait, upside-down portrait, landscape left, and landscape right.

## 1. Connect and sign the personal build

1. Connect the iPad Pro to the Mac with USB-C, unlock it, and accept **Trust
   This Computer** if prompted.
2. On the iPad, enable **Settings > Privacy & Security > Developer Mode** and
   complete the required restart/confirmation.
3. Open Xcode, choose **Xcode > Settings > Apple Accounts**, and add the Apple
   Account used for local development. A Personal Team is sufficient for
   running directly from Xcode; no App Store upload is involved.
4. Open `ios/App/Maurya.xcodeproj`, select the **Maurya** target, open **Signing
   & Capabilities**, leave **Automatically manage signing** enabled, and select
   that Team. Do not commit a personal Team ID to the repository.
5. Select the **Maurya** scheme and the connected iPad Pro as the run
   destination, then choose **Product > Run**. For UI automation, select the
   dedicated **MauryaUI** scheme; it intentionally excludes the unit-test host
   so Swift package products retain the same linkage as the installed app.

Xcode automatically registers the connected device and creates a development
provisioning profile when automatic signing is enabled. If the iPad is absent
from the destination list, check **Window > Devices and Simulators**, unlock the
device, reconnect USB-C, and confirm Developer Mode.

## 2. Automated landscape regression

With the iPad selected, run these tests from the Test navigator:

- `MauryaUITests.testIPadProLandscapeKeepsSidebarAndMajorRoutesUsable`
- `MauryaUITests.testScannerUnavailableRemainsRecoverableAcrossLandscapeAndLifecycle`

The first test rotates to landscape and checks the split sidebar, resource
avatars, Effects, editor keyboard/Save reachability, Analysis, Playback, Share,
and fail-closed OTA. The second checks the full-screen scanner's unavailable,
retry, background/foreground, and return-to-manual-entry paths without faking a
camera success.

The equivalent command-line form is:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project /Users/ryujou/Maurya/ios/App/Maurya.xcodeproj \
  -scheme MauryaUI \
  -configuration Debug \
  -destination 'platform=iOS,id=YOUR_IPAD_UDID' \
  -parallel-testing-enabled NO \
  -only-testing:MauryaUITests/MauryaUITests/testIPadProLandscapeKeepsSidebarAndMajorRoutesUsable \
  -only-testing:MauryaUITests/MauryaUITests/testScannerUnavailableRemainsRecoverableAcrossLandscapeAndLifecycle \
  -allowProvisioningUpdates
```

Find the connected identifier with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun devicectl list devices
```

## 3. Manual iPad landscape matrix

Run every row in both landscape directions. Repeat the core rows in a half-width
Split View or resized Stage Manager window because the app does not require
full-screen operation.

| Area | Required observation |
|---|---|
| Root navigation | A persistent sidebar is visible at regular width; selecting Devices, Resources, Effects, Editor, Analysis, Playback, Share, OTA, Guide, and Privacy updates the detail column without losing the sidebar. |
| Device detail | Console, Characters, Help, and Effects are four visible segmented choices; connect, reconnect, refresh, disconnect, telemetry, all-seven-groups, and support-color actions remain reachable. |
| Resources | Group logos and character avatars display; search for `美竹兰`; add/edit a custom palette; rotate, reset, extract candidate colors, save, delete, undo, import, and export. |
| Effects/editor | Open both Blockly and Script programs; focus an editor field so the software keyboard is visible; verify Save and Run remain reachable; preview, format, undo, and redo remain available from Editor tools. |
| Playback/analysis | Start only with a connected compatible device; verify microphone denial is explained, motion/audio input status is visible, pause/resume/stop work, and rotating does not restart or falsely report success. |
| Share | Manual token entry works; QR scanner fills the entire iPad; rotate while scanning; background and return; camera unavailable shows Retry and Cancel; Cancel returns to manual input. |
| OTA | Without configured production URL/key, Start remains disabled. With approved test firmware, verify progress, cancel, resume, commit, reconnect, and version confirmation in landscape. |
| Accessibility | Test largest text, VoiceOver focus order, Differentiate Without Color, Reduce Motion, external keyboard, and pointer/trackpad operation. |

## 4. Physical hardware evidence

Record the following for each run:

- source commit and whether the worktree has local changes;
- iPad model, iPadOS version, orientation, and window mode;
- ESP32 firmware version and 7×6 pixel layout;
- permission decisions for Bluetooth, Camera, Microphone, and Motion;
- screen recording or screenshots plus the Xcode test result bundle;
- BLE disconnect/reconnect behavior and any console errors;
- for endurance, 20 Hz pixel playback duration, frame loss, battery change,
  temperature/thermal state, and final cleanup state.

Simulator success does not replace physical Bluetooth, camera, microphone,
motion, pressure/proximity, energy, or OTA recovery evidence.

## 5. Read-only physical BLE checks

Use the `MauryaBLE` scheme for the two explicitly physical tests. They run the
real composition root, skip on Simulator, and never press a device write,
playback, diagnostics-clear, or OTA control:

- `testPhysicalBluetoothDiscoveryWhenExplicitlyEnabled`
- `testPhysicalBluetoothConnectsAndReadsSnapshotWithoutWriting`

The second test requires the lamp to be powered on and nearby. Passing means the
app discovered the peripheral, completed GATT setup, read a configuration/group/
diagnostics snapshot and device info, captured evidence, and disconnected. It
does not validate writes or lighting output.

## Apple references

- [Running your app on simulated or physical devices](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices)
- [Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- [Configuring the environment of a simulated device](https://developer.apple.com/documentation/xcode/configuring-a-simulator-for-your-environment)
