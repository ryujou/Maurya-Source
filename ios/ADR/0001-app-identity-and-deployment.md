# ADR 0001: App identity and deployment baseline

- Status: Accepted and updated for the integrated local implementation
- Date: 2026-08-08

## Context

The iOS port needs an independently buildable application target without coupling the shell to the repository-level Swift package work. Phase 0 release ownership, signing, production endpoints, Associated Domains, and hardware gates remain open.

## Decision

- Product name: `Maurya`
- Bundle identifier: `com.ryujou.Maurya`
- Deployment target: iOS 17.0
- Devices: iPhone and iPad
- Language mode: Swift 6 with complete strict-concurrency checking
- Localizations: Simplified Chinese (`zh-Hans`), Japanese (`ja`), and English (`en`) as fallback
- Configurations: Debug, Staging, and Release; endpoint and log-level values are configuration inputs
- Signing baseline: unsigned generic-device builds must succeed with `CODE_SIGNING_ALLOWED=NO`; no Team is selected
- Dependency policy: Apple SDKs plus repository-local Swift packages; integrations enter through app-owned protocols
- Navigation: SwiftUI `NavigationStack` with typed scan-root, device-detail, and share-import routes; the custom `maurya://` scheme is parser-tested

The App declares Bluetooth, camera, microphone, and motion usage descriptions,
but no background mode, tracking, Associated Domains, or production service
credential. BLE, OTA, sharing, effects, palettes, and device control are now
locally integrated and remain fail-closed when their hardware or production
configuration is unavailable.

## Consequences

Placeholder service URLs use the reserved `.invalid` domain and cannot be
mistaken for production configuration. App Store signing, Universal Links,
production endpoints, hardware validation, and release capabilities remain
external gates governed by the later ADRs.
