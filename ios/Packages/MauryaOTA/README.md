# MauryaOTA

`MauryaOTA` is the Phase 9 security and orchestration boundary for iOS 17+.
It depends on the existing `MauryaProtocol`, `MauryaDevice`, and
`MauryaBluetooth` contracts, while keeping network, BLE, signature keys, and
checkpoint storage injectable for deterministic tests.

## Implemented boundary

- Fetches the signed manifest and artifact only over HTTPS and only from an
  explicit host allowlist. The production URLSession client uses normal ATS/TLS
  validation; there is no trust-all delegate or insecure transport fallback.
- Verifies the exact manifest bytes with a versioned RSA public key using
  `SecKeyVerifySignature` and RSA PKCS#1 v1.5 SHA-256, matching
  `tools/build_ota_release.py`. It then validates schema, app version, variant,
  layout, asset pack, BLE capability, monotonic secure version, size, URL, and
  SHA-256 before sending firmware bytes.
- Drives BLE BEGIN/DATA/STATUS/COMMIT/CANCEL as an actor. Firmware chunk size is
  `min(118, adapter write capacity)`. Every acknowledgement is checked and
  persisted. Retry/reconnect/poll counts are bounded and cancellation remains
  cooperative.
- Resumes only when device identity, target version, secure version, artifact
  size, SHA-256, ETag, live device state, expected byte count, and confirmed
  offset agree. The live device offset is authoritative when it is behind,
  equal to, or ahead of the local checkpoint; otherwise BEGIN safely restarts
  at byte zero.
- Persists distinct verified, COMMIT-outcome-unknown, and COMMIT-confirmed
  states. The ambiguous state is written before COMMIT because a successful
  reboot can race the response; a definite pre-send failure restores verified
  so a later workflow can retry. Success is emitted only after reconnecting and
  reading the target firmware version back from GET_INFO.
- Provides an atomic JSON checkpoint store. The app should place this directory
  under Application Support/no-backup. `URLSessionOTAClient` owns a no-backup
  file cache, checks available disk capacity, downloads in bounded Range chunks,
  resumes only with `If-Range`/ETag, safely restarts for HTTP 200 fallback, 416,
  missing validators, or changed validators, and atomically promotes the final
  artifact before returning it for manifest size/hash validation.

`PREPARE (0x02)` is intentionally separate: firmware stores its 16-byte nonce
and reboots into the legacy Wi-Fi SoftAP path. The BLE workflow must use
`BLE_BEGIN (0x10)`, whose size/layout/SHA-256 fields are its preparation gate.
Calling PREPARE before BLE_BEGIN would disconnect and switch transport modes.

## Integration and background limits

The app must provide an `OTADeviceTransport` adapter around the real
`MauryaCentralTransport`, including its current safe firmware payload capacity
and a bounded reconnect operation. The package never starts an unbounded task,
claims fixed-rate BLE execution in the background, or treats background runtime
as guaranteed. On suspension/expiration the app cancels its structured task and
keeps the checkpoint; foreground reconciliation calls `run` again. Any
`bluetooth-central` entitlement and state-restoration behavior remains an app
target/App Review decision with real-device evidence.

## Release gates (not satisfied by unit tests)

This package does not embed a production public key, private key, signing
bypass, server success, or hardware success. Before Phase 9 can close:

1. The release service must protect the private RSA key, publish the exact
   signed manifest/artifact pair, and provide a versioned production public-key
   set to `RSASHA256ManifestVerifier`. Private keys must never enter the app or
   repository.
2. The production server/CDN must be exercised against the Range/ETag client in
   staging, including network changes, 200 fallback, 416, and validator changes.
3. Real ESP32-C3 hardware must pass repeated successful updates, sampled chunk
   boundary power loss/disconnects, resume, cancel, commit response loss, failure
   recovery, and post-reboot GET_INFO version confirmation.
4. Debug and Release builds must retain signature/hash/secure-version/layout
   hard failures. There is no supported skip switch.

## Verification

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -c debug
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -c release
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme MauryaOTA -destination 'generic/platform=iOS' build
```

Tests use fake network, transport, and checkpoint actors. They cover the happy
path, signature/hash/host/layout/rollback failures, chunk capacity and bad ACK,
lost-ACK recovery, persisted resume, device verification failure and timeout,
behind/equal/ahead live-offset reconciliation, two-workflow pre-send and lost
COMMIT-response recovery, commit/reconnect/version confirmation, and real
Security.framework RSA fixture verification. They do not claim server or
hardware Gate completion.
