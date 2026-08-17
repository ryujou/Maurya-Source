# 7 路 WS2812 时分复用设计说明

更新时间：2026-06-12

## 目标

在 ESP32-C3 低配版工程里，把 7 路 WS2812 从“硬编码点灯逻辑”抽象成一个可配置、可复用的时分复用扫描层。

核心要求：

- 支持 7 路独立输出。
- 每一路的灯珠数量可以单独配置。
- 上层只负责往 buffer 写灯效数据，不直接关心扫描细节。
- 扫描层负责把 buffer 中的数据按路路由到对应 GPIO。
- 时分复用逻辑要从灯效逻辑里剥离出来，避免 effect 层和硬件层耦合。

## 设计思路

### 分层

建议拆成三层：

1. **效果层**
   - 只产生“这一帧每一颗灯应该是什么颜色”的数据。
   - 不关心 GPIO，不关心 RMT，不关心扫描顺序。

2. **LED Frame Buffer 层**
   - 保存 7 路 LED 的目标帧数据。
   - 支持每一路不同的灯珠数量。
   - 上层只写 buffer，不直接触碰驱动接口。

3. **TDM 扫描驱动层**
   - 负责按顺序选择一路 GPIO。
   - 把该路对应的 buffer 数据发给 WS2812。
   - 发完后等待 reset 时间，再切到下一路。

这样做的好处是：

- 以后改灯效，只改 buffer 的内容。
- 以后改引脚或扫描节拍，只改扫描层。
- 以后增加或减少某一路的灯珠数量，不会影响整个效果系统。

## 数据模型

### 路由定义

7 路 LED 可以抽象成如下结构：

```c
typedef struct {
    uint8_t gpio_num;
    uint16_t led_count;
} LumiaLedChannelConfig;
```

每一路至少需要知道：

- 使用哪个 GPIO
- 这一条链上有多少颗灯

### 总 buffer

可以用一个总 buffer 保存 7 路数据，也可以每路单独分 buffer。

推荐方案是**每路独立 buffer，但统一管理**，例如：

```c
typedef struct {
    uint8_t rgb[LED_COUNT_MAX][3];
} LumiaLedChannelFrame;

typedef struct {
    LumiaLedChannelConfig channels[7];
    LumiaLedChannelFrame frame[7];
} LumiaLedTdmState;
```

这里的 `LED_COUNT_MAX` 可以按每路最大灯珠数定义，也可以直接用每路真实数量做动态管理。

## Buffer 写入方式

上层只做两类操作：

1. **整路写入**
   - 一次性写某一路的所有灯。
   - 适合整条链播放同一个效果。

2. **单灯写入**
   - 只修改某一路里的某一个 LED。
   - 适合局部动画、亮灭控制、位移效果。

建议保留这两个接口：

```c
void led_tdm_set_pixel(uint8_t channel, uint16_t index, uint8_t r, uint8_t g, uint8_t b);
void led_tdm_set_channel_frame(uint8_t channel, const uint8_t (*rgb)[3], uint16_t count);
```

这样效果层只需要：

- 生成目标颜色
- 写入 buffer
- 调用“提交/刷新”接口

不需要知道当前到底是扫描到第几路。

## 扫描模型

### 基本流程

扫描驱动层按下面流程工作：

1. 选中第 `N` 路 GPIO。
2. 读取第 `N` 路 buffer。
3. 将该路帧发给 WS2812。
4. 等待 reset/latch 时间。
5. 切换到第 `N+1` 路。
6. 直到 7 路全部发送完毕。
7. 从第 1 路重新开始。

### 扫描原则

- 任一时刻只驱动一路。
- 不追求 7 路同时输出。
- 通过快速轮询让视觉上看起来像持续刷新。

### 帧率含义

这里有两个“帧率”概念：

- **单路刷新率**：某一路被重新刷新的频率。
- **整轮扫描率**：7 路全部刷完一遍的频率。

低配版更关心整轮扫描率，因为它决定“7 路灯效同步感”。

## 可配置灯珠数量

每一路的灯珠数量不应写死。

建议在配置里保留：

```c
typedef struct {
    uint8_t gpio_num;
    uint16_t led_count;
} LumiaLedChannelConfig;
```

这样可以支持：

- 7 路每路 5 颗
- 7 路每路不同颗数
- 某一路未来扩展到更多颗

### 写入时的边界规则

扫描层在写入时要检查：

- channel 是否有效
- index 是否小于该路 led_count
- 输入颜色数据是否为空

## 推荐接口

### 初始化

```c
esp_err_t led_tdm_init(const LumiaLedChannelConfig *channels, size_t channel_count);
```

初始化只做：

- 记录 7 路 GPIO
- 记录每路灯珠数
- 准备扫描资源

### 写像素

```c
esp_err_t led_tdm_set_pixel(uint8_t channel,
                            uint16_t index,
                            uint8_t r,
                            uint8_t g,
                            uint8_t b);
```

### 写整路帧

```c
esp_err_t led_tdm_set_channel_frame(uint8_t channel,
                                    const uint8_t (*rgb)[3],
                                    uint16_t count);
```

### 刷新/提交

```c
esp_err_t led_tdm_flush(void);
```

这个接口只表示：

- buffer 已经更新完成
- 扫描层可以开始按当前状态输出

如果扫描层本身是周期性执行的，`flush` 也可以只作为“状态提交标记”。

## 灯效抽象建议

### 上层怎么用

效果层不直接调用 GPIO 驱动，而是对 buffer 做写入：

```text
effect engine
  -> render one frame
  -> write 7 channel buffers
  -> flush
  -> TDM scan driver emits data
```

### 这样做的收益

- 灯效逻辑可以完全独立测试。
- 后续改成别的输出方案，不需要重写灯效。
- 同一套效果可以跑在高配版和低配版上。

## 与现有工程的关系

当前工程已经有：

- 统一的 runtime state
- effect engine
- led strip 驱动封装

下一步建议把现有单路 `led_strip_driver` 逐步替换成：

- `led_tdm_*` 作为抽象层
- 底层再由单通道扫描实现

这样低配版和高配版都能共用同一套效果层，只是底层驱动不同。

## 实现优先级

建议按这个顺序做：

1. 先定义 7 路 channel 配置。
2. 再定义每路 buffer。
3. 再做单路扫描输出。
4. 最后把 effect 层接到 buffer 写入接口。

不要一开始就把扫描、效果、协议、存储全揉在一起。

## 结论

这套设计的核心是：

- **灯效写 buffer**
- **扫描层负责发数据**
- **每路灯珠数量可配置**
- **7 路扫描逻辑完全抽象出来**

这样后续无论是调整灯珠数量、换 GPIO，还是改灯效，都只需要动对应层，不需要牵一发动全身。
