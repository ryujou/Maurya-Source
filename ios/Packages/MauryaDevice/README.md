# MauryaDevice

Pure, Sendable device-domain models and register/runtime behavior for Phase 4.
The package maps the Android and firmware schema for seven groups, parses device
information/capabilities, limits every register request to the schema maximum of
64 registers, and provides an actor-isolated repository over an injected async
transport.

It intentionally contains no SwiftUI screen, no `CBPeripheral`, and no simulated
hardware. The app may adapt `MauryaCentralTransport` to `DeviceTransport` at its
composition boundary; tests use deterministic protocol transports only.

## Hardware gate

Package tests and generic iOS builds validate only pure behavior. Gate P4 still
requires a real Maurya ESP32 to verify seven-group read/write parity, disconnects
during writes, queue behavior under fast slider input, telemetry values, and the
UI/accessibility matrix. None of those hardware or UI checks are claimed here.

The package currently passes Debug and Release builds with
`-warnings-as-errors`, all Swift Testing suites, and a code-signing-disabled
generic iOS 17 device build. The local shell's selected developer directory is
Command Line Tools, so verification commands must set `DEVELOPER_DIR` to the
installed Xcode without changing the machine-wide selection.
