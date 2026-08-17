# MauryaAnalysis

Swift 6 input and analysis layer for Maurya Phase 6. This package is the only
filesystem scope of this slice and depends on the existing `MauryaEffects`
package for the Android-compatible 22-key runtime schema.

## Implemented

- `AnalysisInputHub`, an actor that aggregates physical samples and per-key
  virtual overrides into `Sendable` snapshots. Each sample carries a monotonic
  timestamp, availability, permission state, and strict Android-compatible
  `> 1,000 ms` stale semantics. Snapshot streams use bounded
  `.bufferingNewest` storage and remove their continuation on cancellation.
  While proximity or pressure remains actively registered, an existing valid
  on-change sample receives a freshness lease on snapshot just like Android;
  the hub never invents a value for a sensor that has not produced one. Light
  remains unsupported and is never leased.
- Pure 16 kHz mono/512-sample PCM analysis matching Android commit
  `56709f15cc0173d2c8b28fad8db68b7f48396844`: Hann window, RMS, peak,
  40–250 Hz bass, 250–2,000 Hz mid, 2,000–7,500 Hz treble, adaptive beat
  threshold, 240 ms refractory period, eight-interval BPM, and 40–240 BPM
  clamping. PCM is never persisted, uploaded, or logged.
- Pure motion replay logic for normalized acceleration, motion, shake,
  gyroscope, pitch/roll/yaw, heading wrapping, attitude zeroing, Core Motion
  pressure conversion from kPa to Android hPa, and proximity mapping. The iOS
  accelerometer reaction-force axes are negated to match the Android fixture's
  gravity convention. Ambient light remains unavailable because public iOS
  APIs expose no general lux sensor; proximity and barometric pressure are
  subscribed only when required and remain overridable.
- Conditional iOS providers for `AVAudioEngine` and `CMMotionManager`. They
  subscribe only to required inputs, use bounded streams/ring storage, stop on
  cancellation, and expose interruption/route loss as unavailable/stale data.
  The audio tap uses the hardware's native noninterleaved Float32 format,
  averages every channel to mono without allocating on the realtime callback,
  and resamples on the analysis worker to 16 kHz. A route change removes the
  old tap and automatically rebuilds the engine/resampler from the new native
  format. Interruption recovery occurs only when `.shouldResume` is present and
  the original session is still requested.

The fixed-capacity realtime PCM ring stores its mutable state in
`OSAllocatedUnfairLock`. Its audio-callback write uses `withLockIfAvailable`
and drops that bounded chunk on contention, so the callback never waits for
analysis or reaches actor-isolated state. Two private `@unchecked Sendable`
pointer wrappers have a narrow synchronous lifetime: the lock closure neither
stores nor returns AVAudioPCMBuffer-owned channel pointers.

## Permissions and lifecycle contract

The App target now supplies the microphone/motion usage descriptions and owns
these providers through its analysis service. The package itself still does
not mutate plist or entitlement state. The integration must continue to obey:

- Keep clear `NSMicrophoneUsageDescription` and `NSMotionUsageDescription`
  strings. Starting capture without the microphone key crashes; the audio
  provider requests permission only from its explicit `start()` call.
- Use one app-level `CoreMotionInputProvider`/`CMMotionManager`. Call `stop()`
  when playback stops, the owning page disappears, or required inputs change.
- Do not activate audio at app launch. The provider activates only when an
  audio-reactive effect starts and deactivates with
  `.notifyOthersOnDeactivation`.
- No continuous background operation is promised. Without an approved Phase 8
  `audio` background-mode experiment, the app must stop these providers on
  background entry. Adding `UIBackgroundModes=audio` requires a real user
  setting, visible microphone state, energy disclosure, a disable control, and
  App Review justification. Core Motion alone does not grant background CPU.

## Hardware, permission, and energy gates

Package tests cover pure logic and do not close these gates. On physical iPhone
hardware, verify all of the following before integration or release:

1. Grant, deny, and revoke microphone/motion permission; confirm denied inputs
   become unavailable/stale and virtual overrides still run effects.
2. Replay recorded stationary, single-axis rotation, shake, and known-attitude
   traces against Android, confirming axis signs on portrait/landscape devices.
3. Test built-in mic, wired/USB input, Bluetooth HFP, route sampling-rate
   changes, headset removal, phone-call/alarm interruption, and recommended vs
   non-recommended resume paths. Confirm the old converter/tap is never reused.
4. Run silence, sweep, impulse, pink-noise, clipped, and Android PCM/WAV golden
   fixtures. Set tolerances from measured device results, not convenience.
5. Run for 60 minutes while measuring ring occupancy, dropped samples, CPU,
   memory, battery drain, thermal state, and UI/frame latency. Confirm stopping
   removes the microphone indicator and sensor updates immediately.
6. Only in Phase 8's separately approved background experiment: repeat locked
   and backgrounded 30-minute runs, interruption and force-quit checks. Do not
   turn those results into a guarantee of fixed-rate background execution.

## Validation

Warnings are errors for source and test targets. The local package dependency
also uses `-warnings-as-errors`; Xcode 17 otherwise suppresses dependency
warnings, so the generic build explicitly disables that suppression.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --package-path ios/Packages/MauryaAnalysis -c debug

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --package-path ios/Packages/MauryaAnalysis -c release

cd ios/Packages/MauryaAnalysis
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme MauryaAnalysis -configuration Debug \
    -destination 'generic/platform=iOS' \
    -derivedDataPath /tmp/maurya-analysis-debug \
    CODE_SIGNING_ALLOWED=NO SWIFT_SUPPRESS_WARNINGS=NO build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme MauryaAnalysis -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath /tmp/maurya-analysis-release \
    CODE_SIGNING_ALLOWED=NO SWIFT_SUPPRESS_WARNINGS=NO build
```
