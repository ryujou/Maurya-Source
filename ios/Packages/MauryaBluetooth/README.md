# MauryaBluetooth

Swift 6.2 CoreBluetooth central transport for the Maurya ESP32 GATT profile:

- service `FFE0`
- write-with-response characteristic `FFE1`
- notify/indicate characteristic `FFE2`

The package depends on the sibling `MauryaProtocol` product through the local
`../..` package. CoreBluetooth references stay on `MainActor`; the bounded
transaction queue and incremental Modbus decoder live behind an actor. A pure
state reducer rejects callbacks from stale connection generations.

## Integration requirements

The application target must provide `NSBluetoothAlwaysUsageDescription`.
If background central behavior is approved by the Phase 0/App Review gate, it
must also add `bluetooth-central` to `UIBackgroundModes`. Foreground scanning may
use the Maurya name fallback because some firmware advertisements omit FFE0;
background scans must specify FFE0.

State restoration is disabled by default. Supplying a restoration identifier
without the `bluetooth-central` background mode is an invalid CoreBluetooth
configuration and terminates the application; the foreground-only Maurya app
therefore leaves the identifier `nil`.

Call `close()` during explicit transport teardown. User-initiated disconnects do
not reconnect; unexpected disconnects use capped exponential backoff up to 45
seconds. `ready` is emitted only after service discovery, both characteristic
checks, and confirmed FFE2 notification subscription.

## Hardware Gate — not yet passed

The package's pure and package-level tests do **not** prove physical BLE behavior.
Gate P3 remains open until an iPhone and a real Maurya ESP32 demonstrate:

- permission denial and Settings recovery;
- Bluetooth off/on and device power loss during every connection phase;
- 1,000 serialized requests with no deadlock or crossed response;
- 20 Hz notification/frame traffic for at least 30 minutes;
- write fragmentation using the negotiated `maximumWriteValueLength`;
- lock-screen/background behavior under the approved entitlements;
- two same-name devices remaining distinguishable by peripheral UUID;
- Instruments/Memory Graph showing no retained peripheral, delegate, task, or
  continuation leak.

No simulator, mock, or macOS package test may be reported as satisfying this
hardware gate.
