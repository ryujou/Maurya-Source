# MauryaEffects pure core

Standalone Swift 6 package for the deterministic, platform-independent part
of Maurya's Effects runtime. The implementation is based on these Android
sources at baseline commit `56709f15cc0173d2c8b28fad8db68b7f48396844`:

- `EffectProgram.kt`
- `EffectRuntime.kt`
- the pure builtin paths in `EffectInterpreter.kt`
- `EffectAlgorithmsTest.kt`
- the colour round-trip expectation in `PixelEffectTest.kt`

The package has no third-party dependencies. Public values are `Sendable`, and
all mutable random state is held in a value type rather than shared globally.

## Implemented in this slice

- Android-compatible raw identifiers for all 22 runtime input keys and all 60
  builtin names.
- Runtime number, boolean, colour, target, and list value types.
- Per-input value, availability, timestamp, default, and stale semantics.
- Xorshift deterministic random generator, including zero-seed fallback and
  JVM `Long` bit behavior.
- Pure numeric builtins: arithmetic helpers, mapping, interpolation,
  smoothstep, smootherstep, easing, waves, cycle/beat/bar phase, deadzone,
  value noise, and four-octave fBm.
- HSV/RGB conversion using Android's truncation behavior; RGB/HSV mixing,
  palette interpolation, hue/saturation/value adjustments, and seeded random
  colour generation.
- Pure list patterns: mirror, rotation, center spread/contract, chase, and
  seven-position wave.
- Strongly typed, recursive, `Sendable` expression/target/operation/function
  AST and compiled-program/frame models.
- A pure Swift Blockly JSON compiler covering every statement and expression
  type in the current Android `EffectCompiler.kt` and `effect_editor/src/main.ts`
  catalogs: functions, variables, control flow, lists/patterns, algorithms,
  runtime inputs, dynamic colour/HSV, and group/pixel targets. It enforces
  block/variable/depth/type/range
  limits, pixel-mode conflicts, loop-tail observability, finite-duration
  analysis, required-input collection, unreachable-code rejection, and
  Android schema- and byte-compatible canonical AST/SHA-256 identity for the
  shared strongly typed AST and covered finite-number forms.
- A Maurya Script lexer, recursive-descent parser, and typed compiler covering
  effect/function declarations, group and 42-pixel targets, colour/HSV/fade,
  variables and homogeneous lists, value/flow functions, both for syntaxes,
  if/else/while/repeat/forever/break/continue, runtime inputs, expression
  precedence, and all Android builtin signatures. Unsupported syntax is an
  error; syntax and semantic diagnostics retain Android-compatible UTF-16
  source spans and columns, including supplementary-plane Unicode.
- A deterministic Script formatter that emits parseable source for the typed
  AST, with an executable-semantics round-trip test covering functions, lists,
  variables, loops, colours, and waits.
- Android wire-compatible `EffectProgram` single/bundle transfer using only
  the 14 fields emitted by `EffectProgramTransfer.kt`, including schema/kind
  metadata, 2 MiB file and 256 KiB source limits, per-item bundle diagnostics,
  conflict previews, and mandatory recompilation so imported AST/hash values
  are never trusted. The Swift decoder additionally rejects duplicate JSON
  keys, unknown fields, wrong JSON types, and unknown source kinds.
- A `Sendable` actor repository with CRUD, copy/overwrite/skip import, stable
  program IDs, optimistic revisions derived from canonical known-field JSON
  (never added to the Android wire), a 50-program limit, injectable clock/ID
  generation, and atomic file replacement. Storage corruption is quarantined
  before the two stable example IDs are restored; a failed write cannot mutate
  the actor's in-memory state. It uses files only—never `UserDefaults` or a
  required-reason API.
- Structured async compiler facades use Swift 6.2 `@concurrent` for CPU-bound
  Script/Blockly work, while an actor-isolated async interpreter preserves VM
  state. Both cooperatively check task cancellation and an optional monotonic
  `ContinuousClock` deadline at token/block/statement/compiler-phase and VM
  instruction/loop/function-call boundaries, returning typed cancellation or
  deadline errors. Failed async frames are transactional and do not advance VM
  state; no detached task, GCD bridge, continuation, or unchecked conformance
  is used.
- A deterministic value-semantic interpreter covering variables, lists,
  conditionals, repeat/for/while and nearest-loop break/continue, functions,
  runtime inputs, stateful and pure builtins, wait/fade scheduling, reset on
  time rewind, finite-number and zero-time instruction guards, seven-group
  output, and group-major 42-pixel RGB output.
- Swift tests read Android's eight Maurya Script functional resources directly
  from `android/app/src/test/resources/maurya-script`, lock them by SHA-256,
  compile, and execute them. Android and Swift also consume the same
  `protocol/fixtures/effect-algorithms.json` numeric/pattern golden. Stateful
  smooth/hysteresis/peak-hold/debounce/edge sequences and value-function
  parameter/local restoration are covered explicitly.
