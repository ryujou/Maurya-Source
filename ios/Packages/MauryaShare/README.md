# MauryaShare 临时分享

本包实现 Android/iOS 共用的 v1 分享流程：单个灯效或应援色生成规范信封，上传后返回临时 token/二维码，导入端先严格校验、预览，再由用户确认写入本地对象。服务器审核仍是最终依据。

## 实现内容

- canonical JSON、内容 SHA-256、gzip、10 位 token、Universal Link/maurya:// 解析和严格字段校验。
- ShareAPIClient.production 只接受 https://xtbang.top 的固定主机，拒绝重定向，创建请求使用幂等键且不自动重试；元数据/Blob GET 对超时、离线、429 和 5xx 使用有界退避。
- 在预览前检查状态、主机、媒体类型、声明/实际大小、token、日期、哈希、Blob 长度、信封类型、gzip 和业务负载；ShareImportHistory 只保存 token 哈希和本地 ID，按最新优先去重并限制 256 条。
- ShareWorkflow 把本地敏感词预检放在上传前；导入需要显式确认，并在提交前再次检查历史，避免取消或旧任务覆盖新状态。
- ShareQRCodeGenerator 使用 CoreImage 生成 1024 像素、高纠错、四模块静区的二维码；Vision provider 支持静态图片解析，AVFoundation provider 负责 iOS 17 相机流和取消/前后台/中断生命周期。
- gzip 使用小型 C libz 适配器，校验单成员、原始 deflate、CRC32、ISIZE、尾部数据和 2 MiB 解压上限；头像数据只接受经过 base64、大小、哈希和 96×96 WebP 结构检查的内容。

## 外部条件

仓库不包含分享服务 OpenAPI、可用 staging、AASA 部署或留存/限流策略，因此包测试不是网络 E2E。相机权限文案和导航由 App 管理，Android↔iOS 两台设备互换仍需真实服务和设备矩阵。

~~~
swift test --package-path ios/Packages/MauryaShare -c debug
swift test --package-path ios/Packages/MauryaShare -c release
~~~
