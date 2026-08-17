import {fileURLToPath, pathToFileURL} from 'node:url';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import path from 'node:path';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const localLayout = path.join(projectRoot, 'src', 'android', 'Nichirin', 'effect_editor');
const publishedLayout = path.join(projectRoot, 'android', 'effect_editor');
const usesLocalLayout = await readFile(path.join(localLayout, 'package.json'), 'utf8')
  .then(() => true)
  .catch(() => false);
const editorRoot = usesLocalLayout ? localLayout : publishedLayout;
const builtEditorRoot = usesLocalLayout
  ? path.join(projectRoot, 'src', 'android', 'Nichirin', 'app', 'src', 'main', 'assets', 'effect-editor')
  : path.join(projectRoot, 'android', 'app', 'src', 'main', 'assets', 'effect-editor');
const outputRoot = usesLocalLayout
  ? path.join(projectRoot, 'src', 'server', 'maurya-download', 'script')
  : path.join(projectRoot, 'server', 'script');
const imageRoot = path.join(outputRoot, 'assets', 'block-demos');
const playwrightModule = path.join(editorRoot, 'node_modules', 'playwright', 'index.mjs');
const {chromium} = await import(pathToFileURL(playwrightModule).href);

let sequence = 0;
const id = (name) => `${name}-${++sequence}`;
const shadowNumber = (value) => ({shadow: {type: 'math_number', fields: {NUM: value}}});
const shadowBoolean = (value) => ({shadow: {type: 'logic_boolean', fields: {BOOL: value ? 'TRUE' : 'FALSE'}}});
const shadowColour = (value) => ({shadow: {type: 'maurya_colour_literal', fields: {COLOR: value}}});
const numberBlock = (value) => ({type: 'math_number', id: id('number'), fields: {NUM: value}});
const boolBlock = (value) => ({type: 'logic_boolean', id: id('boolean'), fields: {BOOL: value ? 'TRUE' : 'FALSE'}});
const colourBlock = (value) => ({type: 'maurya_colour_literal', id: id('colour'), fields: {COLOR: value}});
const variableBlock = (name) => ({type: 'maurya_var_get_number', id: id('variable'), fields: {VAR: {id: `var-${name}`} }});
const inputBlock = (value) => ({block: value});
const block = (type, fields = {}, inputs = {}, next = null) => ({
  type,
  id: id(type),
  ...(Object.keys(fields).length ? {fields} : {}),
  ...(Object.keys(inputs).length ? {inputs} : {}),
  ...(next ? {next: {block: next}} : {}),
});
const chain = (...blocks) => {
  for (let index = 0; index < blocks.length - 1; index += 1) {
    blocks[index].next = {block: blocks[index + 1]};
  }
  return {
    blocks: {
      languageVersion: 0,
      blocks: [blocks[0]],
    },
  };
};
const workspace = (...topBlocks) => ({
  blocks: {
    languageVersion: 0,
    blocks: topBlocks,
  },
});
const loopBody = (type, fields, inputs = {}) => block(type, fields, inputs);
const forInputs = () => ({
  FROM: shadowNumber(1),
  TO: shadowNumber(42),
  BY: shadowNumber(1),
});

const rgbWorkspace = chain(
  block('maurya_start'),
  block('maurya_set_color', {TARGET: 'ALL', COLOR: '#FF0000'}),
  block('maurya_wait', {DURATION: 500, UNIT: 'MS'}),
  block('maurya_fade', {TARGET: 'ALL', COLOR: '#00FF00', DURATION: 1500}),
  block('maurya_fade', {TARGET: 'ALL', COLOR: '#0000FF', DURATION: 1500}),
);

const rainbowWorkspace = chain(
  block('maurya_start'),
  block('maurya_forever', {}, {
    DO: inputBlock(
      chain(
        loopBody('maurya_adjust_hsv', {TARGET: 'ALL', H: 2, S: 0, V: 0}),
        loopBody('maurya_wait', {DURATION: 50, UNIT: 'MS'}),
      ).blocks.blocks[0],
    ),
  }),
);

const pixelRainbowWorkspace = chain(
  block('maurya_start'),
  block('maurya_forever', {}, {
    DO: inputBlock(
      chain(
          loopBody('maurya_for', {VAR: {id: 'var-i'}}, {
          ...forInputs(),
          DO: inputBlock(
            block('maurya_set_pixel_at_hsv_value', {}, {
              INDEX: inputBlock(variableBlock('i')),
              H: inputBlock(numberBlock(0)),
              S: inputBlock(numberBlock(255)),
              V: inputBlock(numberBlock(255)),
            }),
          ),
        }),
        loopBody('maurya_wait', {DURATION: 50, UNIT: 'MS'}),
      ).blocks.blocks[0],
    ),
  }),
);
pixelRainbowWorkspace.variables = [{name: 'i', id: 'var-i', type: 'Number'}];

