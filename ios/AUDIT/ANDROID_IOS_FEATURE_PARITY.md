# Android → iOS 功能对等审计

审计日期：2026-08-09
Android 基线：当前工作区 `android/app`、`android/effect_editor` 与共享 `protocol/`
iOS 基线：当前工作区 `ios/App` 与 `ios/Packages/*`

## 判定规则

- **本地已实现**：用户路径、领域实现和自动化测试均已落地；不等于真机或生产验收完成。
- **本地已实现／外部 Gate**：本地代码已闭环，但必须依赖 iPhone、ESP32、生产服务、签名材料或法律结论验收。
- **平台等价替代**：不复制另一平台 API 形态，但产品行为、安全边界与可见状态等价。
- **有意不实现**：经 iOS 安全/审核约束明确排除，不可再写成“已完成”。

README、绿色编译和 mock 本身不作为功能证据；每项必须能指向实现与测试。

## 当前结论

协议、42 灯几何、BLE 前台链路、设备控制、资源与自定义色板、效果程序库、Blockly/Maurya Script 编辑、分析输入、前台效果播放、分享、OTA 的**本地实现已形成完整用户路径**。此前审计中“缺失/未接 UI”的判断已全部复核并更新。

尚不能宣布“最终与安卓版完全一致”，因为下列外部证据仍未取得：真实 ESP32/iPhone BLE 与 20 Hz 长稳、真实摄像头扫码、Android↔iPhone WebP/备份/分享互导、生产分享 API/AASA、生产 OTA 签名链与升级恢复、素材逐项版权批准、真机辅助功能与能耗审计。

## 逐屏与 App composition

