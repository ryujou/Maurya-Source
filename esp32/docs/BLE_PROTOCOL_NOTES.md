# BLE Protocol Notes

BLE 层只承载 Modbus RTU 帧，不做额外效果协议封装。

## Services

- Service: `FFE0`
- Write characteristic: `FFE1`
- Notify characteristic: `FFE2`

## Notes

- 建议协商 MTU `64` 或更大。
- 设备仍按 Modbus 地址过滤请求。
- 写 `DEVICE_ADDR` 时，当前响应仍回到旧地址；下一次请求开始使用新地址。
- 运行配置以寄存器读写为准，设备不会主动推送完整状态快照。
