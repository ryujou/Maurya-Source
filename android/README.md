# Android 源码

android/ 是 Maurya 的 Android 客户端工程。工程名和部分历史包名仍使用 Peacock，应用命名空间为 com.example.peacock；这不会改变与 Maurya ESP32 固件通信的协议。

## 已实现的功能

- 使用 Jetpack Compose 和 Material 3 构建扫描页、设备详情页、灯效库和分享页。
- 通过 Android BLE GATT 扫描并连接 ESP32；默认服务和特征为 FFE0、FFE1（写入）和 FFE2（通知）。BleManager 负责连接状态、MTU、分片写入、通知拼帧、重连和关闭。
- 设备详情页可读取设备信息、遥测和诊断，控制全局场景、全局 RGB 以及 7 个独立灯组的颜色、模式和参数。
- feature/effects 包含灯效数据模型、Blockly JSON 编译器、Maurya Script 编译器/解释器、内置灯效、程序仓库和前台播放服务。灯效编辑器的源代码在 effect_editor/，生产资源会复制到 app/src/main/assets/effect-editor。
- 支持按组和按灯编排，协议默认几何为 7 组 × 6 颗 = 42 颗；编辑器中的循环上限也固定为 42。
- feature/palette 读取内置应援色目录，支持自定义颜色、头像裁切、WebP 校验和本地备份。
- feature/share 负责单个灯效或应援色的临时分享：规范化 JSON、SHA-256、gzip、二维码、导入预览、确认、历史去重和本地敏感词预检。服务器校验仍是最终依据。
- feature/ota 负责 OTA 清单、RSA-SHA256/镜像哈希/布局与安全版本校验，以及通过 BLE 分片传输和断点恢复。
- 应用包含中文、日文和系统语言选择；摄像头、蓝牙、麦克风和前台连接服务权限均在 AndroidManifest.xml 中声明并按页面请求。

## 目录说明

~~~
app/src/main/java/com/example/peacock/
  ble/                 BLE 扫描、GATT 会话和写入分片
  protocol/            Modbus、厂商帧和寄存器模型
  feature/effects/     灯效编译、解释、仓库和播放服务
  feature/palette/     内置/自定义应援色和头像
  feature/share/       分享信封、二维码、导入历史和审核
  feature/ota/         OTA 清单、传输和状态
  ui/                  Compose 页面、导航、语言和主题
app/src/main/assets/   编辑器和灯效资源
effect_editor/         Blockly/Maurya Script 编辑器前端源代码
tools/palette/         颜色目录和素材校验脚本
~~~

## 构建与测试

工程要求 minSdk 31、targetSdk 36、Java 11；版本号、依赖和插件见 gradle/libs.versions.toml 与 app/build.gradle.kts。

在 Windows PowerShell 中：

~~~
cd android
.\gradlew.bat test
.\gradlew.bat lint
.\gradlew.bat assembleDebug
~~~

assembleRelease 只有在提供 RELEASE_STORE_FILE、RELEASE_STORE_PASSWORD、RELEASE_KEY_ALIAS 和 RELEASE_KEY_PASSWORD 后才会执行签名构建。真机调试还需要 Android SDK、蓝牙权限和兼容的 ESP32 设备。

编辑器改动应在 effect_editor/ 中完成，再运行其 README 中的构建/测试命令生成 Android 资源；不要直接修改压缩后的 JavaScript 文件。
