# MauryaBluetooth 蓝牙传输

这是 Swift 6 CoreBluetooth 中心设备传输层，对接 ESP32 的 Maurya GATT 配置：

- FFE0 服务
- FFE1 写入（带响应）
- FFE2 通知/指示

CoreBluetooth 对象和代理保持在 MainActor；有界事务队列、响应匹配和增量 Modbus 解码由 actor 保护。状态 reducer 通过连接代次拒绝旧回调，避免断线重连后把旧数据交给新会话。

## 运行规则

- 应用必须提供 NSBluetoothAlwaysUsageDescription。当前工程默认前台运行，不配置状态恢复或 bluetooth-central 后台模式。
- 明确调用 close() 释放传输。用户主动断开不会自动重连；意外断开使用上限 45 秒的指数退避。
- 只有服务发现、FFE1/FFE2 检查和通知订阅全部完成后才发出 ready。
- 写入会按 negotiated maximumWriteValueLength 分片；收到通知后交给 Modbus 解码器和事务队列。

## 验证边界

Swift 包测试覆盖状态机、广告匹配、队列、响应匹配、分片和重连算法，但不能替代真实 ESP32 的权限拒绝、掉电、1000 次串行请求、20 Hz 流量、后台行为和内存泄漏检查。
