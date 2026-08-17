# Android Host Integration Protocol

本文档用于安卓上位机接入当前 `lumia_esp32_low` 固件。

目标：

- 汇总本轮需求决策
- 给出当前固件唯一有效的通信协议
- 给出安卓上位机需要实现的寄存器读写模型

## 1. 当前需求结论

当前固件已经完全切到双层效果架构，不兼容旧版本语义。

已确认的产品规则：

- 只做低配版工程
- 不兼容任何旧寄存器语义
- 不迁移旧 Flash 配置
- 所有效果配置都持久化到 Flash
- `scene` 是全局唯一一套，不支持每组独立 scene
- `GPIO9` 只切换 `scene_mode`
- `GPIO4` 低电平请求深度睡眠，高电平唤醒

## 2. 效果模型

### 2.1 组内层

组内层只负责单根灯棒自身的整组颜色/亮度变化，不做位置运动。

`inner_mode` 定义：

- `1 = Steady`
- `2 = Breath`
- `3 = Strobe`
- `4 = Fade`

每组配置项：

- `inner_mode`
- `hue`
- `sat`
- `val`
- `inner_param`

### 2.2 组间层

组间层只负责 7 组之间的运动感。

`scene_mode` 定义：

- `1 = Static`
- `2 = Chase L->R`
- `3 = Chase R->L`
- `4 = PingPong`

全局配置项：

- `scene_mode`
- `scene_param`

### 2.3 默认配置

默认上电配置：

- `scene_mode = 1`
- `scene_param = 80`
- `device_addr = 1`
- `led_global_bri = 255`
- `led_gain_r = 255`
- `led_gain_g = 176`
- `led_gain_b = 240`
- 7 组全部：
  - `inner_mode = 1`
  - `hue = 30`
  - `sat = 255`
  - `val = 255`
  - `inner_param = 255`

## 3. 传输层

当前固件支持两种传输入口：

- BLE
- USB Serial

两者承载的上层协议相同，都是 Modbus RTU 帧。

### 3.1 BLE

BLE 只传 Modbus RTU，不做额外封装。

- Service UUID: `FFE0`
- Write Characteristic: `FFE1`
- Notify Characteristic: `FFE2`

注意：

- 建议 MTU 至少 `64`
- 安卓端写入请求帧到 `FFE1`
- 设备响应通过 `FFE2 notify`
- 设备不会主动推送完整状态快照，安卓端必须主动轮询

### 3.2 USB Serial

USB 串口参数：

- 波特率：`115200`

安卓如果走 USB CDC/Serial，也直接发 Modbus RTU 原始帧。

## 4. Modbus RTU 规则

### 4.1 支持的功能码

- `0x03` Read Holding Registers
- `0x06` Write Single Register
- `0x10` Write Multiple Registers

### 4.2 地址过滤

设备只响应当前 `device_addr` 对应的请求。

如果请求帧的设备地址不匹配：

- 设备直接不响应

### 4.3 CRC

使用标准 Modbus CRC16，低字节在前，高字节在后。

CRC 初值：

- `0xFFFF`

多项式：

- `0xA001`

### 4.4 异常响应

异常帧格式：

- `func | 0x80`
- 异常码
- CRC16

当前异常码映射：

- `0x02 = Illegal address`
- `0x03 = Illegal value`

### 4.5 长度限制

固件对单次读/写多个寄存器的数量限制为：

- 最多 `64` 个寄存器

## 5. 当前寄存器表

以下是当前唯一有效的寄存器语义。

### 5.1 全局/系统寄存器

| Address | Name | Access | Range / Meaning |
|---|---|---|---|
| `0x0000` | `SCENE_MODE` | RW | `1..4` |
| `0x0001` | `SCENE_PARAM` | RW | `0..255` |
| `0x0002` | `LED_GLOBAL_BRI` | RW | `0..255` |
| `0x0003` | `LED_GAIN_R` | RW | `0..255` |
| `0x0004` | `LED_GAIN_G` | RW | `0..255` |
| `0x0005` | `LED_GAIN_B` | RW | `0..255` |
| `0x000A` | `CFG_SAVE_STATE` | RO | `0=saved 1=dirty 2=saving 3=failed` |
| `0x000B` | `DEVICE_ADDR` | RW | `1..247` |
| `0x000C` | `UART_RX_COUNT` | RO | 收到请求计数 |
| `0x000D` | `UART_RX_OVERFLOW` | RO | 溢出计数 |
| `0x000E` | `UART_TX_DROP` | RO | 发送失败计数 |
| `0x000F` | `UART_PARSE_ERROR` | RO / W1C | 写 `0xA55A` 清零诊断 |
| `0x0010` | `TEMP_C_X100` | RO | `int16`，单位 `0.01 C` |
| `0x0011` | `VDDA_MV` | RO | 电压，单位 mV |

保留地址：

- `0x0006..0x0009`

这些地址当前不要在安卓端当作业务寄存器使用。

### 5.2 每组组内寄存器

组配置从 `0x0020` 开始。

常量：

- `GROUP_BASE = 0x0020`
- `GROUP_STRIDE = 0x0005`
- `GROUP_COUNT = 7`

每组 5 个寄存器：

| Offset | Name | Access | Range / Meaning |
|---|---|---|---|
| `+0` | `INNER_MODE` | RW | `1..4` |
| `+1` | `HUE` | RW | `0..359` |
| `+2` | `SAT` | RW | `0..255` |
| `+3` | `VAL` | RW | `0..255` |
| `+4` | `INNER_PARAM` | RW | `0..255` |

组地址计算方式：

`group_base = 0x0020 + group_index * 0x0005`

其中：

- `group_index = 0..6`

例如：

