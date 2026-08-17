# ADR 0002: Foreground-first playback and lifecycle policy

- Status: Accepted for the current release candidate
- Date: 2026-08-09

## Context

Android uses a foreground service, microphone service type, notification, and
wakelock. iOS does not promise a continuously scheduled 10/20 Hz timer merely
because a BLE central or audio session exists. Copying Android's mechanism
would create an unreliable product claim and an App Review risk.

## Decision

- Real-time group/pixel playback is foreground-only by default.
- Leaving a screen does not stop an active session, but scene inactive or
  background pauses it, ends the current BLE session best-effort, and stops
  audio/motion acquisition.
- Returning to foreground requires an explicit user resume and a new
  capability/geometry negotiation plus BEGIN.
- The Release target declares neither `bluetooth-central` nor `audio`
  background mode and supplies no restoration identifier.
- CoreBluetooth restoration support remains injectable in the transport for a
  future, separately approved experiment; its delegate selector is exposed
  only when an identifier is configured.
- No UI may describe fixed-rate background playback as supported.

## Consequences and gate

Foreground behavior can be locally tested. Any future background mode requires
a user setting, visible state, energy disclosure, disable control, physical
lock-screen/interruption/force-quit evidence, privacy reconciliation, and a new
ADR revision before entitlement changes.
