# 灯效编辑器源码

本目录是 Android 内置 Blockly 和 Maurya Script 编辑器的源代码。Vite 构建结果会被复制到 android/app/src/main/assets/effect-editor，iOS 通过 ios/Packages/MauryaEditor/Tools/sync-editor-bundle.mjs 复用同一份离线资源。

## 几何约束

当前硬件是 7 组 × 6 颗 = 42 颗灯。编辑器从 src/geometry.ts 读取组数和灯数；循环示例、逐灯目标和生成资源都必须使用这一配置，不要在标签或压缩包中另写一个数量。

## 构建和验证

~~~
npm ci
npx playwright install chromium
npm test
~~~

npm test 会重建生产资源、运行几何和单元检查，再运行 Playwright 交互测试；输出目录每次都会清空，避免旧的哈希文件继续被打进 APK。请修改 TypeScript/源文件后重新生成资源，不要直接编辑压缩后的 JavaScript。
