#pragma once

#include <stdint.h>

#include "esp_err.h"
#include "register_map.h"
#include "runtime_state.h"

typedef enum {
    LUMIA_WEB_CONTROL_READ_STATE = 0,
    LUMIA_WEB_CONTROL_WRITE_SCENE,
    LUMIA_WEB_CONTROL_WRITE_GLOBAL,
    LUMIA_WEB_CONTROL_WRITE_GROUP,
    LUMIA_WEB_CONTROL_WRITE_ALL_GROUPS,
    LUMIA_WEB_CONTROL_CLEAR_DIAGNOSTICS,
} LumiaWebControlType;

typedef struct {
    uint8_t scene_mode;
    uint8_t scene_param;
    uint8_t global_brightness;
    uint8_t gain_r;
    uint8_t gain_g;
    uint8_t gain_b;
} LumiaWebGlobalValues;

typedef struct {
    uint32_t id;
    LumiaWebControlType type;
    uint8_t group_index;
    LumiaWebGlobalValues global;
    LumiaGroupInnerConfig groups[LUMIA_GROUP_COUNT];
} LumiaWebControlRequest;

typedef struct {
    uint32_t id;
    RegisterMapStatus status;
    uint32_t flash_size_bytes;
    uint32_t app_partition_size_bytes;
    uint32_t led_tx_error_count;
    uint32_t led_gpio_switch_error_count;
    uint32_t led_init_error_count;
    uint32_t led_max_scan_gap_us;
    RuntimeState state;
} LumiaWebControlResponse;

typedef esp_err_t (*lumia_web_control_exchange_fn)(
    const LumiaWebControlRequest *request,
    LumiaWebControlResponse *response,
    uint32_t timeout_ms,
    void *user_ctx);
