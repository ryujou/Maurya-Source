# Host Tests

Run from WSL:

```bash
cd /mnt/f/lumia/Lumia_main/lumia_esp32_low/lumia_esp32
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
```

Additional tests:

```bash
gcc -std=c99 -Wall -Wextra -Werror \
  -Icomponents/lumia_effects/include \
  -Icomponents/lumia_effect_session/include \
  tests/host/test_effect_session.c \
  components/lumia_effect_session/effect_session.c \
  -o /tmp/lumia_effect_session_test
/tmp/lumia_effect_session_test
```

```bash
gcc -std=c99 -Wall -Wextra -Werror \
  -Itests/host/include \
  -Icomponents/lumia_storage/include \
  -Icomponents/lumia_runtime/include \
  tests/host/test_config_store.c \
  components/lumia_storage/config_store.c \
  -o /tmp/lumia_config_store_test
/tmp/lumia_config_store_test
```

Effect engine test:

```bash
cd /mnt/f/lumia/Lumia_main/lumia_esp32_low/lumia_esp32/components/lumia_effects/test
gcc -std=c99 -Wall -Wextra -Werror \
  -I../include -I.. \
  test_effect_engine.c \
  ../effect_engine.c \
  ../effect_inner.c \
  ../effect_inner_mode_steady.c \
  ../effect_inner_mode_breath.c \
  ../effect_inner_mode_strobe.c \
  ../effect_inner_mode_fade.c \
  ../effect_scene.c \
  ../effect_scene_mode_static.c \
  ../effect_scene_mode_chase_lr.c \
  ../effect_scene_mode_chase_rl.c \
  ../effect_scene_mode_pingpong.c \
  -o /tmp/lumia_effects_test
/tmp/lumia_effects_test
```

LED strip routing test:

```bash
cd /mnt/f/lumia/Lumia_main/lumia_esp32_low/lumia_esp32
gcc -std=c99 -Wall -Wextra -Werror \
  -Itests/host/include \
  -Icomponents/lumia_platform/include \
  -Icomponents/lumia_effects/include \
  tests/host/test_led_strip_routing.c \
  components/lumia_platform/led_strip_driver.c \
  -o /tmp/lumia_led_strip_routing_test
/tmp/lumia_led_strip_routing_test
```

Mode button logic test:

```bash
gcc -std=c99 -Wall -Wextra -Werror \
  -Icomponents/lumia_platform/include \
  tests/host/test_mode_button_logic.c \
  components/lumia_platform/mode_button_logic.c \
  -o /tmp/lumia_mode_button_logic_test
/tmp/lumia_mode_button_logic_test
```

Sleep switch startup-state test:

```bash
gcc -std=c99 -Wall -Wextra -Werror \
  -Itests/host/include \
  -Icomponents/lumia_platform/include \
  tests/host/test_sleep_switch.c \
  components/lumia_platform/sleep_switch.c \
  -o /tmp/lumia_sleep_switch_test
/tmp/lumia_sleep_switch_test
```

Web resource and compact palette test:

```bash
python3 tools/test_web_assets.py
python3 tools/test_flash_layout.py
```

Wi-Fi automatic channel selector test:

```bash
gcc -std=c99 -Wall -Wextra -Werror \
  -Icomponents/lumia_web \
  tests/host/test_wifi_channel_selector.c \
  components/lumia_web/wifi_channel_selector.c \
  -o /tmp/lumia_wifi_channel_selector_test
/tmp/lumia_wifi_channel_selector_test
```
