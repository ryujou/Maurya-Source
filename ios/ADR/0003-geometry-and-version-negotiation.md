# ADR 0003: Geometry, protocol source of truth, and compatibility

- Status: Accepted
- Date: 2026-08-09

## Context

Historical assets and configuration mixed 7×6=42 with 7×10=70. The product
owner confirmed the real current hardware is seven groups of six pixels.

## Decision

- Canonical current geometry is `groupCount=7`, `pixelsPerGroup=6`,
  `pixelCount=42`; a pixel vendor frame is 140 bytes.
- `protocol/maurya-protocol.json` and `protocol/golden-vectors.json` are the
  versioned cross-platform contract for UUIDs, commands, registers, limits,
  geometry, OTA, effects, and known capabilities.
- Clients use device-reported geometry when a future capability defines it.
  Current/legacy firmware without negotiation falls back to exactly 42.
- Dynamic domain models may represent a future bounded geometry, but no
  production source, generated editor bundle, firmware default, or help text
  may infer 70 for current hardware.
- Modbus register requests use the repository contract maximum of 64, not the
  generic Modbus 125/123 limits.

## Consequences

Android editor/APK assets, ESP32 runtime/driver/tests, and iOS codecs consume
or test the same contract. Any geometry or wire change must update schema,
golden vectors, all consumers, compatibility policy, and this ADR together.
