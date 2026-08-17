# MauryaPlayback

Structured-concurrency playback for volatile ESP32 effect sessions. The caller owns and awaits `run`; cancellation, pause, disconnect, END, and input cleanup all converge on one bounded cleanup path. There is no detached task, busy loop, unbounded stream, or simulated hardware claim.

The scheduler uses monotonic absolute deadlines. Group frames target 10 Hz, pixel frames target 20 Hz, heartbeat targets 1 Hz (well before the firmware's 5 s volatile-session timeout), and only one transport request can be in flight. Late intermediate frames are coalesced rather than queued. Every frame sequence must be echoed by the acknowledgement. Current 42-pixel RGB888 requests are exactly 140 bytes on the wire; seven-group frames use the protocol's group layout.

Required runtime inputs follow Android's one-second startup grace period. At
exactly 1,000 ms an available sample last updated at 0 ms is still accepted;
after that strict boundary, any unavailable or stale required input fails with
the typed `PlaybackError.staleRequiredInputs`, then runs the normal input/END
cleanup path. Tests use the virtual monotonic playback clock, so this boundary
is verified without sleeping or depending on scheduler timing.

Disconnect recovery freezes effect elapsed time from link loss through the new
BEGIN acknowledgement. Input providers are prepared again, and the one-second
required-input warm-up restarts at that acknowledgement, preventing both an
effect timeline jump and immediate reuse of stale pre-disconnect samples.

## Lifecycle policy

Foreground operation is supported. Inactive/background defaults to pause without promising continued heartbeat or 20 Hz BLE scheduling; foreground return requires explicit resume and refreshes capability/geometry before a new BEGIN. Experimental audio continuation additionally requires a user setting, approved Release background mode, visible status, energy disclosure, and a disable control. BLE background events may help recovery but do not provide a fixed-rate execution guarantee. Force-quit, Low Power Mode, and serious/critical thermal handling belong to the app lifecycle integration and must degrade to pause/stop.

## Build verification

The package passes Debug Swift Testing, Release warnings-as-errors, and a code-signing-disabled generic iOS build with the full Xcode toolchain. The generic build was verified with `SWIFT_SUPPRESS_WARNINGS=NO` against `generic/platform=iOS`; it is not blocked by the Command Line Tools-only developer selection when `DEVELOPER_DIR` points to the installed Xcode application.

## Gates before product claims

- Run foreground group and pixel playback for two hours and verify bounded memory, drift, cleanup, and acknowledged-rate metrics.
- Run a 20 Hz pixel effect for 30 minutes on physical hardware while recording achieved rate, coalesced frames, reconnect time, battery delta, thermal state, and device temperature.
- For any background experiment, test locked and app-switched for 30 minutes, calls, audio-route removal, Low Power Mode, and thermal pressure on a physical iPhone.
- Confirm microphone/motion providers stop and the microphone indicator disappears after every stop, cancel, disconnect failure, and lifecycle interruption.
- Do not advertise continuous background playback until energy measurements and App Review risk are approved.