const sensorCompare = block('logic_compare', {OP: 'GT'}, {
  A: inputBlock(block('maurya_runtime_number', {KEY: 'SENSOR_SHAKE'})),
  B: shadowNumber(12),
});
const sensorWorkspace = chain(
  block('maurya_start'),
  block('maurya_if_else', {}, {
    IF: inputBlock(sensorCompare),
    DO: inputBlock(block('maurya_set_color_value', {TARGET: 'ALL'}, {
      COLOR: shadowColour('#FF2D55'),
    })),
    ELSE: inputBlock(block('maurya_set_hsv_value', {TARGET: 'ALL'}, {
      H: inputBlock(block('maurya_runtime_number', {KEY: 'SENSOR_ROLL'})),
      S: inputBlock(numberBlock(255)),
      V: inputBlock(numberBlock(255)),
    })),
  }),
);

const audioWorkspace = chain(
  block('maurya_start'),
  block('maurya_for', {VAR: {id: 'var-i'}}, {
    ...forInputs(),
    DO: inputBlock(block('maurya_set_pixel_at_hsv_value', {}, {
      INDEX: inputBlock(variableBlock('i')),
      H: inputBlock(block('maurya_audio_number', {KEY: 'AUDIO_BASS'})),
      S: inputBlock(block('maurya_audio_number', {KEY: 'AUDIO_MID'})),
      V: inputBlock(block('maurya_audio_number', {KEY: 'AUDIO_TREBLE'})),
    })),
  }),
);
audioWorkspace.variables = [{name: 'i', id: 'var-i', type: 'Number'}];

const colourList = block('maurya_colour_list7', {}, {
  C1: shadowColour('#FF2D55'),
  C2: shadowColour('#FF9500'),
  C3: shadowColour('#FFD60A'),
  C4: shadowColour('#39FF88'),
  C5: shadowColour('#39C5BB'),
  C6: shadowColour('#1677FF'),
  C7: shadowColour('#AF52DE'),
});
const functionDefinition = block('maurya_function_def', {NAME: '脉冲'}, {},);
functionDefinition.inputs = {
  BODY: inputBlock(
    chain(
      block('maurya_set_color', {TARGET: 'ALL', COLOR: '#FFFFFF'}),
      block('maurya_wait', {DURATION: 500, UNIT: 'MS'}),
    ).blocks.blocks[0],
  ),
};
const listWorkspace = workspace(
  chain(
    block('maurya_start'),
    block('maurya_apply_colour_list', {}, {LIST: inputBlock(colourList)}),
    block('maurya_wait', {DURATION: 500, UNIT: 'MS'}),
    block('maurya_function_call', {NAME: '脉冲'}),
  ).blocks.blocks[0],
  functionDefinition,
);

const demos = [
  {
    slug: 'rgb',
    title: '红 → 绿 → 蓝',
    description: '开始播放后，依次设置红色、等待、渐变到绿色，再渐变到蓝色。',
    workspace: rgbWorkspace,
    code: `effect "红绿蓝" {
    all.color("#FF0000");
    wait(500ms);
    all.fade("#00FF00", 1500ms);
    all.fade("#0000FF", 1500ms);
}`,
  },
  {
    slug: 'rainbow',
    title: '无限彩虹',
    description: '永久重复调整全部7组的色相，每次前进2度并等待50毫秒。',
    workspace: rainbowWorkspace,
    code: `effect "无限彩虹" {
    forever {
        all.adjustHsv(2, 0, 0);
        wait(50ms);
    }
}`,
  },
  {
    slug: 'pixel-rainbow',
    title: '42颗彩虹',
    description: '用 for 遍历完整的42颗灯珠，并把循环变量接到逐灯 HSV 积木。',
    workspace: pixelRainbowWorkspace,
    code: `effect "42颗彩虹" {
    forever {
        for (let i = 1; i <= 42; i += 1) {
            pixelAt(i).hsv(time.elapsedMs / 18 + i * 9, 255, 255);
        }
        wait(50ms);
    }
}`,
  },
  {
    slug: 'sensor-branch',
    title: '传感器分支',
    description: '读取摇动强度；超过阈值时显示粉红色，否则使用手机滚转角设置色相。',
    workspace: sensorWorkspace,
    code: `effect "传感器分支" {
    if (sensor.shake > 12) {
        all.color("#FF2D55");
    } else {
        all.hsv(sensor.roll, 255, 255);
    }
}`,
  },
  {
    slug: 'audio-bands',
    title: '音乐频段',
    description: '在 for 循环中读取低频、中频和高频，并把三段音频数据接到逐灯 HSV。',
    workspace: audioWorkspace,
    code: `effect "音乐频段" {
    for (let i = 1; i <= 42; i += 1) {
        pixelAt(i).hsv(audio.bass, audio.mid, audio.treble);
    }
    wait(50ms);
}`,
  },
  {
    slug: 'lists-functions',
    title: '列表与函数',
    description: '用7色列表应用颜色，再调用一个可复用的“脉冲”流程函数。',
    workspace: listWorkspace,
    code: `fn pulse() {
    all.color("#FFFFFF");
    wait(500ms);
}

effect "列表与函数" {
    applyColours(["#FF2D55", "#FF9500", "#FFD60A",
        "#39FF88", "#39C5BB", "#1677FF", "#AF52DE"]);
    pulse();
}`,
  },
];

