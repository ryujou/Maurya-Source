# ADR 0006: OTA trust chain and release signing

- Status: Accepted locally; production credentials externally gated
- Date: 2026-08-09

## Context

Firmware replacement is a supply-chain boundary. A successful BLE write is
not proof of a valid update, and PREPARE has different restart semantics from
the direct BLE path.

## Decision

- Stable/channel manifest and detached signature are fetched only from an
  HTTPS allowlist. RSA-SHA256 verification uses versioned pinned public keys;
  schema, variant, app/layout/assets compatibility, size, SHA-256 and
  secureVersion are hard gates with no Release bypass.
- Direct BLE OTA sends BLE_BEGIN(size/layout/hash), bounded DATA chunks,
  STATUS/recovery, COMMIT once, and only declares success after reconnect and
  GET_INFO confirms the new version. Wi-Fi PREPARE is a separate API and is
  never inserted into the direct BLE path.
- Artifacts use no-backup Caches storage, a 256 KiB bounded Range/If-Range
  downloader, ETag-safe restart, capacity check, atomic final replacement, and
  a persisted checkpoint. Explicit cancel sends BLE_CANCEL; lifecycle
  cancellation preserves a resumable checkpoint.
- Release configuration contains no private signing key and defaults to an
  invalid endpoint/empty production public-key input. Private keys must never
  enter the app or repository.

## Consequences and gate

Protocol/security/fault paths are locally testable. Production completion
requires controlled key ownership/rotation, signed staging and production
artifacts, CDN Range behavior, physical ESP32 success/interruption/rollback,
secureVersion downgrade tests, and App signing/archive records.
