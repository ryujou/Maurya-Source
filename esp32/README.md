# ESP32-C3 源码

ESP32 部分由 ESP-IDF 固件、板端网页、主机工具和生产烧录器组成。固件入口和构建命令见 [lumia_esp32/README.md](lumia_esp32/README.md)，硬件/协议文档见 [docs/README.md](docs/README.md)。

| 路径 | 说明 |
| --- | --- |
| lumia_esp32/ | ESP-IDF 6.0.1 工程、组件、主任务和默认配置 |
| lumia_esp32/web_ui/ | Vue 3 + Vite 离线网页源码 |
| lumia_esp32/tests/host/ | 不依赖芯片的 C 协议、灯效、存储和自动信道测试 |
| lumia_esp32/tools/production_flasher/ | Python/Tk 一键烧录器源码 |
| tools/lumia_host/ | USB Serial Modbus 主机工具 |
| docs/ | 接线、寄存器、存储、BLE 和发布说明 |

所有固件路径都以 7 组 × 6 颗 = 42 颗灯为默认基线；无线功率和自动信道的实际实现以 components/lumia_web、components/lumia_platform 源码为准。
