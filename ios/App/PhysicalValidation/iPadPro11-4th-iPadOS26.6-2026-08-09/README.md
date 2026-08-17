# iPad Pro 真机验证记录（2026-08-09）

这份 README 对应一次历史真机记录，不是持续集成结果，也不替代新的发布验收。

## 设备和构建

- 设备：11 英寸 iPad Pro（第 4 代），型号 iPad14,3，iPadOS 26.6（23G71），arm64。
- 应用：Maurya 1.0 (1) Debug，使用 Personal Team 临时签名；方案为 MauryaUI。
- Xcode 26.6（17F113）；横屏 XCTest 窗口约 1389×970 点。
- Team 标识只通过命令行传入，没有写入工程文件。

## 结果

最终 UI 真机运行 2 项通过、0 失败、0 跳过：

- testIPadProLandscapeKeepsSidebarAndMajorRoutesUsable
- testScannerUnavailableRemainsRecoverableAcrossLandscapeAndLifecycle

测试覆盖横屏侧栏、角色/分组头像、Effects 到 Editor、键盘输入、Save、Analysis、Playback、Share 和 OTA 失败关闭状态；扫描不可用/重试、前后台恢复和取消返回手动输入。测试明确没有伪造 BLE、服务器或 OTA 成功。截图和 manifest 在 attachments/。

同一设备上的只读 BLE 检查发现 Maurya-2601，完成 GATT 服务发现、FFE1/FFE2 检查、通知订阅、设备快照和信息读取，并主动断开；报告固件 1.8.0、multilingual、地址 1 和 7 个灯组。没有执行任何写入、播放或 OTA。

## 记录的修复

1. 使用 Xcode 完整开发目录，避免 Command Line Tools 缺少 Swift Testing。
2. 把只构建应用和 UI 测试的 MauryaUI 方案与原组合方案分开。
3. WKWebView 的 detach() 改为非观测式清理，避免 SwiftUI 图失效时的独占访问崩溃。
4. 动态场景/组内模式标签改用 String.LocalizationValue，避免把本地化 key 原样显示。

## 未覆盖内容

本次没有验证 BLE 写入、播放流量、断线/重连注入、长时间运行、摄像头成功路径、麦克风/运动/能耗、VoiceOver、键盘/Stage Manager、OTA 恢复和 iOS↔Android 分享互通。这些仍需在真实设备和对应服务条件下单独验收。
