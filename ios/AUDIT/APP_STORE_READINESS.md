# Maurya iOS App Store readiness audit

Audit date: 2026-08-09 (Asia/Shanghai)

This file is a release gate, not a claim that the app is ready to submit. A
checked item means the repository contains static evidence; hardware, service,
legal and App Store Connect evidence must still be produced for the exact
archive submitted to Apple.

## Current Apple requirements checked

- App Store Connect uploads currently require Xcode 26 or later and an iOS 26
  SDK or later. The project and CI select Xcode 26.6, and the local generic
  device build uses the iOS 26 SDK.
- An iPhone submission needs an accepted 6.9-inch screenshot set. Because
  `TARGETED_DEVICE_FAMILY` is `1,2`, an iPad 13-inch set is also required.
- App Review requires a final, fully functional build and access to non-obvious
  features. Hardware-dependent behavior requires detailed review instructions
  and may require a demo video or the hardware.
- Required-reason APIs must be declared in a privacy manifest with an approved
  reason matching actual use.

Official sources:

- <https://developer.apple.com/news/upcoming-requirements/>
- <https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/>
- <https://developer.apple.com/documentation/BundleResources/describing-use-of-required-reason-api>
- <https://developer.apple.com/app-store/review/guidelines/>
- <https://developer.apple.com/app-store/review/>

## Static repository evidence

| Area | Status | Evidence |
|---|---|---|
| Upload SDK | PASS locally | Xcode 26.6/iOS 26 generic device builds; `.github/workflows/ios-foundation.yml` selects Xcode 26.6. Remote CI has not run because these changes are unpushed. |
| Deployment | PASS statically | iOS 17 minimum, iPhone and iPad families, Swift 6 strict concurrency in `ios/App/Maurya.xcodeproj/project.pbxproj`. |
| App icon | PASS statically | The generated, character-free 1024×1024 opaque `AppIcon` compiles with `actool` for iPhone and iPad and emits the expected primary-icon metadata. Final visual approval remains a product decision. |
| Usage descriptions | PASS statically | Bluetooth, camera, microphone and motion purposes are specific in `ios/App/Config/Info.plist` and correspond to scan/control, share QR scanning, audio effects and motion effects. PhotosPicker uses the system picker and does not request broad Photo Library access. |
| Entitlements/background | PASS statically | No entitlement file, Associated Domains, push, tracking or background modes are enabled. Foreground-only behavior is intentional. |
| Privacy manifest | PASS statically | `ios/App/Resources/PrivacyInfo.xcprivacy` declares no tracking, tracking domains or collected data. It declares the disk-space category with approved reason `E174.1`, matching the bounded OTA downloader's preflight capacity check. |
| Required-reason API scan | PASS for current source | The OTA cache uses `volumeAvailableCapacityForImportantUsageKey` only to check that its firmware artifact can be written, matching `NSPrivacyAccessedAPICategoryDiskSpace` reason `E174.1`. No UserDefaults/AppStorage, system boot time, active-keyboard, or file timestamp API use was found in app and linked local package production Swift sources. Re-scan the exact archive before upload. |
| Network behavior | PARTIAL | Share networking is restricted to HTTPS `xtbang.top`, rejects redirects, and validates responses. OTA validates both the requested URL and URLSession's final URL against HTTPS/allowlist/no-userinfo rules; release configuration is intentionally `.invalid` and has no production key. |
| Third-party notices | PASS statically | Pinned Google libwebp 1.6.0 is BSD-3-Clause; its source license is retained and `ThirdPartyNotices.txt` was verified in the unsigned Release `.app`. Recheck the signed archive. |
| Data collection | PASS only for the current disabled-service build | No analytics, ads, account login, third-party SDK, ATT, location, contacts or remote telemetry implementation is present. Audio and motion are processed on-device and are not saved/uploaded. Release service URLs are `.invalid`; before enabling production sharing, classify the uploaded effect/palette payload and retention under App Privacy/privacy-manifest rules, update the public policy, and capture runtime traffic from the exact archive. |
| Dynamic code | REVIEW | The editor executes an embedded, hash-verified offline JavaScript bundle. It must remain bundled and must not download executable feature code. Review notes should explain that it is a local effect editor for the user's Maurya hardware. |
| Hardware review access | BLOCKED EXTERNALLY | A reviewer needs a supported Maurya device or Apple-approved alternative evidence plus connection/setup instructions and a sample share token/QR. |
| Screenshots | BLOCKED EXTERNALLY | Capture real localized UI from the release candidate: 6.9-inch iPhone and 13-inch iPad, without unavailable OTA/share claims. |
| Privacy policy | BLOCKED EXTERNALLY | A public, accurate privacy-policy URL is not configured. Do not invent one in source. |
| Resource rights | BLOCKED LEGALLY | All 560 mirrored character/group assets remain `reviewRequired`; written distribution rights or replacement/removal is mandatory before submission. |
| Production services | BLOCKED EXTERNALLY | Share staging/OpenAPI/AASA, production OTA endpoint/key/signing service and live backend evidence are absent. Associated Domains must not be enabled until AASA is deployed and verified. |

## Release-candidate procedure

1. Resolve every legal and production-service blocker above.
2. Build an Archive with Xcode 26+ and the iOS 26+ SDK using the final Release
   configuration and production signing identity.
3. Inspect the archive for `PrivacyInfo.xcprivacy`, entitlements, embedded
   frameworks, `ThirdPartyNotices.txt`, usage descriptions and unexpected
   network SDKs.
4. Run on physical iPhone and iPad with a production Maurya device, including
   disconnect/reconnect, 20 Hz playback endurance, OTA recovery, microphone and
   motion permission denial/revocation, and share import/export.
5. Capture runtime network traffic and reconcile it with the privacy manifest,
   App Privacy answers and public privacy policy.
6. Capture the required localized screenshots from that same functional build.
7. Supply App Review notes, hardware/setup access, sample QR/token and a demo
   video where physical review access is impractical.

## App Icon provenance

The current candidate was generated with the built-in image generation tool,
then resized without transparency to the repository path
`ios/App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`.
Its SHA-256 is
`10d253b763ab8e44d7c2458b64d33511c09ec4cac82acba536196a9652f1c317`.

Final prompt:

> Create a premium, geometric iOS icon for a Bluetooth concert-light
> controller: a dark circular controller with exactly seven radial luminous
> bars, each optionally suggesting six segments, on a full-bleed midnight
> indigo background with violet, cyan and a small coral accent. Keep a clean
> small-size silhouette. Use no people, characters, mascots, letters, words,
> numbers, third-party logos, trademarked shapes, watermark, transparency or
> rounded-corner mask.

The generated image is a candidate asset, not a substitute for product-owner
visual approval or the release archive's legal review.
