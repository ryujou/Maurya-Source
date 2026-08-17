# iOS 应用目标

App/ 是 SwiftUI 应用目标，负责把仓库内的协议、BLE、设备、灯效、资源、分析、编辑器、播放、分享和 OTA 包组合成页面。工程文件为 Maurya.xcodeproj，部署目标为 iOS 17，同时支持 iPhone 和 iPad。

## 主要页面和入口

- NavigationStack 路由覆盖扫描、设备详情、分享导入和 maurya:// 深链；HTTPS 分享路径由应用层接收后进入同一导入流程。
- 设备详情页通过 CoreBluetooth 扫描/连接，读取设备快照和信息，提供全局场景、全局 RGB、诊断清除以及 7 个灯组的读取/写入。
- 灯效页连接 MauryaEffects、MauryaEditor 和 MauryaPlayback，支持 Blockly/Script 程序预览和连接设备后的前台播放。
- 资源页提供角色/企划/应援色浏览、搜索、头像和自定义颜色；分享页支持创建/导入单个灯效或应援色、二维码、预览确认和历史去重。
- Analysis 仅在用户触发时启动音频/运动输入；OTA 页面执行严格的版本、布局、哈希、签名和设备状态检查。
- 页面状态明确区分加载、空、错误、权限、断开和不可用；界面含系统、简体中文和日文选择。

## 权限和服务地址

应用在 Info.plist 中声明蓝牙、麦克风、摄像头和运动用途说明，不声明后台模式。分享服务仍使用配置中的占位地址，OTA 使用应用配置的发布地址和内置公钥；生产地址、签名团队、Associated Domains 和私有签名材料不写入公开仓库。

## 打开与构建

在 Xcode 26 或更新版本打开 Maurya.xcodeproj，也可以在 App/ 目录执行：

~~~
xcodebuild -project Maurya.xcodeproj \
  -scheme Maurya \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  SWIFT_SUPPRESS_WARNINGS=NO \
  CODE_SIGNING_ALLOWED=NO build
~~~

测试使用 Swift Testing 和 XCTest。真机测试必须提供开发签名和实际 ESP32；纯包测试、模拟器和注入的假传输只能验证状态机和编解码，不代表硬件 Gate 已通过。

## 编辑器资源

编辑器源代码在 android/effect_editor/。先构建 Android 资源，再运行 Packages/MauryaEditor/Tools/sync-editor-bundle.mjs；同步脚本会校验 manifest、文件大小、MIME、SHA-256 和总哈希，应用只从离线 maurya-editor:// 方案加载资源。
