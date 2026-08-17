# Register Map

当前固件不再维护旧版本寄存器兼容语义。下面是当前低配版唯一有效的寄存器布局。

## Global / System

| Address | Name | Access | Notes |
|---|---|---|---|
| `0x0000` | `SCENE_MODE` | RW | `1..4` |
| `0x0001` | `SCENE_PARAM` | RW | scene 速度 |
| `0x0002` | `LED_GLOBAL_BRI` | RW | 全局亮度 |
| `0x0003` | `LED_GAIN_R` | RW | 白平衡 R |
| `0x0004` | `LED_GAIN_G` | RW | 白平衡 G |
| `0x0005` | `LED_GAIN_B` | RW | 白平衡 B |
| `0x000A` | `CFG_SAVE_STATE` | RO | `0 saved / 1 dirty / 2 saving / 3 failed` |
| `0x000B` | `DEVICE_ADDR` | RW | Modbus 地址 `1..247` |
| `0x000C` | `UART_RX_COUNT` | RO | 请求计数 |
| `0x000D` | `UART_RX_OVERFLOW` | RO | 溢出计数 |
| `0x000E` | `UART_TX_DROP` | RO | 发送失败计数 |
| `0x000F` | `UART_PARSE_ERROR` | RO / W1C | 写 `0xA55A` 清零诊断 |
| `0x0010` | `TEMP_C_X100` | RO | 芯片温度，`int16`，单位 `0.01 C` |
| `0x0011` | `VDDA_MV` | RO | 电压，单位 mV |

`0x0006..0x0009` 当前保留，不提供业务语义。

## Per Group Inner Config

- `GROUP_BASE = 0x0020`
- `GROUP_STRIDE = 0x0005`
- `GROUP_COUNT = 7`

每组寄存器布局：

| Offset | Name | Access | Notes |
|---|---|---|---|
| `+0` | `INNER_MODE` | RW | `1=Steady 2=Breath 3=Strobe 4=Fade` |
| `+1` | `HUE` | RW | `0..359` |
| `+2` | `SAT` | RW | `0..255` |
| `+3` | `VAL` | RW | `0..255` |
| `+4` | `INNER_PARAM` | RW | 当前组内模式参数 |