| 用户能力 | 状态 | Android 证据 | iOS 实现证据 | 自动化证据 / 剩余 Gate |
|---|---|---|---|---|
| 扫描、停止、FFE0/名称筛选、连接、断开 | 本地已实现／外部 Gate | `ui/screen/scan/ScanScreen.kt`, `ble/BleManager.kt`, `BleAdvertisementMatcher.kt` | `ScanScreen.swift`, `LiveDeviceService.swift`, `MauryaCentralTransport.swift`, `BluetoothAdvertisementMatcher.swift` | matcher/state/queue/App fake tests；需双设备、拒权、蓝牙开关与断连真机测试。 |
| Android demo/debug 设备 | 平台等价替代 | `MauryaApp.kt` 的 `demoMode` | `HardwareReviewGuideView.swift` 提供无硬件审阅路径，但绝不伪报写设备成功 | iOS release 约束要求 unavailable 必须真实显示；不把 Android 调试模拟器当生产功能。 |
| 设备快照、1 秒遥测、7 组 HSV/mode/参数 | 本地已实现／外部 Gate | `DetailScreen.kt`, `RuntimeRepository.kt` | `DeviceDetailView.swift`, `DeviceGroupControl.swift`, `DeviceRepository.swift` | Device/App repository tests；需真实寄存器读写与长轮询。 |
| scene、global LED、全组写、清诊断 | 本地已实现／外部 Gate | `SceneCard.kt`, `GlobalLedCard.kt`, `RuntimeRepository` | `DeviceGlobalControl.swift`, `DeviceDiagnosticsSection.swift`, `LiveDeviceService.swift` | `LiveDeviceServiceTests.swift` 与 package mapping tests；需硬件确认。 |
| 内置角色/团体/应援色搜索、预览、应用 | 本地已实现／外部 Gate | `CharacterPaletteScreen.kt`, palette repositories | `SupportColorBrowserView.swift`, `SupportColorPreview.swift`, `BuiltinResources.swift` | 560 项 inventory/hash tests、selection tests；素材法律 Gate 未关闭。 |
| 自定义色板创建、编辑、删除、Undo、备份 | 本地已实现／外部 Gate | `CustomPalettePanel.kt`, `CustomPaletteViewModel.kt` | `ResourceLibraryView.swift`, `CustomPaletteEditorView.swift`, `LiveResourceLibraryService.swift` | repository/backup/App tests；需真机照片选择和 Android 互导。 |
| 图片裁切/旋转/取色、96×96 WebP≤6144B | 本地已实现／外部 Gate | `CustomAvatarProcessor.kt` | `AvatarImageProcessor.swift`, pinned `CWebP` 1.6.0 | 20 个 Resources tests（含可复现 host measurement）；需视觉裁切一致性与 Android 解码真测。 |
| 设备帮助 | 本地已实现 | `HelpScreen.kt` | `DeviceHelpView.swift` | 路由/本地化 parity tests；内容仍应做产品文案复核。 |
| 应用内语言切换（系统/简中/日文） | 本地已实现 | Android locale picker 与持久化设置 | `AppLanguageSettings.swift`, `AppHomeView.swift`，文件原子持久化并注入 SwiftUI locale | `AppLanguageSettingsTests.swift`、三语言 key parity；编辑器、资源名和分享名均跟随所选语言。 |
| 效果程序列表、双语命名、CRUD、复制、积木转代码 | 本地已实现 | `EffectLibraryScreen.kt`, `EffectViewModel.kt` | `EffectLibraryView.swift`, `LiveEffectProgramService.swift`, `EffectProgramRepository.swift` | App composition tests + 99 个 Effects tests。 |
| 效果单项/整库导出、导入预览、COPY/OVERWRITE/SKIP | 本地已实现 | `EffectProgramTransfer.kt` | `EffectProgramTransfer.swift`, `EffectProgramTransferDocument.swift`, `EffectLibraryView.swift` | 预览显示有效数、冲突数、逐项错误和程序名；strict wire/repository/App tests；需 Android 真实文件双向互导。 |
| Blockly 离线编辑、保存、Undo/Redo、诊断、运行 | 本地已实现／外部 Gate | Android WebView + `android/effect_editor` | `EffectEditorHostView.swift`, `MauryaEditorView.swift`, verified editor bundle | 11 Editor Swift tests、3 editor unit、15 Playwright；需 iPhone 键盘/VoiceOver/WebView 真测。 |
| Maurya Script 编辑、格式化、编译、运行 | 本地已实现 | Android script compiler/editor | `EffectScriptCompiler.swift`, `EffectScriptFormatter.swift`, script editor host | 8 个 Android sample 逐字节 hash+compile/frame、UTF-16 range、stateful builtin 和函数作用域 golden；真机分析输入另列 Gate。 |
| 分析：motion/audio、快照、过期、虚拟输入、归零、灵敏度 | 本地已实现／外部 Gate | `EffectSensorHub.kt`, Effect screen input monitor | `AnalysisControlView.swift`, `LiveAnalysisControlService.swift`, `AnalysisInputHub.swift` | 16 Analysis tests 与 App state tests；实时 tap 竞争时丢弃有界 chunk 而不阻塞音频线程；需真实麦克风 route/运动坐标验证。 |
| 选中效果 + 分析输入 + BLE 前台播放、暂停/恢复/停止 | 本地已实现／外部 Gate | `EffectPlaybackService.kt`, `EffectViewModel.play` | `LivePlaybackControlService.swift`, `EffectPlaybackActor.swift`, `AnalysisPlaybackInputSource.swift` | UI 仅在 actor 真正 running 后显示运行；required input 严格超过 1 秒 stale 即 fail；8 个 Playback tests 与 App fail-closed tests；需 20 Hz/30 分钟硬件验收。 |
| OTA 检查、签名/哈希验证、BLE 续传、进度、取消、提交、重连确认 | 本地已实现／外部 Gate | `OtaCoordinator.kt`, `OtaViewModel.kt` | `OTAWorkflowView.swift`, `LiveOTAAvailabilityService.swift`, `OTAWorkflow.swift`, `AppOTADeviceTransport.swift` | 26 OTA tests；256 KiB Range/ETag 缓存、容量检查和原子完成已覆盖；缺生产 URL、公钥、签名固件与恢复演练。 |
| 分享创建、QR、token/URL 输入、扫码、预览、确认导入 | 本地已实现／外部 Gate | `ShareScreen.kt`, `ShareViewModel.kt`, scanner | `ShareImportView.swift`, `ShareQRScannerSheet.swift`, `LiveShareImportService.swift`, `ShareCameraScanner.swift` | 确认前二次 token 去重、marker 竞争及 actor 重入 busy gate；47 Share tests 与 App workflow tests；缺生产 API/AASA、真机相机与双端 E2E。 |
| device/share deep link | 本地已实现 | Android navigation/share entry | `DeepLinkParser.swift`, `AppRootView.onOpenURL` | `DeepLinkParserTests.swift`, `AppRouterTests.swift`；Universal Link 仍依赖生产 AASA。 |

## 领域与持久化

| 领域 | 状态 | iOS 证据 | 关键约束 |
|---|---|---|---|
| 协议 schema/golden | 本地已实现 | `protocol/maurya-protocol.json`, `golden-vectors.json`, `MauryaProtocol` | 7×6=42、显式端序、CRC、0x03/06/10/41、TLV/effect/OTA；251 checks/14 vectors，生产源码 line coverage 99.70%。 |
| Device repository | 本地已实现／外部 Gate | `MauryaDevice` | 64-register 上限、22+35 分区、generation 防陈旧写回、结构化轮询。 |
| Resource inventory | 本地已实现 | `MauryaResources` | 560 资源逐文件 hash，App 列表按需显示真实角色/团体头像；当前个人本地使用范围不以素材授权为阻塞，公开分发仍需另行审查。 |
| CustomPalette repository | 本地已实现 | `CustomPaletteRepository.swift` | 50 项、NFC/长度、原子写、hash 文件名、orphan repair、Undo receipt。 |
| EffectProgram repository | 本地已实现 | `EffectProgramRepository.swift` | 50 项、revision、原子写、损坏隔离、Android 14 字段 transfer。 |
| Share import history/transaction | 本地已实现／服务 Gate | `ShareImportHistory.swift`, App consumers | token hash 去重、预览后确认、失败 rollback；生产并发可见性仍需服务端 E2E。 |
| OTA checkpoint | 本地已实现／硬件 Gate | `FileOTACheckpointStore.swift`, `OTAWorkflow.swift` | 取消保留 checkpoint，显式 cancel 才发 BLE_CANCEL，commit once。 |

