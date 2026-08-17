# Maurya wire protocol schema

This directory is the machine-readable Phase 0/Phase 2 handoff for Android,
iOS, firmware, editor tooling, and CI. It records only facts supported by the
current Android and ESP32 source, plus the owner-confirmed production geometry
of **7 groups × 6 pixels = 42 pixels**.

## Files

- `maurya-protocol.json` — transport, geometry, Modbus, registers,
  capabilities, Effects, OTA layouts, evidence, and unresolved facts.
- `golden-vectors.json` — byte-exact CRC, Modbus, Effects, OTA, geometry, and
  Android/iOS share canonical JSON, content-hash, gzip, and blob-hash fixtures
  boundary fixtures.
- `validate_protocol.py` — standard-library-only self-consistency and golden
  encoder check.

Run from the repository root:

```sh
python3 protocol/validate_protocol.py
```

No consumer should copy these constants and then maintain a private variant.
Instead, consume the JSON directly or generate platform constants from it.
Generated Swift/Kotlin/C output must be reproducible and verified against
`golden-vectors.json` in that platform's test suite.

## Required consumer behavior

1. Modbus register addresses/counts/values are big-endian; CRC suffix is
   little-endian. Effects/OTA multibyte fields inside vendor payloads are
   little-endian.
2. A vendor frame is `address, 0x41, payloadLength, payload, crcLo, crcHi`.
3. Logical pixel order is group-major. Current valid zero-based indices are
   `0...41`; protocol code must not reverse physical channels.
4. The 42-pixel RGB888 frame is exactly 140 bytes, including Modbus envelope
   and CRC.
5. Unknown capability bits must be preserved/ignored. They must not be named
   or used until both endpoint evidence and an ADR exist.
6. Entries under `unresolved` are deliberate safety boundaries, not omissions
   to fill by guessing.

## Evidence and authority

The schema's `evidence` arrays point to the relevant Android and firmware
implementations. A fact with evidence from both endpoints is stronger than an
old prose document. When endpoints disagree, stop the affected downstream
work, add an unresolved record, and resolve it through the plan's Phase 0
change-control process before updating vectors.

The schema is initially anchored to commit
`56709f15cc0173d2c8b28fad8db68b7f48396844`. Because Phase 0 geometry cleanup
may alter working-tree paths without changing wire bytes, any future update
must change `schemaVersion`, refresh `sourceCommit`, rerun this validator, and
run the platform-specific golden suites before merge.
