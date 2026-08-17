# Maurya 源代码

这里保存 Maurya 的客户端、ESP32-C3 固件、通信协议和开发辅助源码。仓库只放可阅读、可构建的源文件；APK、IPA、固件镜像、发布压缩包和本地构建目录不在这里。

## 目录

| 目录 | 内容 | 入口 |
| --- | --- | --- |
| [android/](android/README.md) | Android 应用、灯效运行时、分享与 OTA | [android/README.md](android/README.md) |
| [ios/](ios/README.md) | SwiftUI 应用和 Swift Package | [ios/README.md](ios/README.md) |
| [esp32/](esp32/README.md) | ESP32-C3 固件、板端网页和烧录工具 | [esp32/README.md](esp32/README.md) |
| [protocol/](protocol/README.md) | JSON 协议基线、黄金向量和校验脚本 | [protocol/README.md](protocol/README.md) |
| [tools/](tools/README.md) | 网站构建、校验和编辑器演示脚本 | [tools/README.md](tools/README.md) |

## 当前硬件基线

- 目标芯片为 ESP32-C3。
- 灯珠按 7 组、每组 6 颗计算，共 42 颗；协议中的逻辑顺序是“组优先”。
- 固件同时提供 NimBLE、USB Serial Modbus 和 Wi-Fi SoftAP 控制入口。
- SoftAP 启动时可扫描周围网络，在 1、6、11 三个非重叠信道中选择干扰评分最低的信道；扫描失败时使用配置的备用信道。
- 固件把 Wi-Fi 最大功率限制为 34 个四分之一 dBm 单位（8.5 dBm），BLE 广播和连接功率使用 ESP_PWR_LVL_P6（6 dBm），并在设置后读取校验。

## 源码关系

Android 和 iOS 都从 protocol/ 的协议描述及黄金向量取得跨平台常量。ESP32 的 components/lumia_protocol 实现 Modbus、厂商帧、灯效会话和 OTA 数据路径；客户端在各自的 BLE、USB 或网络适配层调用这些协议。编辑器的源代码位于 android/effect_editor/，iOS 通过同步脚本复用同一份离线资源。

## 常用入口

~~~
Android：打开 android/，运行 gradlew.bat test 或在 Android Studio 中运行 app
iOS：打开 ios/App/Maurya.xcodeproj；Swift 包测试使用 swift test --package-path ios
ESP32：进入 esp32/lumia_esp32，使用 idf.py set-target esp32c3 和 idf.py build
协议：在仓库根目录运行 python protocol/validate_protocol.py
~~~

每个目录的 README 只记录当前代码中已经存在的接口、配置和验证方式；需要真实硬件、签名证书或发布服务器的步骤会明确标注为外部条件。许可文件单独放在仓库根目录。
