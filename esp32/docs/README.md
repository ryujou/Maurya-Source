# ESP32-C3 文档索引

本目录记录 esp32/lumia_esp32/ 固件的接线、协议、存储和发布说明。固件项目根目录不在本目录，而是在上一级的 lumia_esp32/。

## 固件当前包含的能力

- NimBLE GATT：FFE0 服务、FFE1 写入特征和 FFE2 通知特征。
- Modbus 功能码 0x03、0x06、0x10，寄存器映射由 components/lumia_runtime 和 components/lumia_protocol 实现。
- 全局场景（静态、左右追逐、往返）和每组的常亮、呼吸、频闪、渐变模式。
- 7 路 WS2812 输出，每路默认 6 颗，逻辑总数为 42 颗。
- Flash 双槽配置保存、温度/电压与传输诊断、GPIO9 模式按键和 GPIO4 休眠开关。
- Wi-Fi SoftAP 网页控制和 OTA；启用自动信道时，启动扫描只在 1、6、11 中选择，失败回退到配置的信道。
- Wi-Fi 最大 TX 功率 8.5 dBm，BLE 广播/连接功率 6 dBm；设置和读取不一致时服务不会继续提供无线能力。

## 构建

~~~
cd esp32/lumia_esp32
idf.py set-target esp32c3
idf.py build
idf.py -p COMx flash monitor
~~~

sdkconfig.defaults 中包含灯珠 GPIO/数量、SoftAP、BLE、OTA 布局和功率相关默认值。公开源码中的 SoftAP 密码是占位值，实际烧录前请在本地配置中替换。

## 相关文档

- [HARDWARE_AND_BUILD.md](HARDWARE_AND_BUILD.md)：接线、工具链和构建注意事项
- [BLE_PROTOCOL_NOTES.md](BLE_PROTOCOL_NOTES.md)：BLE 与 Modbus 帧说明
- [REGISTER_COMPATIBILITY_MATRIX.md](REGISTER_COMPATIBILITY_MATRIX.md)：寄存器兼容关系
- [LED_MATRIX_ROUTING.md](LED_MATRIX_ROUTING.md)：7 路灯带的逻辑顺序
- [FLASH_STORAGE_LAYOUT.md](FLASH_STORAGE_LAYOUT.md)：双槽与配置存储
- [FIRMWARE_RELEASE_PROCESS.md](FIRMWARE_RELEASE_PROCESS.md)：发布和校验步骤
