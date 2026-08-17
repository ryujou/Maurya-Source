# iOS 源码

ios/ 包含 Maurya 的 SwiftUI 应用、协议核心和独立 Swift Package。应用目标面向 iOS 17，使用 Swift 6 严格并发；签名团队、配置文件和 IPA 不放在公开源码仓库中。

## 目录

| 路径 | 内容 |
| --- | --- |
| Sources/MauryaProtocol | BLE UUID、二进制读写、Modbus CRC/帧、厂商 TLV、灯效和 BLE OTA 编解码 |
| Packages/MauryaBluetooth | CoreBluetooth 中心设备传输、状态机、事务队列、通知解析和重连 |
| Packages/MauryaDevice | 寄存器映射、设备信息、7 组运行时状态和 actor 仓库 |
| Packages/MauryaEffects | Android 兼容的灯效数学、Blockly/Maurya Script 编译器、解释器和程序仓库 |
| Packages/MauryaShare | 分享信封、规范 JSON/哈希、gzip、二维码、导入历史和本地审核 |
| Packages/MauryaResources | 内置应援色、头像 WebP、用户颜色、备份和分享桥接 |
| Packages/MauryaAnalysis | 16 kHz 音频分析、Core Motion 映射、输入新鲜度和前台提供器 |
| Packages/MauryaEditor | 离线 WKWebView 编辑器、版本化桥接、自动保存和 Android 编辑器资源 |
| Packages/MauryaPlayback | 10/20 Hz 灯效调度、心跳、确认、背压、重连和生命周期 |
| Packages/MauryaOTA | 清单签名/哈希校验、BLE 分片、断点、提交和重连确认 |
| App | SwiftUI 导航、设备控制、灯效/分享/OTA 页面、权限和本地化组合 |

## 42 颗灯和传输

协议默认几何为 7 组 × 6 颗 = 42 颗；没有能力信息时各端回退到这一几何。BLE 使用 FFE0 服务、FFE1 写入和 FFE2 通知；Modbus 和厂商帧的字节规则由 [protocol/README.md](../protocol/README.md) 与 maurya-protocol.json 统一定义。iOS 不在本目录复制另一份协议 JSON，测试直接读取仓库级 protocol/ 文件。

## 构建和测试

协议核心：

~~~
swift test --package-path ios
~~~

应用项目位于 ios/App/Maurya.xcodeproj，可用 Xcode 26 或更新版本打开。无签名的通用构建示例：

~~~
xcodebuild -project ios/App/Maurya.xcodeproj \
  -scheme Maurya \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
~~~

各独立包也可在对应目录运行 swift test；涉及 iOS SDK、Swift Testing 或真机 CoreBluetooth 的命令需要完整 Xcode。模拟器和纯单元测试不能代替真实 ESP32 的 BLE、吞吐、能耗、OTA 恢复和摄像头验证。

## 当前边界

应用已经包含设备扫描/连接、7 组控制、灯效编辑入口、二维码分享导入、资源浏览、分析和 OTA 的代码路径；需要生产分享服务、AASA/Associated Domains、签名 OTA 清单或实际硬件的部分会显示为未完成/不可用状态，不把测试替身当成线上成功。
