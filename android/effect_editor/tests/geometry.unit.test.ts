import {readFileSync, readdirSync, statSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {describe, expect, test} from 'vitest';
import {EFFECT_GEOMETRY} from '../src/geometry';

const editorRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const androidRoot = resolve(editorRoot, '..');
const packagedEditorRoot = resolve(editorRoot, '../app/src/main/assets/effect-editor');

const obsoleteGeometryPatterns = [
  /全部\s*70\s*颗/u,
  /全\s*70\s*ピクセル/u,
  /(?:^|\D)7\s*[×xX*]\s*10(?:\D|$)/u,
  /\b70\s*(?:pixels?|leds?)\b/iu,
];

function textFilesBelow(root: string): string[] {
  return readdirSync(root).flatMap((entry) => {
    const path = join(root, entry);
    if (statSync(path).isDirectory()) {
      return ['node_modules', 'build', '.gradle', 'test-results'].includes(entry)
        ? []
        : textFilesBelow(path);
    }
    if (path === fileURLToPath(import.meta.url)) return [];
    return /\.(?:html|js|json|ts|kt|kts|xml|css|md|txt)$/u.test(entry) ? [path] : [];
  });
}

describe('canonical effect geometry', () => {
  test('is seven groups of six pixels', () => {
    expect(EFFECT_GEOMETRY).toEqual({groupCount: 7, pixelsPerGroup: 6, pixelCount: 42});
    expect(EFFECT_GEOMETRY.pixelCount).toBe(
      EFFECT_GEOMETRY.groupCount * EFFECT_GEOMETRY.pixelsPerGroup,
    );
  });

  test('Android sources, tests, docs, resources, and bundles contain no obsolete geometry', () => {
    const violations = textFilesBelow(androidRoot).flatMap((path) => {
      const content = readFileSync(path, 'utf8');
      return obsoleteGeometryPatterns
        .filter((pattern) => pattern.test(content))
        .map((pattern) => `${path}: ${pattern.source}`);
    });

    expect(violations).toEqual([]);
  });

  test('packaged Blockly editor exposes the canonical localized pixel count', () => {
    const bundle = textFilesBelow(packagedEditorRoot)
      .filter((path) => path.endsWith('.js'))
      .map((path) => readFileSync(path, 'utf8'))
      .join('\n');

    // Vite keeps the localized labels as template literals and minifies the
    // imported constant name. Verify both the embedded canonical object and
    // that each label reads its value instead of carrying another literal.
    expect(bundle).toContain('groupCount:7,pixelsPerGroup:6,pixelCount:42');
    expect(bundle).toMatch(/全部\$\{[^}]+\.pixelCount\}颗/u);
    expect(bundle).toMatch(/全\$\{[^}]+\.pixelCount\}ピクセル/u);
  });
});
