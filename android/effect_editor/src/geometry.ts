/** Canonical physical geometry for the current Maurya hardware revision. */
export const EFFECT_GEOMETRY = Object.freeze({
  groupCount: 7,
  pixelsPerGroup: 6,
  pixelCount: 42,
});

if (EFFECT_GEOMETRY.pixelCount !== EFFECT_GEOMETRY.groupCount * EFFECT_GEOMETRY.pixelsPerGroup) {
  throw new Error('Maurya effect geometry is internally inconsistent');
}
