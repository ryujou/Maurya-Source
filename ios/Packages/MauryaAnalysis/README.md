# MauryaAnalysis 音频与运动分析

这是 iOS 端的输入和分析包，负责把音频、运动、压力和距离等输入整理成灯效运行时可消费的快照。包本身不保存或上传音频，也不修改应用的权限和后台配置。

## 实现内容

- AnalysisInputHub 是 actor，聚合物理采样和每个运行时输入的虚拟覆盖值；每个样本带单调时间戳、可用性和权限状态，严格按超过 1000 ms 判定过期。
- 音频分析固定为 16 kHz 单声道、512 样本窗口，包含 Hann 窗、RMS、峰值、低/中/高频段、节拍阈值、240 ms 抑制时间、8 个间隔的 BPM 和 40–240 BPM 限幅，与 Android 处理路径保持一致。
- 运动回放覆盖加速度、摇动、陀螺仪、俯仰/横滚/偏航、航向归一化、姿态归零、气压换算和距离映射；环境光在公开 iOS API 下保持不可用。
- AppleAudioInputProvider 使用 AVAudioEngine，按设备原生非交错 Float32 格式接收并混为单声道，再在分析线程重采样；路由变化、打断和取消会拆除旧 tap 并重建。
- CoreMotionInputProvider 使用 CMMotionManager，只订阅当前灯效需要的输入；权限拒绝、路由丢失或打断会产生不可用/过期状态。
- 固定容量 PCM 环形缓冲使用 OSAllocatedUnfairLock，音频回调抢不到锁时丢弃当前块，不等待 actor 或分析任务。

## 集成约束

应用必须提供 NSMicrophoneUsageDescription 和 NSMotionUsageDescription，并在用户明确开始音频响应灯效时才调用 start。页面离开、播放停止、权限变化或进入后台时要调用 stop；本包不承诺后台持续采样，也不自行添加 UIBackgroundModes。

## 验证

~~~
swift test --package-path ios/Packages/MauryaAnalysis -c debug
swift test --package-path ios/Packages/MauryaAnalysis -c release
~~~

包测试覆盖纯分析、环形缓冲、输入新鲜度和运动映射；真实麦克风、蓝牙音频路由、电话打断、能耗、温度和长时间运行仍需在实体 iPhone 上验证。
