#pragma once

#include <stdbool.h>
#include <stdint.h>

#define LUMIA_GROUP_COUNT      7u
#define LUMIA_GROUP_LED_COUNT  6u
#define LUMIA_LED_COUNT        (LUMIA_GROUP_COUNT * LUMIA_GROUP_LED_COUNT)

typedef struct {
    uint8_t inner_mode;
    uint16_t hue;
    uint8_t sat;
    uint8_t val;
    uint8_t inner_param;
} LumiaGroupInnerConfig;

typedef struct {
    uint8_t scene_mode;
    uint8_t scene_param;
    uint8_t device_addr;
    uint8_t led_global_bri;
    uint8_t led_gain_r;
    uint8_t led_gain_g;
    uint8_t led_gain_b;
    LumiaGroupInnerConfig groups[LUMIA_GROUP_COUNT];
} PersistentConfig;

typedef struct {
    PersistentConfig cfg;
    uint8_t save_state;
    int16_t temp_c_x100;
    uint16_t vdda_mv;

    bool cfg_dirty;
    uint32_t config_revision;
    uint32_t frame_revision;

    uint32_t rx_request_count;
    uint32_t rx_overflow_count;
    uint32_t tx_drop_count;
    uint32_t parse_error_count;
} RuntimeState;

void runtime_state_init(void);
void runtime_state_restore_config(const PersistentConfig *config);
RuntimeState *runtime_state_get(void);
const PersistentConfig *runtime_state_config(void);

uint8_t runtime_state_get_device_addr(void);
bool runtime_state_set_device_addr(uint8_t device_addr);
void runtime_state_mark_config_changed(void);
void runtime_state_set_save_state(uint8_t save_state);
void runtime_state_mark_config_saved(uint32_t saved_revision);
void runtime_state_set_telemetry(int16_t temp_c_x100, uint16_t vdda_mv);

void runtime_state_note_rx_request(void);
void runtime_state_note_rx_overflow(void);
void runtime_state_note_tx_drop(void);
void runtime_state_note_parse_error(void);
void runtime_state_clear_diag_counters(void);
