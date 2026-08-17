# MauryaResources

Phase 5 core for Maurya's built-in support-color catalog, custom 96×96 WebP avatars, local palettes, Android-compatible backups, and `MauryaShare` palette payloads. Swift owns the domain and persistence layers; the pinned CWebP target supplies the WebP encoder required for Android-compatible custom avatars.

## Built-in inventory

The bundled snapshot is copied without upscaling from Android's `app/src/main/assets/palette` catalog:

- 4 franchises, 55 groups, 505 characters, and 560 uniquely referenced PNG files.
- 11,921,332 bytes of PNG payload (about 11.4 MiB); the Swift package directory is about 13 MiB.
- Largest image dimensions: 320×160. Fully decoding all images simultaneously as 32-bit RGBA would require about 21.0 MiB, so clients should decode on demand and cache with a bounded policy.
- `asset_inventory.json` records stable ID, zh/ja display names, affiliation, support color, resource path, SHA-256, source URLs, and legal status. Runtime validation checks catalog hash, ID parity, duplicate IDs, colors, files, and every image hash.
- `Tools/generate_inventory.rb` deterministically regenerates the inventory from the Android catalog. Run it after intentionally refreshing the mirrored resources, then run the inventory test.

## Personal-use scope and distribution note

These are third-party character, band, project, and virtual-singer identifiers. Inclusion does not imply affiliation or endorsement. The current product decision is a personal, locally installed build, so all 560 mirrored images are enabled and shown in the app; the inventory's conservative `reviewRequired` metadata is not surfaced as a runtime warning and does not block local use.

The Android source notes provide limited provenance for selected THE IDOLM@STER logos (including some Wikimedia `PD-textlogo` claims, while warning that trademark restrictions remain) and state that VOCALOID/virtual-singer rights remain with their owners. Those notes are not a blanket distribution license. If scope later expands to public, commercial, TestFlight, or App Store distribution, the distribution review gate must be reopened before shipping.

## Custom avatars and palettes

`AvatarImageProcessor` decodes the selected image with orientation applied,
supports bounded square crop transforms (pan, zoom, and quarter-turn rotation),
and encodes exactly 96×96 WebP. It searches quality downward until the Android
6,144-byte limit is satisfied, then revalidates dimensions, RIFF structure, and
SHA-256 before returning bytes. The app provides the PhotosPicker/crop UI.

The encoder is the official Google libwebp 1.6.0 source archive from
`downloads.webmproject.org`, pinned by SHA-256
`e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564`.
Its BSD-3-Clause terms are retained at `Sources/CWebP/LICENSE.libwebp` and are
also reproduced in the app's bundled `ThirdPartyNotices.txt` for binary
distribution.

`AvatarValidator` accepts only a structurally bounded RIFF WebP whose declared size matches the bytes, whose first image chunk is `VP8 `, `VP8L`, or `VP8X`, whose dimensions are exactly 96×96, and whose total size is at most 6,144 bytes. It returns codec, dimensions, byte count, and SHA-256 and can verify a supplied hash. This matches the validation surface used by `MauryaShare` and Android's schema-v1 palette backup.

`CustomPaletteRepository` is an actor. It enforces normalized bilingual names (32 Unicode scalar limit), canonical `#RRGGBB`, revision checks, a 50-entry limit, content deduplication, hash-derived avatar filenames, atomic index/avatar writes, orphan cleanup, and delete receipts for current-session Undo. `FileCustomPaletteStorage` accepts an injected root URL; the app should pass an Application Support subdirectory. Tests use isolated temporary directories.

For delete and backup import, the durable index is the commit point. If an old
avatar cannot be removed after that commit, the operation remains successful
and `loadAndRepair()` retries orphan cleanup later; the API never reports a
failed import while the imported entries are already visible.

The schema-v1 backup keys intentionally match Android: `id`, `nameZh`, `nameJa`, `hex`, `createdAt`, `updatedAt`, `avatarWebpBase64`, and `avatarSha256`. Base64, UUID, WebP metadata, size, and hash are validated before repository mutation. `CustomPaletteEntry.makeShareEnvelope` and `CustomPaletteRepository.importShare` bridge the existing `MauryaShare` palette contract.

## Known gates requiring device or release work

- `CGImageSource`/ImageIO decoding of representative `VP8 `, `VP8L`, and `VP8X` files still needs physical-device verification.
- The implemented PhotosPicker/crop/rotate/color-suggestion UI and WebP encoder still require visual crop-parity QA plus a real Android↔iPhone backup round trip.
- File-protection attributes, backup exclusion, low-disk UX, and deletion impact on already-referenced device groups still require release decisions.
- The 11.4 MiB payload and on-demand decode memory must be measured in the final archived app and on the minimum supported physical device; package-level byte arithmetic is not an installed-size measurement.
- No Android device or iPhone round-trip was run in this environment. Compatibility is covered at the shared envelope/backup byte-contract level only.

## Verification

Use the full Xcode developer directory so Swift Testing is available:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test -c debug
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test -c release
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MauryaResources -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO SWIFT_SUPPRESS_WARNINGS=NO
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme MauryaResources -destination 'generic/platform=iOS' -configuration Release build CODE_SIGNING_ALLOWED=NO SWIFT_SUPPRESS_WARNINGS=NO
```

All library and test targets compile with warnings treated as errors and Swift 6 language mode.

### Reproducible host measurement

`bash Tools/measure_host_resources.sh` runs the serialized Release measurement test. On the
arm64 development host (macOS 26.6.1), the 2026-08-09 run measured 560-entry inventory load in
86.726 ms with a 5,160,960-byte resident delta. Ten representative encode/decode/crop/color
iterations had a median decode path of 0.185 ms and a 950,272-byte resident delta. The complete
Swift test runner reported a 27,132,528-byte peak memory footprint; `/usr/bin/time` also reports
its broader 391,774,208-byte maximum resident-set accounting. These are deterministic host-side
engineering measurements, not minimum-device or archived-app acceptance evidence; those release
gates remain open above.
