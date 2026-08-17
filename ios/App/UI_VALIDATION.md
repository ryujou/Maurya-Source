# UI and Snapshot Validation Strategy

This file defines the Phase 1/11 UI evidence that must be produced before the
UI gate is closed. Unit tests and generic builds do not substitute for it.

## Automated journeys

`MauryaUITests` launches a deterministic offline composition with the private
`-maurya-ui-testing` argument. Eleven executable journeys now cover launch, typed
navigation, fail-closed OTA production gates, offline privacy/legal disclosure,
populated resources and effects, editor autosave recovery and controls, share
preview/confirm-failure/cancellation, scanner lifecycle recovery, light/dark
appearance, Simplified Chinese launch, a largest-text / RTL no-crash launch, and
largest text with Differentiate Without Color. The
resource journey verifies compact rows backed by the real 560-image package and
captures the visible role/group avatars. The composition reports hardware and
production services as unavailable; it never simulates BLE, OTA, or server
success and cannot be entered from production UI.

On 2026-08-09 the final compact regression passed on iPhone 17 Pro (iOS 26.5
simulator): 62 logical tests / 81 executions, 0 failed; the iPad-only landscape
journey was skipped once by its explicit device-size gate. The final full iPad
Pro 13-inch (M5) run on iOS 26.3.1 passed 60 logical tests / 79 executions with
0 failures. Its deterministic 1376×1032-point landscape journey kept the adaptive
sidebar visible while exercising populated resources/effects, editor keyboard
input with reachable Save, analysis, playback, share, and fail-closed OTA.
Editor load/edit/save/run process recovery beyond the deterministic autosave
restore, real permission-denial sheets, and hardware success still need dedicated
manual/device evidence.

## Snapshot matrix

The current reviewed-input captures and `xcresulttool` manifests live under
`VisualBaselines/iPhone17Pro` and `VisualBaselines/iPadPro13`. They include scan,
OTA fail-closed, populated resource/effect views, editor recovery, share preview
and failure, dark appearance, plus largest-text RTL. The reviewed iPad final set
contains three upright 2752×2064 captures for landscape resources/split view,
editor with software keyboard, and fail-closed OTA. These files are
evidence captures, not an automatic pixel-diff oracle.

Increase Contrast, Reduce Transparency, and every physical device/editor/import
interaction remain in the manual matrix. Landscape, Reduce Motion, and
Differentiate Without Color now have deterministic layout coverage, but still
need physical visual/accessibility review.
Baselines must be reviewed rather than blindly re-recorded.

## Manual accessibility and hardware evidence

Before Phase 11 closes, run Accessibility Inspector and VoiceOver through every
journey in Simplified Chinese and Japanese, including external keyboard and iPad
pointer operation. Phase 13 separately requires physical iPhone/iPad and ESP32
evidence. This document is the strategy only; no unexecuted row is a pass.
