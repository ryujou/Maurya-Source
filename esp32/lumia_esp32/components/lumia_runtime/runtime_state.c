#include "runtime_state.h"

#include <string.h>

static RuntimeState s_runtime_state;

void runtime_state_init(void)
{
    uint8_t group;

    memset(&s_runtime_state, 0, sizeof(s_runtime_state));

    s_runtime_state.cfg.scene_mode = 1u;
    s_runtime_state.cfg.scene_param = 80u;
    s_runtime_state.cfg.device_addr = 0x01u;
    s_runtime_state.cfg.led_global_bri = 255u;
    s_runtime_state.cfg.led_gain_r = 255u;
    s_runtime_state.cfg.led_gain_g = 176u;
    s_runtime_state.cfg.led_gain_b = 240u;
    for (group = 0u; group < LUMIA_GROUP_COUNT; ++group) {
        s_runtime_state.cfg.groups[group].inner_mode = 1u;
        s_runtime_state.cfg.groups[group].hue = 30u;
        s_runtime_state.cfg.groups[group].sat = 255u;
        s_runtime_state.cfg.groups[group].val = 255u;
        s_runtime_state.cfg.groups[group].inner_param = 255u;
    }

    s_runtime_state.save_state = 0u;
    s_runtime_state.temp_c_x100 = 2500;
    s_runtime_state.vdda_mv = 3300u;
    s_runtime_state.frame_revision = 1u;
}

void runtime_state_restore_config(const PersistentConfig *config)
{
    if (config == NULL) {
        return;
    }

    s_runtime_state.cfg = *config;
    s_runtime_state.cfg_dirty = false;
    s_runtime_state.save_state = 0u;
    s_runtime_state.config_revision = 0u;
    s_runtime_state.frame_revision += 1u;
}

RuntimeState *runtime_state_get(void)
{
    return &s_runtime_state;
}

const PersistentConfig *runtime_state_config(void)
{
    return &s_runtime_state.cfg;
}

uint8_t runtime_state_get_device_addr(void)
{
    return s_runtime_state.cfg.device_addr;
}

bool runtime_state_set_device_addr(uint8_t device_addr)
{
    if (device_addr < 1u || device_addr > 247u) {
        return false;
    }

    if (s_runtime_state.cfg.device_addr != device_addr) {
        s_runtime_state.cfg.device_addr = device_addr;
        runtime_state_mark_config_changed();
    }
    return true;
}

void runtime_state_mark_config_changed(void)
{
    s_runtime_state.cfg_dirty = true;
    s_runtime_state.save_state = 1u;
    s_runtime_state.config_revision += 1u;
    s_runtime_state.frame_revision += 1u;
}

void runtime_state_set_save_state(uint8_t save_state)
{
    s_runtime_state.save_state = save_state;
}

void runtime_state_mark_config_saved(uint32_t saved_revision)
{
    if (s_runtime_state.config_revision == saved_revision) {
        s_runtime_state.cfg_dirty = false;
        s_runtime_state.save_state = 0u;
    } else {
        s_runtime_state.cfg_dirty = true;
        s_runtime_state.save_state = 1u;
    }
}

void runtime_state_set_telemetry(int16_t temp_c_x100, uint16_t vdda_mv)
{
    s_runtime_state.temp_c_x100 = temp_c_x100;
    s_runtime_state.vdda_mv = vdda_mv;
}

void runtime_state_note_rx_request(void)
{
    s_runtime_state.rx_request_count += 1u;
}

void runtime_state_note_rx_overflow(void)
{
    s_runtime_state.rx_overflow_count += 1u;
}

void runtime_state_note_tx_drop(void)
{
    s_runtime_state.tx_drop_count += 1u;
}

void runtime_state_note_parse_error(void)
{
    s_runtime_state.parse_error_count += 1u;
}

void runtime_state_clear_diag_counters(void)
{
    s_runtime_state.rx_request_count = 0u;
    s_runtime_state.rx_overflow_count = 0u;
    s_runtime_state.tx_drop_count = 0u;
    s_runtime_state.parse_error_count = 0u;
}
