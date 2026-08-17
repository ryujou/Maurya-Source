# Maurya Effect Editor

This directory is the source of truth for the Blockly and script editors bundled in the Android app.

## Hardware geometry

The current Maurya hardware has seven groups with six physical pixels per group, for 42 pixels total. Editor code must read these values from `src/geometry.ts`; do not duplicate pixel-count literals in labels or generated assets.

## Rebuild and verify

```sh
npm ci
npx playwright install chromium
npm test
```

`npm test` rebuilds the production bundle into `../app/src/main/assets/effect-editor`, runs the geometry/unit checks, and then runs the Playwright interaction suite. The Vite output directory is emptied on every build, so obsolete hashed bundles cannot remain packaged in the APK.

Commit source changes and their regenerated Android assets together. Never edit a minified bundle directly.
