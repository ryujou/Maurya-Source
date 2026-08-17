# Maurya iOS threat model

Review date: 2026-08-09
Source baseline: `56709f15cc0173d2c8b28fad8db68b7f48396844`

This document is a Phase 12 security boundary, not a release approval. It must
be revalidated against the exact signed archive, firmware, backend, AASA, and
production keys.

## Assets and trust boundaries

| Asset | Trust boundary | Required property |
|---|---|---|
| Device configuration and live pixels | iPhone ↔ unauthenticated BLE radio ↔ ESP32 | Bounded parsing, unit/function matching, connection generation, no stale success |
| Effect programs and editor state | Swift domain ↔ local WKWebView bundle | Fixed bundle hash, versioned schema, nonce/request ID, bounded messages, no external code/navigation |
| Microphone and motion samples | Apple sensor callbacks ↔ analysis actor | User-triggered, memory-only, no payload/log/network path, prompt stop and stale state |
| Custom palettes and avatars | PhotosPicker ↔ WebP codec ↔ Application Support | Explicit selection, bounded decode/encode, atomic index/files, protection/no-backup policy, repair/Undo |
| Shared effects/palettes | App ↔ QR/deep link ↔ HTTPS service ↔ local repositories | Strict token/host/schema/hash/compression/image checks, preview, moderation, atomic import, duplicate marker |
| Firmware and update state | HTTPS/CDN ↔ cache ↔ BLE OTA ↔ bootloader | Pinned key verification, host/schema/size/hash/secureVersion/layout gates, safe resume, commit-once, version confirmation |
| Signing/public-service configuration | Build system/App Store ↔ App bundle | No private key in source/binary, configuration separation, archive/entitlement/privacy reconciliation |

## Adversaries and abuse cases

### Malicious or spoofed BLE peer

- Can advertise the expected name/service, disconnect at every state, fragment,
  coalesce, corrupt, replay, or flood notifications, and return valid-looking
  responses from an old connection generation.
- Controls all device-reported lengths, exceptions, capabilities, status,
  offsets, firmware strings, and geometry until validated.
- Mitigations: service/characteristic/notify readiness gate, with-response MTU
  chunks, one bounded transaction queue, response matcher, CRC/length decoder,
  two-second default timeout, buffer maximum, generation invalidation, explicit
  capability/geometry validation, and fail-closed UI state.
- Residual risk: the current protocol has no cryptographic device identity or
  BLE application-layer authentication. Physical spoofing/MITM must be
  documented and assessed on real devices before release; do not describe the
  connection as authenticated.

### Malicious editor content or Web process

- Can send unknown/duplicate/deep/oversized messages, guess request IDs,
  navigate, open windows, request media, or terminate between save operations.
- Mitigations: offline custom-scheme resources with manifest SHA-256, strict
  CSP/navigation/media denial, nonpersistent data store, isolated page-world
  message handler, version/nonce/request-ID/schema/byte/depth/node/identifier
  limits, fixed dispatcher, handler removal and structured task cancellation,
  debounced atomic autosave and process-reload recovery.
- Residual gate: physical WKWebView keyboard, rotation, accessibility and
  process-termination testing.

### Malicious share input or backend response

- Can provide token confusion, redirects/userinfo/ports, gzip bombs, deep or
  duplicate-key JSON, wrong hash/type/codec, malformed WebP, repeated imports,
  moderation violations, partial domain writes, retry amplification, or
  preview/confirm races.
- Mitigations: a single strict token parser, exact HTTPS host, redirect denial,
  response status/type/declared and actual size bounds, bounded GET backoff,
  no blind POST retry, gzip CRC/ISIZE/expanded-size limits, strict JSON limits,
  canonical hash, WebP structure/hash/size checks, local moderation, preview,
  confirm-time duplicate recheck, atomic consumer contract and compensation.
- Residual gate: production OpenAPI/retention/rate-limit/abuse handling,
  Android↔iOS E2E, AASA lifecycle, privacy classification and runtime capture.

### OTA supply-chain or interruption attacker

- Can replace URLs/manifests/signatures/artifacts, redirect hosts, truncate or
  splice ranges, alter ETag, replay an old secureVersion, lie about offsets,
  disconnect at any chunk, suppress reboot, or return without a new version.
- Mitigations: HTTPS allowlist and final-URL validation, detached RSA-SHA256
  verification with key ID map, strict manifest and compatibility gates,
  actual size/hash verification, bounded 256 KiB Range/If-Range, ETag-safe
  restart, no-backup atomic cache, disk-space reason declaration, checkpoint,
  acknowledged offsets, bounded retry/status recovery, commit once, and
  reconnect+GET_INFO version confirmation. No Release signature bypass or
  private key exists.
- Residual gate: real signing owner/rotation/revocation, staging/CDN behavior,
  physical power-loss/rollback/secureVersion and recovery drills.

### Local filesystem failure or hostile data at rest

- Includes full disk, denied/corrupt files, crash between file/index changes,
  orphan avatars, duplicate/unknown fields, oversized repositories, and
  backup of replaceable cache data.
- Mitigations: strict decoders and count/byte limits, Application Support for
  user data, Caches/no-backup for OTA, atomic replacement, file protection,
  revision checks, corruption quarantine, orphan repair, compensating deletes,
  and session Undo receipts. Fault-injection tests exercise failed writes.
- Residual gate: physical install/upgrade/restore and storage-pressure tests.

### Privacy, logging, and reviewer misuse

- Sensitive values include share tokens/payloads, device contents, PCM, motion
  traces, imported images, signing material, and future production endpoints.
- Mitigations: finite OSLog categories with outcome-only messages; no raw PCM
  persistence/upload/logging; no analytics/ads/ATT; user-triggered permission
  acquisition; system PhotosPicker; no background entitlement; `.invalid`
  Release services and empty OTA key; manifest declares only the disk-space
  API reason used by OTA.
- Residual gate: exact archive strings/binary/domain scan, network capture,
  App Privacy answers, public privacy policy, review hardware/video, and legal
  rights for every distributed asset.

## Security invariants checked in code/tests

1. Every decoder/downloader/bridge/repository has a byte/count/depth or queue
   bound; no remote input selects a Swift selector or executable resource.
2. BLE responses cannot complete a different connection generation or a
   mismatched transaction; cancellation/timeout/disconnect release capacity.
3. Effect compile/execute has node, instruction, iteration, call-depth, list,
   duration, finite-number, target and monotonic deadline checks.
4. Share import cannot bypass preview/validation or leave a successful history
   marker without its domain object; duplicate token checks occur at confirm.
5. OTA cannot send data before manifest/signature/compatibility gates and
   cannot report success before post-reboot version confirmation.
6. Scene suspension stops analysis and pauses playback; the audio callback
   performs bounded work and never waits on its consumer.
7. Release source/config contains no production private key, debug trust
   bypass, arbitrary-load exception, background mode, tracking domain, or
   Associated Domains entitlement.

## Release-blocking evidence still required

- Physical BLE spoof/interruption/soak and two-same-name-device matrix.
- Physical audio/motion/route/camera/WebView/VoiceOver and resource cleanup.
- Signed OTA staging/production supply chain, interruption and rollback.
- Production share/AASA/privacy/abuse E2E and Android↔iOS interop.
- Archive entitlement, required-reason, strings, license, network-domain,
  secret and privacy-label audit.
- Legal approval or removal/replacement for all `reviewRequired` assets.

Any new network domain, entitlement, third-party SDK, wire command, share
field, OTA key/algorithm, sensor input, background behavior, or executable web
content requires updating this threat model before implementation is accepted.
