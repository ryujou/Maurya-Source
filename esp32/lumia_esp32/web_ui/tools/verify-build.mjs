import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { join } from 'node:path'

const root = new URL('..', import.meta.url).pathname.replace(/^\/(.:)/, '$1')
const variantIndex = process.argv.indexOf('--variant')
const variant = variantIndex >= 0 ? process.argv[variantIndex + 1] : 'multilingual'
if (!['multilingual', 'ja'].includes(variant)) throw new Error(`invalid variant: ${variant}`)
const palette = JSON.parse(readFileSync(join(root, 'public', 'palette.json'), 'utf8'))
const app = readFileSync(join(root, 'src', 'App.vue'), 'utf8')
const styles = readFileSync(join(root, 'src', 'styles.css'), 'utf8')
const compiledJavaScript = readdirSync(join(root, 'dist', 'assets'))
  .filter((name) => name.endsWith('.js'))
  .map((name) => readFileSync(join(root, 'dist', 'assets', name), 'utf8'))
  .join('\n')
const avatarRoot = join(root, 'public', 'avatars')
const avatarFiles = readdirSync(avatarRoot).filter((name) => name.endsWith('.webp'))
const imas = palette.groups
  .filter((item) => item.franchiseId === 'imas')
  .sort((a, b) => a.sortOrder - b.sortOrder)

if (palette.franchises.length !== 4) throw new Error('franchise count')
if (palette.groups.length !== 31) throw new Error('group count')
if (palette.characters.length !== 505) throw new Error('character count')
if (imas.length !== 8 || imas.at(-1).nameZh !== '其他') throw new Error('imas filtering')
if (avatarFiles.length !== 505) throw new Error('avatar count')
if (new Set(palette.characters.map((item) => item.avatar)).size !== 505) throw new Error('avatar mapping uniqueness')
if (readdirSync(join(root, 'public', 'group-icons')).length !== 31) throw new Error('group icon count')
if (palette.groups.some((item) => !item.icon || !existsSync(join(root, 'public', 'group-icons', item.icon)))) throw new Error('group icon mapping')
if (imas.filter((item) => item.officialLogo).length !== 8) throw new Error('imas official logo mapping')
for (const endpoint of ['/api/v1/state', '/api/v1/scene', '/api/v1/global', '/api/v1/groups', '/api/v1/diagnostics/clear']) {
  if (!app.includes(endpoint)) throw new Error(`missing REST endpoint: ${endpoint}`)
}
for (const field of ['ledTxErrorCount', 'ledGpioSwitchErrorCount', 'ledMaxScanGapUs']) {
  if (!app.includes(field)) throw new Error(`missing LED diagnostic: ${field}`)
}
if (!app.includes('data-testid="all-group-mode-buttons"')) throw new Error('missing all-group mode buttons')
if (variant === 'ja') {
  if (!app.includes('v-if="!japaneseOnly" class="language-button"')) {
    throw new Error('Japanese-only language switch guard is missing')
  }
  if (compiledJavaScript.includes('language-button') || compiledJavaScript.includes('中文')) {
    throw new Error('Japanese-only compiled build contains the language switch')
  }
} else if (!app.includes('class="language-button"')) {
  throw new Error('multilingual build must expose a language switcher')
} else if (!compiledJavaScript.includes('language-button') || !compiledJavaScript.includes('中文')) {
  throw new Error('multilingual compiled build is missing the language switch')
}
if (!app.includes('const { innerMode, hue, sat, value, innerParam }')) throw new Error('all-group apply omits mode or parameter')
if (!app.includes('v-for="mode in [1, 3]"') || app.includes('<select v-model.number="group.innerMode"') || app.includes('<select v-model.number="state.groups[0].innerMode"')) throw new Error('web group modes must use steady/strobe buttons only')
function webpSize(buffer) {
  if (buffer.toString('ascii', 0, 4) !== 'RIFF' || buffer.toString('ascii', 8, 12) !== 'WEBP') throw new Error('invalid webp')
  const chunk = buffer.toString('ascii', 12, 16)
  if (chunk === 'VP8X') return [1 + buffer.readUIntLE(24, 3), 1 + buffer.readUIntLE(27, 3)]
  if (chunk === 'VP8L') {
    const bits = buffer.readUInt32LE(21)
    return [1 + (bits & 0x3fff), 1 + ((bits >> 14) & 0x3fff)]
  }
  if (chunk === 'VP8 ') return [buffer.readUInt16LE(26) & 0x3fff, buffer.readUInt16LE(28) & 0x3fff]
  throw new Error(`unsupported webp chunk: ${chunk}`)
}
const avatarBytes = avatarFiles.reduce((total, name) => {
  const payload = readFileSync(join(avatarRoot, name))
  if (webpSize(payload).join('x') !== '96x96') throw new Error(`avatar dimensions: ${name}`)
  return total + payload.length
}, 0)
if (avatarBytes > 1_500_000) throw new Error(`avatar budget: ${avatarBytes}`)
for (const required of ['help', 'guideContent', 'Maurya123', '192.168.4.2/24', 'v1.8.2-jp', 'popstate']) {
  if (!app.includes(required)) throw new Error(`missing guide/navigation behavior: ${required}`)
}
if (variant === 'multilingual') {
  for (const chineseUi of ['控制台', '使用说明', '频闪', '清零诊断', '正在连接']) {
    if (!app.includes(chineseUi)) throw new Error(`Chinese UI missing: ${chineseUi}`)
  }
}
if (!styles.includes('prefers-reduced-motion') || !styles.includes('--gold')) throw new Error('visual accessibility tokens')
if (!existsSync(join(root, 'dist', 'index.html'))) throw new Error('dist index')
function directoryBytes(directory) {
  return readdirSync(directory, { withFileTypes: true }).reduce((total, item) => {
    const path = join(directory, item.name)
    return total + (item.isDirectory() ? directoryBytes(path) : statSync(path).size)
  }, 0)
}
const distBytes = directoryBytes(join(root, 'dist'))
if (distBytes > 1_850_000) throw new Error(`web resource budget: ${distBytes}`)
console.log('web UI verification passed')