## BLE、并发与安全边界

| 能力 | 状态 | 证据 / 说明 |
|---|---|---|
| FFE0/FFE1/FFE2/CCCD | 本地已实现／硬件 Gate | `MauryaCentralTransport`, `MauryaProtocol`；ready 只在服务、双特征与 notify 确认后发出。 |
| MTU 分片、withResponse、串行事务、响应匹配 | 本地已实现 | `WriteFragmenter`, `BluetoothTransactionQueue`, `ResponseMatcher`；18 Bluetooth tests。 |
| timeout、取消、generation、指数重连 | 本地已实现 | 2 秒响应超时、阶段 timeout、45 秒封顶；纯状态机/队列 tests。 |
| State restoration | 有意不启用 | App 不声明 `bluetooth-central` 后台模式，因此 `restorationIdentifier == nil`。曾启用会触发系统终止，现有默认值回归测试。若产品批准后台 BLE，须连同 entitlement、隐私、功耗与真机 kill/restore 一起重新开启。 |
| 编译/解释取消与 deadline | 本地已实现 | `EffectAsyncCompiler`, `EffectAsyncInterpreter` 使用 structured async、cooperative checkpoint、monotonic deadline；有取消/超时 tests。 |
| 前后台策略 | 平台等价替代 | `AppRootView` 在 inactive/background 停止 analysis，并让 playback 结束当前 BLE session 后保持 paused；跨页面不停止，回前台由用户显式恢复并重建 session。未申请后台音频/BLE；Android foreground service 行为不直接复制，除非产品与审核 Gate 批准。 |
| OTA URL 安全 | 本地已实现 | HTTPS + allowlist + 禁 userinfo；初始 URL 和 URLSession 最终 URL均复核，防跨 host/降级重定向；26 OTA tests。 |
| 分享网络安全 | 本地已实现／服务 Gate | 严格 `https://xtbang.top`、拒绝重定向、bounded retry/size/content-type/hash；生产合约仍需 staging。 |

## 发布与 App Store 状态

| 项目 | 状态 |
|---|---|
| Bluetooth/Camera/Microphone/Motion 使用说明 | 已配置；文案与真实入口一致。 |
| Privacy manifest | `PrivacyInfo.xcprivacy` 已存在；归档前仍需用最终二进制重新扫描 required-reason API。 |
| App icon | 1024×1024 资源已生成并接入；归档/上传验证待做。 |
| 第三方许可 | libwebp BSD-3-Clause 原许可保留，App bundle 含 `ThirdPartyNotices.txt`；需归档确认资源实际包含。 |
| 后台模式/Associated Domains | 当前均未声明；符合 fail-closed 设计。Universal Link 要上线必须由生产 AASA 与 entitlement 联合开启。 |
| 素材版权 | 当前仅个人本地使用，不阻塞安装或显示 560 项角色/团体图片；若以后公开、商业、TestFlight 或 App Store 分发，重新启用逐项审查 Gate。 |
| 签名与商店资料 | **外部 Gate**：Team/App ID、证书、隐私标签、截图、审核备注、支持/隐私 URL 尚需生产账户。 |

## 必须关闭的外部 Gate

1. **BLE/ESP32 真机矩阵**：至少 iOS 17/当前 iOS，各跑扫描拒权恢复、两个同名设备、MTU 分片、断电重连、1,000 请求、42 像素 20 Hz 30 分钟、内存与能耗。
2. **跨端数据**：Android 导出 effect bundle/custom palette/share，iPhone 导入再导出，反向重复；逐字节核对 schema、hash、WebP 与冲突策略。
3. **分享生产链**：staging/OpenAPI、限流、审核、过期 token、AASA、真实二维码相机、Android↔iPhone 双向导入。
4. **OTA 生产链**：真实 HTTPS host、RSA 公钥轮换、签名 manifest/firmware、断电/断网/杀 App/续传/回滚/secureVersion 演练。
5. **分析真机**：麦克风拒权、HFP/有线/扬声器 route、中断、采样率变化、真实运动轨迹与 Android 共用 fixture。
6. **UI/可访问性**：iPhone/iPad、横竖屏、Dark/Increase Contrast、AX5、VoiceOver、键盘、Reduce Motion、相机与 PhotosPicker。
7. **可选公开发布流程（不属于当前个人版范围）**：逐项素材授权、最终隐私清单、归档 required-reason 扫描、商店签名、截图、审核备注和 App Store 上传验证。

## 审计限制

- 本文证明当前源码的本地实现范围，不把 simulator/mock 当作硬件或生产服务验收。
- Android 专属 foreground service 与 iOS scene/background policy 以产品行为等价为目标，不要求 API 同构。
- 任何外部 Gate 未关闭前，都不得在发布文档中写“与安卓版完全一致”或“可发布”。
