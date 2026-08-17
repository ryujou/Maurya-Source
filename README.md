# Maurya

<p align="center">
  <strong>为 7 组 × 6 颗灯打造的跨平台应援灯控制系统</strong><br>
  Android · iOS · ESP32-C3 · BLE · Wi-Fi Web · 42 像素灯效 · Maurya Script
</p>

<p align="center">
  <img alt="Android source" src="https://img.shields.io/badge/Android-source-3DDC84?logo=android&logoColor=white">
  <img alt="iOS source" src="https://img.shields.io/badge/iOS-source-111111?logo=apple&logoColor=white">
  <img alt="ESP32-C3 source" src="https://img.shields.io/badge/ESP32--C3-source-E7352C">
  <img alt="LED geometry" src="https://img.shields.io/badge/LEDs-7%C3%97%206%3D42-7C3AED">
</p>

<p align="center">
  <a href="#-公开仓库范围">源码范围</a> ·
  <a href="#-5-分钟快速开始">快速开始</a> ·
  <a href="#-功能全览">功能</a> ·
  <a href="#-硬件与接线">硬件</a> ·
  <a href="#-从源码构建">构建</a> ·
  <a href="#-参与开发">参与开发</a>
</p>

---

Maurya 将手机端灯效创作、设备控制、临时分享、固件升级和离线烧录相关源码放在一个跨平台工程中。当前硬件基线固定为 **ESP32-C3 + 7 路输出 + 每路 6 颗 WS2812 = 42 颗可独立控制像素**。本仓库以源码、协议和开发文档为主，真实设备、签名环境和外部服务需要在本地或对应环境中验证。

> [!IMPORTANT]
> 本仓库只保存源码、协议和文档；APK、IPA、固件 BIN、烧录 EXE、ZIP、发布清单和分享服务端不在这里。需要真实设备、签名或外部服务的部分会明确标注验证边界。

## 📦 公开仓库范围

| 内容 | 状态 | 说明 |
| --- | --- | --- |
| Android、iOS、ESP32-C3 源码 | 包含 | 各平台入口和构建说明见对应目录 README |
| 通信协议、黄金向量和校验脚本 | 包含 | 用于保持客户端、固件和工具之间的数据一致 |
| Web UI 与本地开发工具源码 | 包含 | 仅包含当前公开目录中的工具和资源 |
| APK、IPA、固件镜像和烧录包 | 不包含 | 请在本地按构建说明生成 |
| 分享服务端、生产发布站点和私有素材 | 不包含 | 客户端保留协议、界面和本地校验逻辑 |

## 🚀 5 分钟快速开始

### 获取源码

~~~powershell
git clone https://github.com/ryujou/Maurya-Source.git
cd Maurya-Source
python protocol/validate_protocol.py
~~~

协议校验脚本可先确认当前工作区的 7 × 6 = 42 几何、帧长度和黄金向量。之后按目标平台进入对应目录：

| 目标 | 入口 |
| --- | --- |
| Android | <code>android/README.md</code>，使用 Android Studio 或仓库内 Gradle Wrapper |
| iOS | <code>ios/README.md</code>，使用 Xcode 和 Swift Package 测试 |
| ESP32-C3 | <code>esp32/README.md</code>，使用 ESP-IDF 6.0.1 |
| 协议 | <code>protocol/README.md</code>，运行校验器和向量测试 |
| 工具 | <code>tools/README.md</code>，查看站点、演示和辅助脚本 |

### 首次接线

先按硬件章节确认供电、共地和数据线，再刷入本地构建的固件。普通控制和 OTA SoftAP 都由 ESP32-C3 固件提供；BLE、USB Serial 和 Wi-Fi Web 是三条相互独立的控制入口。

## 🎛️ 功能全览

### 灯光与设备控制

- 以 7 组 × 6 颗为固定几何，每颗像素拥有独立 RGB、相位、波形和动画状态
- 支持单色、应援色、彩虹、渐变、呼吸、追逐、噪声和脚本驱动的灯效
- 支持 BLE、USB Serial Modbus 和 Wi-Fi SoftAP Web 控制
- Wi-Fi SoftAP 可在 1、6、11 信道中按周围干扰评分选择信道，扫描失败时使用配置的备用信道
- Wi-Fi 最大功率固定为 8.5 dBm；BLE 广播和连接功率固定为 6 dBm，并在固件中读取校验

### Android 应用

Android 端使用 Jetpack Compose 组织设备、灯效、颜色、脚本、分享和 OTA 页面。主要代码位于 <code>android/app</code>，灯效编辑器位于 <code>android/effect_editor</code>，测试和构建说明位于 [android/README.md](android/README.md)。

### iOS 应用

iOS 端包含 SwiftUI 应用和多个 Swift Package，覆盖 BLE、设备模型、灯效、脚本编辑、播放、分享、OTA 和资源管理。包之间共享协议和 42 像素几何；真机蓝牙、签名和生产服务仍需在 macOS/Xcode 环境中验证。

### Maurya Script 与 Blockly

编辑器同时提供可视化积木和文本脚本入口，目标可以是灯组，也可以是 42 颗像素。下面的示例让每颗灯以不同相位显示彩虹色：

