# Maurya 4.0.0 本地发布说明

- Android：Maurya 4.0.0（versionCode 400）
- applicationId：`com.example.peacock`
- ESP32 固件：继续使用 v1.7.1，本版本不需要重新刷写

## 本次更新

- 播放前检查持续 0 ms 的不可见颜色或模式状态，并提供一键补入等待。
- 新增离线 Maurya Script 代码编辑器、语法高亮、补全、格式化和行内错误定位。
- 积木程序与代码程序统一使用受限 Kotlin 解释器和 BLE RAM 临时控制协议。
- 新增单程序与整库导入、导出；导入源码会在本机重新编译和校验。
- 修复窄屏顶栏、WebView 加载时序和 Android 深色算法导致的代码低对比度问题。

## 验证结果

- Blockly / Maurya Script Playwright 测试：7/7 通过。
- Android `testDebugUnitTest`：通过。
- Android `lintDebug`：通过。
- Android `assembleRelease`：通过。
- Android 16 虚拟机代码编辑器流程：通过。
- 320 dp 窄屏及 1.3 倍字体检查：通过。
- APK v2 签名校验：通过。

本发布只生成在本机，没有上传 GitHub、服务器或在线下载页。
