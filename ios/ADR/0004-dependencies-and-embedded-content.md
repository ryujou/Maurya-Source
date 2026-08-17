# ADR 0004: Dependency and embedded-content policy

- Status: Accepted
- Date: 2026-08-09

## Context

The difficult boundaries are Apple platform APIs, strict concurrency, a local
Web editor, and WebP encoding. A cross-platform UI runtime would not remove
those boundaries and would enlarge privacy, lifecycle, and supply-chain risk.

## Decision

- The product UI is native SwiftUI on Swift 6; CoreBluetooth, AVFAudio,
  Accelerate/CoreMotion, WebKit, Security, URLSession, CoreImage, and
  AVFoundation are used directly behind testable interfaces.
- Feature domains are repository-local Swift packages with warnings-as-errors;
  no remote binary SDK is accepted without license, privacy manifest, network
  domain, maintenance, size, and removal review.
- The sole non-Apple production dependency is pinned Google libwebp 1.6.0,
  built from source under BSD-3-Clause with its license and third-party notice
  bundled in the App.
- The Blockly/script editor is a hash-manifested, offline bundle built from the
  checked-in Android editor source. It cannot download executable code, open
  external navigation, or request web camera/microphone access.

## Consequences

Dependency updates require reproducible hashes, license/privacy re-audit,
Debug/Release package tests, generic iOS builds, final archive inspection, and
an ADR revision when trust or distribution boundaries change.