~~~text
effect "42颗彩虹" {
    forever {
        for (let i = 1; i <= 42; i += 1) {
            pixelAt(i).hsv(time.elapsedMs / 18 + i * 9, 255, 255);
        }
        wait(50ms);
    }
}
~~~

编辑器源代码和测试以 <code>android/effect_editor</code> 为准；跨平台协议常量和向量以 <code>protocol</code> 为准。

### 7 天临时分享与二维码

客户端包含单个灯效或应援色的 7 天临时分享流程：生成规范化数据、压缩和摘要，展示二维码，导入前预览并确认。分享内容会经过客户端敏感词快速预检，服务端地址和服务端实现不属于本公开源码仓库；分享码有效期上限为 604800 秒。

### 固件、Web UI 与通信

ESP32-C3 固件将协议解析、灯效运行时、Web UI、OTA、存储和监控组件分开组织。网页控制台随固件资源构建并从 SoftAP 提供；BLE OTA 还会校验签名、镜像摘要、版本和分区布局。

### 烧录与开发工具

<code>esp32/lumia_esp32/tools/production_flasher</code>、<code>esp32/tools/lumia_host</code> 和 <code>tools</code> 提供本地烧录、主机调试、站点辅助和演示脚本。发布包不会随源码仓库提交，工具所需的私有站点工作区也不在这里。

## 📱 平台与完成度

| 能力 | Android | iOS | ESP32/Web | 协议/工具 |
| --- | --- | --- | --- | --- |
| BLE 设备控制 | 源码与测试 | Swift Package 源码 | NimBLE 固件 | 共用服务与特征约定 |
| USB / Wi-Fi 控制 | USB 与 Web 适配 | Web/网络适配源码 | Serial Modbus、SoftAP | 帧格式和向量 |
| 灯效与脚本 | Compose、Blockly、播放器 | SwiftUI、编辑器、播放器 | 运行时和效果组件 | 42 像素几何 |
| 临时分享 | 7 天分享、二维码、本地预检 | 分享包和本地预检 | 外部服务协议入口 | 规范化、压缩、摘要 |
| OTA | 页面和状态管理 | OTA 包源码 | BLE OTA、双 OTA 分区 | 签名和镜像校验 |
| 真实设备验证 | 需要 Android 设备 | 需要 macOS/Xcode 和 iOS 设备 | 需要 ESP32-C3 与灯板 | 运行本地测试 |

## 🧭 系统架构

下面的关系图只描述本仓库中的源码边界；分享服务端位于仓库外。

~~~mermaid
flowchart LR
    accTitle: Maurya source architecture
    accDescr: Android and iOS clients use shared protocol definitions to reach ESP32-C3 over BLE, USB, or Wi-Fi, while tools and the external share service remain separate boundaries.

    clients["Android / iOS clients"]
    editor["Script / Blockly editor"]
    protocol["Protocol schema / vectors"]
    transport["BLE / USB / Wi-Fi"]
    firmware["ESP32-C3 firmware"]
    pixels["7 × 6 = 42 WS2812"]
    share["7-day share service outside repo"]
    tools["Local tools and tests"]

    editor --> clients
    clients --> protocol
    clients --> transport
    transport --> firmware
    firmware --> pixels
    clients --> share
    tools --> protocol
    tools --> editor

    classDef client_style fill:#dbeafe,stroke:#2563eb,stroke-width:2px,color:#1e3a5f
    classDef firmware_style fill:#dcfce7,stroke:#16a34a,stroke-width:2px,color:#14532d
    classDef external_style fill:#fef9c3,stroke:#ca8a04,stroke-width:2px,color:#713f12

    class clients,editor,protocol,transport,tools client_style
    class firmware,pixels firmware_style
    class share external_style
~~~

## 🔌 硬件与接线

| 项目 | 当前约定 |
| --- | --- |
| 主控 | ESP32-C3 开发板 |
| 灯珠 | WS2812，7 路数据，每路 6 颗，共 42 颗 |
| 数据 GPIO | GPIO0、GPIO1、GPIO3、GPIO7、GPIO10、GPIO20、GPIO21 |
| 状态与输入 | GPIO8 状态灯、GPIO9 模式按键、GPIO4 休眠开关 |
| 供电 | 独立 5 V 电源，建议额定电流不低于 3 A |
| 布线 | 灯板与主控共地；数据线按固件通道顺序连接 |
| 信号完整性 | 可按实际线长增加电平转换和 220–470 Ω 串联电阻 |

42 颗 WS2812 全白时的理论电流约为 2.52 A，实际设计还要考虑电源余量、线损、亮度限制和连接器温升。不要把满载灯板长期直接接在开发板 USB 供电上。更完整的管脚、供电和构建说明见 [esp32/docs/README.md](esp32/docs/README.md)。

## 🗂️ 仓库结构

