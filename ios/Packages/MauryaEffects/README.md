# MauryaEffects 灯效核心

这是不依赖平台 UI 的 Swift 6 灯效包，目标是让 iOS 与 Android 对同一份灯效程序得到相同的值、诊断和传输数据。包不依赖第三方库，公开值为 Sendable，随机状态保存在值类型中。

## 运行时和算法

- 提供 Android 兼容的 22 个运行时输入键、60 个内置函数名，以及数字、布尔、颜色、目标和列表值。
- 实现算术、映射、插值、smoothstep、缓动、波形、周期/节拍/小节相位、死区、value noise 和四倍频 fBm。
- 颜色部分包含 Android 截断规则的 HSV/RGB 转换、混合、调色板插值、色相/饱和度/明度调整和带种子的随机颜色。
- 列表图案包含镜像、旋转、中心展开/收缩、追逐和 7 位置波形。
- 运行时输出支持 7 组和组优先的 42 颗 RGB 帧，并处理输入默认值、可用性、时间戳、过期和时间回退。

## Blockly 与 Maurya Script

- Blockly 编译器覆盖当前 Android EffectCompiler 和 effect_editor catalog 中的语句、表达式、函数、变量、控制流、列表/图案、算法、传感器/音频输入、动态颜色/HSV、组目标和逐灯目标。
- 编译阶段检查块数、变量、深度、类型、数值范围、像素模式冲突、循环尾部可观察性、有限时长、必需输入和不可达代码，并生成 Android 兼容的规范 AST 与 SHA-256。
- Script 包含词法分析、递归下降解析、类型编译、格式化和错误范围；支持 effect/function、组和 42 颗灯目标、颜色/HSV/fade、变量/列表、for/if/while/repeat/forever、break/continue、runtime/audio/sensor 输入和内置函数。
- 格式化后的源代码可以再次解析；不支持的语法显式报错，不会静默生成一个看似有效的程序。

## 程序传输和仓库

- EffectProgram 单个/批量 JSON 使用 Android 的字段集合、schema/kind 元数据、2 MiB 文件上限和 256 KiB 源码上限；导入后必须重新编译，不能信任外部 AST 或哈希。
- actor 仓库提供新增、复制、覆盖、跳过、版本冲突、稳定 ID、50 个程序上限和原子文件替换；损坏文件会先隔离再恢复默认示例。
- Swift 的 revision 是本地仓库元数据，不会写入 Android 传输 JSON；未知字段、重复 JSON key、错误类型和未知 sourceKind 会拒绝。

## 异步执行

EffectAsyncCompiler 和 EffectAsyncInterpreter 使用结构化并发、协作取消和单调时钟 deadline；检查点位于编译阶段、token/block、VM 指令、循环和函数调用边界。失败的异步帧不会推进解释器状态；同步 API 仍保留给已受控的纯测试。

## 验证

~~~
swift test --package-path ios/Packages/MauryaEffects -c debug -Xswiftc -warnings-as-errors
swift test --package-path ios/Packages/MauryaEffects -c release -Xswiftc -warnings-as-errors
~~~

测试直接读取 Android 的 Maurya Script 资源和 protocol/fixtures/effect-algorithms.json，覆盖算法黄金值、格式化往返、恶意输入、传输字段、仓库原子性、取消/deadline 和 42 颗灯输出。包测试不代替真实传感器录音或连接灯具的播放验收。
