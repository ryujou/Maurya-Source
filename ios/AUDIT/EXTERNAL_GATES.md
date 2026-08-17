# External gate register

Updated: 2026-08-09 (Asia/Shanghai)

This register contains evidence that cannot be manufactured from the local
repository. An unassigned named person is itself a blocker: the role shown
below must nominate an accountable person before the due milestone. No row is
closed by unit tests, simulator screenshots, or an App Review approval alone.

Current product scope is a personal, locally installed build and explicitly
excludes TestFlight and App Store distribution. `ASSET-RIGHTS`,
`PRIVACY-POLICY`, and `STORE-REVIEW` therefore do not block that local-use
scope. They become active again before any public, commercial, TestFlight, or
App Store distribution; this scope decision is not a statement that third-party
rights were granted.

| Gate | Required evidence | Accountable role | Due milestone | Downstream work prohibited while open |
|---|---|---|---|---|
| HW-42 | Photograph/video and routing log proving all 42 physical pixels map as seven groups of six on production hardware | Hardware owner | Before hardware release candidate | Pixel-effect compatibility claim and production firmware release |
| BLE-ENDURANCE | Physical iPhone/ESP32 scan, permission denial/recovery, MTU fragmentation, 1,000 transactions, disconnect/reconnect, and 20 Hz pixel playback for 30 minutes with rate, loss, thermal and battery data | iOS QA + firmware QA | Before TestFlight external testing | Background claims, performance sign-off and App Store submission |
| ANALYSIS-DEVICE | Microphone routes/sample-rate changes/interruption, proximity, pressure, motion and Android comparison captures on supported iPhones | iOS QA | Before TestFlight external testing | Claim that real sensor/audio effects are Android-equivalent |
| WEBP-E2E | Android→iPhone and iPhone→Android import/export using real PhotosPicker input, crop/rotation, 96×96 WebP and backup envelopes | Cross-platform QA | Before release candidate | Share/custom-palette interoperability claim |
| EDITOR-DEVICE | Physical iPhone/iPad keyboard, WebView recovery, VoiceOver and largest Dynamic Type journeys | Accessibility QA | Before release candidate | Phase P7/P11 closure |
| SHARE-SERVICE | Authoritative OpenAPI, staging endpoint, rate/error/retention/abuse policy, deployed AASA, install-state Universal Link tests and Android/iOS E2E | Backend owner + privacy owner | Before enabling a non-`.invalid` Share endpoint | Associated Domains, production sharing and related privacy-label answers |
| OTA-TRUST | Named private-key custodian, rotation/revocation procedure, signed staging artifact, CDN Range/ETag evidence, physical update/power-loss/resume/rollback/downgrade tests | Security owner + firmware release owner | Before configuring a production OTA URL/key | Production OTA and firmware release |
| ASSET-RIGHTS | Written distribution status for every one of the 560 mirrored assets, or replacement/removal of every unapproved asset | Legal/content owner | Before any public/TestFlight/App Store distribution; waived for the current personal local-use build | Public, commercial, TestFlight, or App Store distribution only |
| APP-IDENTITY | Apple Developer Team, final App ID/bundle ID ownership, signing roles and provisioning records | Release owner | Before first signed archive | Signed archive, TestFlight and App Store Connect setup |
| PRIVACY-POLICY | Public policy URL matching final network behavior, retention, support contact and App Privacy answers | Privacy/legal owner | Before App Store metadata submission | App Store submission and production Share activation |
| STORE-REVIEW | Localized 6.9-inch iPhone and 13-inch iPad screenshots, review notes, hardware/setup access or demo video, support/marketing URLs | Product/release owner | Before App Store submission | Submission to App Review |
| CI-FIRST-RUN | Successful GitHub Actions run from the committed tree using the pinned macOS/Xcode runner | Repository maintainer | Before merging the iOS release branch | Treating local test evidence as merge evidence |

## Closure rule

Each closure record must include the exact source commit and app/firmware build,
device/OS identifiers, date, raw logs or media location, reviewer, and result.
If hardware, endpoint, signing input, asset set, privacy behavior, or release
configuration changes, the affected evidence expires and the row reopens.