| 路径 | 内容 |
| --- | --- |
| [android/](android/README.md) | Android 应用、灯效编辑器、测试和资源 |
| [ios/](ios/README.md) | SwiftUI 应用、Swift Package 和 iOS 测试 |
| [esp32/](esp32/README.md) | ESP-IDF 固件、Web UI、主机测试和烧录工具 |
| [protocol/](protocol/README.md) | 协议描述、黄金向量和校验器 |
| [tools/](tools/README.md) | 站点、渲染、演示和构建辅助脚本 |
| [LICENSE](LICENSE) | 仓库许可证文本 |
| [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) | 第三方依赖、素材和标识说明 |

## 🛠️ 从源码构建

### Android

~~~powershell
cd android
.\gradlew.bat test
.\gradlew.bat lint
.\gradlew.bat assembleDebug
~~~

发布签名需要本地 Gradle 属性和签名文件，具体变量见 [android/README.md](android/README.md)；签名文件和 APK 不应提交到仓库。

### iOS

~~~bash
swift test --package-path ios
xcodebuild -project ios/App/Maurya.xcodeproj -scheme Maurya -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
~~~

iOS 构建需要 macOS/Xcode；真机安装、蓝牙权限和 IPA 签名属于本地发布环境。

### ESP32-C3 固件

~~~powershell
cd esp32\lumia_esp32
idf.py set-target esp32c3
idf.py build
idf.py -p COMx flash monitor
~~~

固件基线为 ESP-IDF 6.0.1。网页资源构建可在 <code>esp32\lumia_esp32\web_ui</code> 中运行：

~~~powershell
npm ci
npm run build
npm test
python ..\tools\build_web_assets.py
~~~

### 协议与工具

~~~powershell
python protocol\validate_protocol.py
~~~

工具目录下的脚本按各自 README 说明运行；部分站点渲染和发布脚本需要仓库外的素材或工作区。

## 🧪 测试与质量门槛

- 协议校验器覆盖帧长度、字段范围、7 × 6 = 42 几何和黄金向量
- Android 运行单元测试、Lint、编辑器测试和构建任务
- iOS 运行 Swift Package 测试，并在需要时做真机蓝牙与分享流程验证
- ESP32 运行组件构建、主机测试和 Web UI 测试
- 真机通信距离、BLE OTA 中断恢复、SoftAP 自动信道、供电温升和长时间灯效仍需要现场验证

建议在提交改动前至少运行受影响目录的本地测试，并在 PR 中注明操作系统、工具链版本和测试结果。

## 🩺 常见问题

| 现象 | 检查方向 |
| --- | --- |
| 搜不到 BLE 设备 | 确认设备处于 BLE 模式、系统蓝牙权限已授予，并检查 GPIO9 模式输入 |
| 打开不了 Wi-Fi 控制页 | 连接固件创建的 SoftAP 后访问 <code>http://192.168.4.1/</code>，并确认设备已完成启动 |
| Wi-Fi 信道和预期不同 | 自动选择只在 1、6、11 中决策；扫描失败会回退到配置的备用信道 |
| 灯珠不亮或颜色错位 | 检查 5 V、共地、数据 GPIO 顺序、首颗灯方向和串联电阻 |
| iOS 找不到 IPA | 源码仓库不含 IPA，需要在 macOS/Xcode 中自行构建和签名 |
| 分享码无法导入 | 检查是否超过 7 天、内容是否通过本地预检，以及外部分享服务是否可用 |

## 🗺️ 当前限制与后续验证

- 灯板几何固定为 7 × 6 = 42，本仓库不再按其他数量描述默认硬件
- 发布包、生产站点和分享服务端不属于公开源码范围
- iOS 的设备兼容性、签名和生产环境行为需要在 macOS/Xcode 与真实设备上复核
- Wi-Fi/BLE 发射功率限制和自动信道逻辑已写入固件，但覆盖距离仍受天线、外壳、供电和现场干扰影响
- 现场测试、长时间运行和 OTA 故障注入结果应随版本记录，不能仅由主机测试替代

## 🤝 参与开发

欢迎提交 Issue 和 Pull Request。无论是修复文档、补充测试、改进灯效、完善跨平台实现，还是发现硬件兼容性问题，都可以先从一个小而明确的改动开始。

建议的 PR 流程：

1. 先查看相关目录 README 和现有协议向量，确认改动边界
2. 从最新主分支创建独立分支，保持每个 PR 聚焦一个主题
3. 运行受影响平台的测试，并在描述中记录命令、环境和未完成的真机验证
4. 如果修改协议、几何或公共数据格式，同时更新 <code>protocol/</code>、客户端和固件的对应说明
5. 不要提交签名证书、访问令牌、私有服务凭据、发布包或未经确认的第三方素材

提交 PR 前不必追求一次性覆盖所有平台；清晰的变更范围、可复现的测试结果和待验证事项更有助于审查。

## ⚖️ 许可与第三方说明

仓库许可证文本见 [LICENSE](LICENSE)。第三方依赖、图标、字体、标识和素材的来源及原有条款见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)、[android/THIRD_PARTY_LOGO_NOTICES.md](android/THIRD_PARTY_LOGO_NOTICES.md) 和 [ios/App/Resources/ThirdPartyNotices.txt](ios/App/Resources/ThirdPartyNotices.txt)。使用或再分发前，请同时遵守这些文件和各依赖上游的要求。
