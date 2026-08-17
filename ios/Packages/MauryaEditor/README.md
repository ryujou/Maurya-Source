# MauryaEditor 离线灯效编辑器

MauryaEditor 是 iOS 17 的 SwiftUI/WKWebView 容器，加载 Android effect_editor 生成的 Blockly/Maurya Script 资源。使用 WKWebView 是因为应用需要稳定的 JavaScript 到原生消息桥。

## 离线和安全边界

- 资源通过只读 maurya-editor://bundle/ 方案提供，只允许 manifest.json 中列出的文件。
- HTTP(S)、file、未知 scheme、新窗口、下载、非主框架导航、摄像头和麦克风均拒绝；非持久网站数据和 CSP 禁止网络、frame、object、form。
- JavaScript 到原生的消息要经过 origin、bridge 版本、每个 WebView nonce、请求 ID、字节数、嵌套深度、节点数和命令 schema 检查。
- 命令白名单为 load、export、import、undo、redo、resize、fit、run、editField、insertWaitAfter、diagnostic、clearDiagnostics；事件包括 ready、workspaceChanged、sourceChanged、saveRequested、runRequested、haptic 和 response。
- 模型、代理和清理流程由 MainActor 管理；自动保存使用去抖和原子写入，Web 内容进程终止后会重新加载已校验资源并恢复最近一次保存。

## 同步编辑器资源

源代码唯一来源是 android/effect_editor，不要编辑本包里的压缩文件：

~~~
cd android/effect_editor
npm ci
npx playwright install chromium
npm test

cd ../../ios/Packages/MauryaEditor
node Tools/sync-editor-bundle.mjs
swift test
~~~

同步脚本会记录版本、大小、MIME、每个文件的 SHA-256 和总哈希。应用应等 phase == ready 后发送命令；真实 iPhone/iPad 仍需验证键盘、IME、旋转、内存压力、VoiceOver 和 WebView 反复进入/退出。
