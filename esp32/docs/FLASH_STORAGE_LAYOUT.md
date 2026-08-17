# Flash Storage Layout

配置存储使用双槽位轮换写入。

## Record Format

- `slot size = 4096`
- `record size = 128`
- `header size = 32`
- `payload size = 80`
- `commit size = 16`
- `record version = 2`

## Persisted Fields

以下字段会持久化：

- `scene_mode`
- `scene_param`
- `device_addr`
- `led_global_bri`
- `led_gain_r/g/b`
- `groups[0..6].inner_mode`
- `groups[0..6].hue`
- `groups[0..6].sat`
- `groups[0..6].val`
- `groups[0..6].inner_param`

以下字段不会持久化：

- 诊断计数
- 温度
- 电压
- BLE 连接状态
- 保存状态机运行态

旧版本存储记录不会迁移。读取到旧版本时，固件按“无有效配置”处理，并使用当前默认值重新保存。