function collectBlocks(value, result = []) {
  if (!value || typeof value !== 'object') return result;
  if (Array.isArray(value)) {
    value.forEach((item) => collectBlocks(item, result));
    return result;
  }
  if (typeof value.type === 'string' && value.id) result.push(value);
  Object.values(value).forEach((child) => collectBlocks(child, result));
  return result;
}

for (const demo of demos) {
  const blocks = collectBlocks(demo.workspace);
  const types = new Set(blocks.map((item) => item.type));
  if (!types.has('maurya_start')) throw new Error(`${demo.slug} is missing maurya_start`);
  if (demo.slug === 'pixel-rainbow' || demo.slug === 'audio-bands') {
    const loop = blocks.find((item) => item.type === 'maurya_for');
    const upperBound = loop?.inputs?.TO?.shadow?.fields?.NUM;
    if (upperBound !== 42) throw new Error(`${demo.slug} must loop through exactly 42 pixels`);
  }
}

async function waitForServer(url) {
  for (let attempt = 0; attempt < 60; attempt += 1) {
    try {
      const response = await fetch(url);
      if (response.ok) return;
    } catch {
      // Vite is still starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for ${url}`);
}

await mkdir(imageRoot, {recursive: true});
const contentTypes = {
  '.css': 'text/css',
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
};
const server = createServer(async (request, response) => {
  try {
    const pathname = decodeURIComponent(new URL(request.url ?? '/', 'http://127.0.0.1').pathname);
    const relative = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
    const candidate = path.resolve(builtEditorRoot, relative);
    if (candidate !== builtEditorRoot && !candidate.startsWith(`${builtEditorRoot}${path.sep}`)) {
      response.writeHead(403);
      response.end();
      return;
    }
    const body = await readFile(candidate);
    response.writeHead(200, {
      'Content-Type': contentTypes[path.extname(candidate).toLowerCase()] ?? 'application/octet-stream',
      'Cache-Control': 'no-store',
    });
    response.end(body);
  } catch {
    response.writeHead(404);
    response.end();
  }
});
await new Promise((resolve) => server.listen(4374, '127.0.0.1', resolve));

try {
  await waitForServer('http://127.0.0.1:4374/');
  const browser = await chromium.launch({headless: true});
  try {
    const page = await browser.newPage({viewport: {width: 1200, height: 1800}, deviceScaleFactor: 2});
    await page.goto('http://127.0.0.1:4374/?lang=zh', {waitUntil: 'networkidle'});
    await page.evaluate(() => {
      document.querySelector('.blocklyToolboxDiv')?.remove();
      document.querySelector('#workspace-controls')?.remove();
      document.querySelector('.blocklyFlyout')?.remove();
      document.querySelector('.blocklyScrollbarVertical')?.remove();
      document.querySelector('.blocklyScrollbarHorizontal')?.remove();
      document.body.style.background = '#090c14';
    });

    const manifest = [];
    for (const demo of demos) {
      await page.evaluate((value) => window.MauryaEditor?.load(JSON.stringify(value)), demo.workspace);
      await page.waitForFunction(() => document.querySelectorAll('#editor .blocklyBlockCanvas .blocklyDraggable').length > 0);
      await page.evaluate(() => window.MauryaEditor?.fit());
      await page.waitForTimeout(120);
      const geometry = await page.locator('#editor .blocklyBlockCanvas .blocklyDraggable').evaluateAll((elements) => {
        const rects = elements.map((element) => {
          const rect = element.getBoundingClientRect();
          return {left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom};
        });
        return {
          count: elements.length,
          left: Math.min(...rects.map((rect) => rect.left)),
          top: Math.min(...rects.map((rect) => rect.top)),
          right: Math.max(...rects.map((rect) => rect.right)),
          bottom: Math.max(...rects.map((rect) => rect.bottom)),
          types: elements.map((element) => element.getAttribute('data-id')),
        };
      });
      if (!geometry.count || !Number.isFinite(geometry.left)) {
        throw new Error(`No rendered blocks found for ${demo.slug}`);
      }
      const padding = 24;
      const clip = {
        x: Math.max(0, geometry.left - padding),
        y: Math.max(0, geometry.top - padding),
        width: geometry.right - geometry.left + padding * 2,
        height: geometry.bottom - geometry.top + padding * 2,
      };
      const imagePath = path.join(imageRoot, `${demo.slug}.png`);
      await page.screenshot({path: imagePath, clip});
      manifest.push({
        slug: demo.slug,
        title: demo.title,
        description: demo.description,
        image: `assets/block-demos/${demo.slug}.png`,
        code: demo.code,
        blockCount: geometry.count,
      });
    }
    await writeFile(path.join(outputRoot, 'block-demos.json'), `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
  } finally {
    await browser.close();
  }
} finally {
  await new Promise((resolve) => server.close(resolve));
}
