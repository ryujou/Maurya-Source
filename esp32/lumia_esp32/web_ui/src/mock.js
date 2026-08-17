export function createMockState() {
  return {
    wirelessMode: 'wifi',
    global: {
      sceneMode: 1,
      sceneParam: 252,
      globalBrightness: 255,
      gainR: 255,
      gainG: 176,
      gainB: 240,
      deviceAddr: 1,
      saveState: 0,
    },
    groups: Array.from({ length: 7 }, () => ({
      innerMode: 1,
      hue: 45,
      sat: 172,
      value: 254,
      innerParam: 255,
    })),
    diagnostics: {
      tempCx100: 3187,
      vddaMv: 3300,
      rxCount: 128,
      rxOverflow: 0,
      txDrop: 0,
      parseError: 0,
      flashSizeBytes: 4194304,
      appPartitionBytes: 1048576,
      ledTxErrorCount: 0,
      ledGpioSwitchErrorCount: 0,
      ledInitErrorCount: 0,
      ledMaxScanGapUs: 620,
    },
  }
}

export function hexToHsv(hex) {
  const value = Number.parseInt(hex.slice(1), 16)
  const r = ((value >> 16) & 255) / 255
  const g = ((value >> 8) & 255) / 255
  const b = (value & 255) / 255
  const max = Math.max(r, g, b)
  const min = Math.min(r, g, b)
  const delta = max - min
  let hue = 0
  if (delta) {
    if (max === r) hue = 60 * (((g - b) / delta) % 6)
    else if (max === g) hue = 60 * ((b - r) / delta + 2)
    else hue = 60 * ((r - g) / delta + 4)
  }
  if (hue < 0) hue += 360
  return {
    hue: Math.round(hue) % 360,
    sat: Math.round(max ? (delta / max) * 255 : 0),
    value: Math.round(max * 255),
  }
}
