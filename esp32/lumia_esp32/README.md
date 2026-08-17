# ESP32-C3 固件

这是基于 ESP-IDF 6.0.1 的 ESP32-C3 工程，入口为 main/app_main.c。固件采用事件队列模型：BLE、USB Serial Modbus、Wi-Fi HTTP 和 OTA 回调只提交完整请求或诊断事件，app_task 统一拥有运行时状态、灯效调度、配置保存、传感器服务和 LED 刷新。

## 组件

- lumia_protocol：Modbus CRC、请求/响应、厂商 0x41 帧和 OTA/灯效数据。
- lumia_runtime：寄存器映射、7 组运行时状态、遥测和诊断。
- lumia_effects、lumia_effect_session：全局场景、组内模式、volatile 灯效会话和 42 颗 RGB 输出。
- lumia_platform：NimBLE、USB Serial、GPIO、状态灯、WS2812 驱动和设备存储适配。
- lumia_web：SoftAP、自动信道、网页静态资源、Captive DNS 和 HTTP OTA。
- lumia_ota、lumia_storage、lumia_monitor：OTA 会话、Flash 双槽配置、温度/电压采样。

## 固定硬件和无线配置

- 7 路 LED 输出，每路默认 6 颗，合计 42 颗；GPIO 和数量可在 sdkconfig.defaults/菜单配置中查看。
- BLE 名称由 CONFIG_LUMIA_BLE_DEVICE_NAME 配置；服务/特征为 FFE0/FFE1/FFE2。
- CONFIG_LUMIA_WIFI_AP_AUTO_CHANNEL=y 时，启动扫描 1、6、11 并选择评分最低者，扫描失败使用 CONFIG_LUMIA_WIFI_AP_CHANNEL。
- Wi-Fi 最大功率使用 34 个四分之一 dBm 单位（8.5 dBm），BLE 使用 ESP_PWR_LVL_P6（6 dBm）；广播开始和连接建立后都会读取校验。

## 构建和本机测试

~~~
idf.py set-target esp32c3
idf.py build
idf.py -p COMx flash monitor
~~~

主机侧 C 测试和网页资源测试位于 tests/host/ 与 tools/，用法见 [tests/host/README.md](tests/host/README.md)。板端网页源码见 [web_ui/README.md](web_ui/README.md)，USB 生产烧录器见 [tools/production_flasher/README.md](tools/production_flasher/README.md)。
