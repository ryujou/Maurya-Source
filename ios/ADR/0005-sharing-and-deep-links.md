# ADR 0005: Sharing service, QR, and deep-link trust boundary

- Status: Accepted locally; production activation externally gated
- Date: 2026-08-09

## Context

The repository contains client contracts but no authoritative production
OpenAPI, retention policy, staging ownership, rate-limit contract, or deployed
AASA evidence. Import data is untrusted and may contain compressed or image
payloads.

## Decision

- Share bytes use the Android-compatible canonical envelope, gzip and SHA-256
  contract with strict size, depth, entry, duplicate-key, WebP, moderation,
  and version validation before domain writes.
- Only `https://xtbang.top` is accepted by the production client contract;
  redirects, userinfo, ports, unexpected types/statuses, and unbounded retries
  are rejected. POST is not blindly retried; GET retry is finite.
- QR/scanned/custom-scheme/Universal-Link inputs all pass the same strict token
  parser and always enter preview. They never overwrite local data directly.
- Domain data and the unique token marker are one consumer transaction;
  confirm repeats duplicate detection to close preview/confirm races.
- Release remains configured to `.invalid` and has no Associated Domains
  entitlement until staging/OpenAPI/AASA and privacy/retention evidence exist.

## Consequences and gate

Local codecs, malicious input, QR, history, and transaction failure can be
tested without a server. Production activation additionally requires
Android↔iOS E2E, real camera, cold/hot install-link tests, public policy and App
Privacy classification, service owner, monitoring, and expiry/abuse evidence.