- 第 1 组基址：`0x0020`
- 第 2 组基址：`0x0025`
- 第 7 组基址：`0x003E`

## 6. 安卓端建议读写方式

### 6.1 刷新整机状态

建议分两次读取：

1. 读全局/系统区
   - 起始：`0x0000`
   - 数量：`22`

2. 读组配置区
   - 起始：`0x0020`
   - 数量：`7 * 5 = 35`

说明：

- 全局读 `22` 个寄存器时，`0x0006..0x0009`、`0x0012..0x0015` 当前无业务语义，可忽略
- 组配置区一次性读完最简单

### 6.2 写全局 scene

方式一：单寄存器写

- 写 `0x0000 = scene_mode`
- 写 `0x0001 = scene_param`

方式二：多寄存器写

- 起始 `0x0000`
- 数量 `2`

### 6.3 写全局 LED 校正

建议一次写 4 个寄存器：

- 起始 `0x0002`
- 数量 `4`

顺序：

- `LED_GLOBAL_BRI`
- `LED_GAIN_R`
- `LED_GAIN_G`
- `LED_GAIN_B`

### 6.4 写单组组内配置

建议对单组直接用 `0x10` 一次写 5 个寄存器。

顺序：

- `INNER_MODE`
- `HUE`
- `SAT`
- `VAL`
- `INNER_PARAM`

### 6.5 写所有组相同配置

安卓端循环写 7 次即可。

当前固件没有“广播写所有组相同配置”的专用寄存器。

## 7. 保存与状态行为

配置写入后：

- 固件会自动标记 dirty
- 延时保存到 Flash

安卓端不需要单独发送“保存配置”命令。

`CFG_SAVE_STATE` 含义：

- `0`：已保存
- `1`：配置变更，待保存
- `2`：正在保存
- `3`：保存失败

建议安卓端：

- 每次写配置后可轮询 `CFG_SAVE_STATE`
- 看到 `0` 视为持久化完成

## 8. 设备地址修改规则

修改寄存器：

- `0x000B = DEVICE_ADDR`

规则：

- 当前写响应仍使用旧地址返回
- 下一次请求开始，设备只接受新地址

安卓端建议流程：

1. 用旧地址发写请求
2. 正常接收旧地址响应
3. 立即把本地会话地址切换为新地址
4. 后续读写都用新地址

## 9. 诊断与遥测

### 9.1 诊断计数

- `0x000C = UART_RX_COUNT`
- `0x000D = UART_RX_OVERFLOW`
- `0x000E = UART_TX_DROP`
- `0x000F = UART_PARSE_ERROR`

清零方式：

- 向 `0x000F` 写入 `0xA55A`

### 9.2 温度与电压

- `0x0010 = TEMP_C_X100`
- `0x0011 = VDDA_MV`

温度需要按有符号 16 位解析。

示例：

- `2500` 表示 `25.00 C`
- `-500` 表示 `-5.00 C`

## 10. GPIO 与业务关联

安卓上位机只需要知道这些行为，不需要直接控制 GPIO：

- `GPIO8`：板载 BLE 状态灯，低电平点亮
- `GPIO9`：本地按键，只切换 `scene_mode`
- `GPIO4`：高电平运行，低电平请求深度睡眠，高电平唤醒

## 11. 安卓上位机推荐数据模型

建议安卓端直接建以下数据结构：

### 11.1 GlobalState

- `sceneMode: Int`
- `sceneParam: Int`
- `globalBrightness: Int`
- `gainR: Int`
- `gainG: Int`
- `gainB: Int`
- `deviceAddr: Int`
- `saveState: Int`

### 11.2 GroupState

- `innerMode: Int`
- `hue: Int`
- `sat: Int`
- `val: Int`
- `innerParam: Int`

### 11.3 RuntimeSnapshot

- `global: GlobalState`
- `groups: List<GroupState>`，固定 7 组
- `rxCount: Int`
- `rxOverflow: Int`
- `txDrop: Int`
- `parseError: Int`
- `tempCx100: Int`
- `vddaMv: Int`

## 12. 典型命令示例

以下示例都是 Modbus RTU 逻辑内容，CRC 需安卓端自行补。

### 12.1 读取全局区

- addr: `0x01`
- func: `0x03`
- start: `0x0000`
- count: `0x0016`

### 12.2 读取全部组配置

- addr: `0x01`
- func: `0x03`
- start: `0x0020`
- count: `0x0023`

### 12.3 设置 scene = PingPong, speed = 100

- 写 `0x0000 = 4`
- 写 `0x0001 = 100`

或者一次多写：

- start: `0x0000`
- values: `[4, 100]`

### 12.4 设置第 3 组为蓝色呼吸

第 3 组 `group_index = 2`

基址：

- `0x0020 + 2 * 0x0005 = 0x002A`

写入 5 个值：

- `INNER_MODE = 2`
- `HUE = 240`
- `SAT = 255`
- `VAL = 255`
- `INNER_PARAM = 120`

## 13. 安卓端实现注意点

- 不要假设设备会主动同步状态
- 连接成功后先读一次全局区和组区
- BLE notify 收到的是完整 Modbus RTU 响应帧，不要再按自定义协议拆包
- 每次写配置后，UI 侧最好立即更新本地状态，并异步轮询确认
- `TEMP_C_X100` 必须按 `int16` 解释
- 修改地址后必须切换本地请求地址
- 当前只支持 7 组，每组固定 5 个寄存器

## 14. 参考源码

如果安卓端需要对照实现，可直接参考这些文件：

- `lumia_esp32/components/lumia_runtime/include/register_map.h`
- `lumia_esp32/components/lumia_runtime/include/runtime_state.h`
- `lumia_esp32/components/lumia_protocol/modbus_server.c`
- `tools/lumia_host/lumia_host/protocol.py`
