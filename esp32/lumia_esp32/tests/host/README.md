# 固件主机测试

tests/host/ 中的 C 测试不需要 ESP32 芯片，直接编译固件组件的纯 C 部分。下面的命令从 esp32/lumia_esp32/ 目录执行，要求本机有 gcc。

## 协议和运行时

~~~
gcc -std=c99 -Wall -Wextra -Werror \
  -Itests/host/include \
  -Icomponents/lumia_protocol/include \
  -Icomponents/lumia_runtime/include \
  -Icomponents/lumia_platform/include \
  tests/host/test_protocol_runtime.c \
  components/lumia_protocol/modbus_crc.c \
  components/lumia_protocol/modbus_frame.c \
  components/lumia_protocol/modbus_server.c \
  components/lumia_runtime/register_map.c \
  components/lumia_runtime/runtime_state.c \
  -o /tmp/lumia_protocol_runtime_test
/tmp/lumia_protocol_runtime_test
~~~

## 其他纯 C 测试

- test_effect_session.c + components/lumia_effect_session/effect_session.c：volatile 灯效会话的序列号、开始/结束和边界。
- test_config_store.c + components/lumia_storage/config_store.c：双槽配置读写、校验和损坏恢复。
- components/lumia_effects/test/test_effect_engine.c：静态、左右追逐、往返、常亮、呼吸、频闪和渐变算法。
- test_led_strip_routing.c：7 路灯带和组优先顺序。
- test_mode_button_logic.c：GPIO9 短按/长按消抖。
- test_sleep_switch.c：GPIO4 启动和休眠判定。

每个测试都使用同样的编译选项：

~~~
gcc -std=c99 -Wall -Wextra -Werror [头文件目录] [测试文件] [被测源文件] -o /tmp/maurya_test
/tmp/maurya_test
~~~

## Python 资源测试

从项目根目录运行：

~~~
python tools/test_web_assets.py
python tools/test_flash_layout.py
~~~

## 自动信道测试

wifi_channel_selector.c 只在 1、6、11 三个候选信道中评分；测试会覆盖空扫描、非法信道、RSSI 截断、重叠权重和备用信道平局：

~~~
gcc -std=c99 -Wall -Wextra -Werror \
  -Icomponents/lumia_web \
  tests/host/test_wifi_channel_selector.c \
  components/lumia_web/wifi_channel_selector.c \
  -o /tmp/lumia_wifi_channel_selector_test
/tmp/lumia_wifi_channel_selector_test
~~~