- Swift Testing suites with parameterized Android parity fixtures, malicious
  input/limit cases, formatter round trips, and exact RNG/noise hexadecimal
  floating-point values. Transfer tests lock the Android field set and
  recompilation behavior; repository tests cover CRUD, conflict strategies,
  revision conflicts, 50-item limits, corruption recovery, and atomic-write
  failure. Async tests self-cancel a structured child task, use an already-due
  monotonic deadline without sleeping, verify transactional recovery, and
  count internal compiler/VM checkpoints. Canonical golden tests lock Android's
  member order, integral-number representation, function sorting/array shape, and hash;
  reachability and finite-tail diagnostics are also covered. Catalog tests
  execute every Android statement/expression type through a typed consumer and
  lock the catalog sets to zero missing/extra entries. JVM `JSONObject` extreme
  number canonical/hash fixtures are included. The current package runs 94
  tests in 14 suites; the current total is 101 tests.

## Compatibility boundary

The pure compiler/interpreter/repository behavior in this package is locally
covered. Diagnostic compatibility is defined by structured code, source ID,
UTF-16 range, and quick-fix value; Chinese/Japanese prose is presentation text,
not a serialized compatibility field. Sensor/audio acquisition and comparison
against recordings from Android and iPhone hardware belong to the sibling
`MauryaAnalysis` package and remain a physical-device validation gate.

Canonical JSON now uses Android's ordered object/array schema rather than
Swift type descriptions: operations preserve source order, functions sort by
name, enum values use Android raw names, integral doubles omit `.0`, and
`astSHA256` hashes those exact UTF-8 bytes. Integral, fractional, signed-zero,
scientific-threshold, maximum finite, minimum subnormal, and 53-bit-boundary
numbers are locked to Java 17 `JSONObject.numberToString` output and fixed
SHA-256 goldens. Unknown future Blockly blocks still fail explicitly and
therefore cannot acquire a misleading hash.

## Async and synchronous execution scope

- Use `EffectAsyncCompiler` and `EffectAsyncInterpreter` for UI-triggered or
  lifecycle-bound work. Their cancellation is cooperative: latency is bounded
  by the next documented checkpoint, not by forcibly interrupting a Swift
  instruction. Deadlines are absolute `ContinuousClock.Instant` values, so
  wall-clock changes cannot extend or shorten execution.
- Deadline tests intentionally pass the current monotonic instant and assert
  the typed error. They do not sleep or depend on scheduler speed. Separate
  checkpoint-count tests prove checks occur inside compiler and VM work rather
  than only at facade entry.
- The original synchronous compiler/interpreter APIs remain deterministic and
  source-compatible. They are appropriate for already-bounded background work,
  pure unit tests, and callers that provide their own execution budget. They do
  not observe Swift task cancellation or a wall-clock deadline; their existing
  instruction, iteration, call-depth, duration, list, finite-number, and target
  limits still apply.

## Exact repository/transfer differences from Android

- Exported single/bundle JSON has the same schema `1`, kinds, `exportedBy`
  members, and program field names as Android 4.2.0. No revision or private
  Swift storage field is serialized. JSON member order and whitespace are not
  a compatibility contract.
- Android's `org.json` decoder defaults several absent values and silently
  treats unknown `sourceKind` values as Blockly. Swift preserves the documented
  defaults for absent known fields but deliberately rejects unknown fields,
  duplicate keys, wrong types, and unknown kinds instead of silently accepting
  future syntax.
- Android replaces a corrupt repository in place. Swift first moves it beside
  the live file with an `effect_programs.json.corrupt-*` name, then restores
  defaults. This makes recovery inspectable without changing the transfer wire.
- Built-in defaults use the same Blockly source kind, program IDs, names, and
  RGB/rainbow operation chains as Android. Android creates installation-random
  UUID block IDs; Swift uses deterministic block IDs, so default workspace bytes
  and AST hashes are intentionally not stable across platforms (nor across two
  Android installations).
- Swift optimistic revisions are SHA-256 values over sorted JSON containing
  only Android-known program fields. They are repository API metadata, are not
  persisted/exported as a new field, and therefore do not claim Android wire
  support for revisions.

Package tests establish the platform-independent Effects core. They do not
substitute for physical sensor/audio fixture validation in `MauryaAnalysis` or
end-to-end playback against a lamp.

## Validation

This machine's full Xcode is at `/Applications/Xcode.app`. Select it per
command so validation does not depend on the caller's active developer path:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --package-path ios/Packages/MauryaEffects -c debug \
    -Xswiftc -warnings-as-errors

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --package-path ios/Packages/MauryaEffects -c release \
    -Xswiftc -warnings-as-errors

cd ios/Packages/MauryaEffects
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme MauryaEffects \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath /tmp/maurya-effects-derived \
    CODE_SIGNING_ALLOWED=NO \
    SWIFT_SUPPRESS_WARNINGS=NO \
    build
```

The generic build has been verified against the iPhoneOS 26.5 SDK with an
iOS 17.0 deployment target, code signing disabled, and warnings as errors.
