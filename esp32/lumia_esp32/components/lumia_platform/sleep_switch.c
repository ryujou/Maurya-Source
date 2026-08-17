#include "sleep_switch.h"

#include <stdbool.h>
#include <stddef.h>

#include "driver/gpio.h"
#include "esp_sleep.h"
#include "sdkconfig.h"

typedef struct {
    bool initialized;
    bool debounced_sleep_request;
    bool sampled_sleep_request;
    uint32_t last_change_ms;
} LumiaSleepSwitchState;

static LumiaSleepSwitchState s_sleep_switch;

static bool time_reached(uint32_t now_ms, uint32_t deadline_ms)
{
    return (int32_t)(now_ms - deadline_ms) >= 0;
}

static bool level_is_sleep_request(int level)
{
    bool high = level != 0;

    return CONFIG_LUMIA_SLEEP_SWITCH_ACTIVE_LOW ? !high : high;
}

esp_err_t lumia_sleep_switch_init(uint32_t now_ms, bool *sleep_requested)
{
    gpio_config_t input_config;
    int level;

    if (sleep_requested != NULL) {
        *sleep_requested = false;
    }
    if (s_sleep_switch.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    if (!GPIO_IS_VALID_GPIO(CONFIG_LUMIA_SLEEP_SWITCH_GPIO)) {
        return ESP_ERR_INVALID_ARG;
    }

    input_config.pin_bit_mask = 1ULL << CONFIG_LUMIA_SLEEP_SWITCH_GPIO;
    input_config.mode = GPIO_MODE_INPUT;
    input_config.pull_up_en = GPIO_PULLUP_DISABLE;
    input_config.pull_down_en = GPIO_PULLDOWN_DISABLE;
    input_config.intr_type = GPIO_INTR_DISABLE;

    esp_err_t err = gpio_config(&input_config);
    if (err != ESP_OK) {
        return err;
    }

    level = gpio_get_level(CONFIG_LUMIA_SLEEP_SWITCH_GPIO);
    if (level < 0) {
        return ESP_FAIL;
    }

    s_sleep_switch.sampled_sleep_request = level_is_sleep_request(level);
    s_sleep_switch.debounced_sleep_request = s_sleep_switch.sampled_sleep_request;
    s_sleep_switch.last_change_ms = now_ms;
    s_sleep_switch.initialized = true;
    if (sleep_requested != NULL) {
        *sleep_requested = s_sleep_switch.debounced_sleep_request;
    }
    return ESP_OK;
}

esp_err_t lumia_sleep_switch_service(uint32_t now_ms, bool *sleep_requested)
{
    bool sampled_sleep_request;
    int level;

    if (sleep_requested != NULL) {
        *sleep_requested = false;
    }
    if (!s_sleep_switch.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    level = gpio_get_level(CONFIG_LUMIA_SLEEP_SWITCH_GPIO);
    if (level < 0) {
        return ESP_FAIL;
    }
    sampled_sleep_request = level_is_sleep_request(level);

    if (sampled_sleep_request != s_sleep_switch.sampled_sleep_request) {
        s_sleep_switch.sampled_sleep_request = sampled_sleep_request;
        s_sleep_switch.last_change_ms = now_ms;
        return ESP_OK;
    }

    if (sampled_sleep_request == s_sleep_switch.debounced_sleep_request) {
        return ESP_OK;
    }
    if (!time_reached(now_ms,
                      s_sleep_switch.last_change_ms +
                          CONFIG_LUMIA_SLEEP_SWITCH_DEBOUNCE_MS)) {
        return ESP_OK;
    }

    s_sleep_switch.debounced_sleep_request = sampled_sleep_request;
    if (sleep_requested != NULL && sampled_sleep_request) {
        *sleep_requested = true;
    }
    return ESP_OK;
}

esp_err_t lumia_sleep_switch_prepare_high_wakeup(void)
{
    if (!esp_sleep_is_valid_wakeup_gpio(CONFIG_LUMIA_SLEEP_SWITCH_GPIO)) {
        return ESP_ERR_NOT_SUPPORTED;
    }

    esp_err_t err = esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_ALL);
    if (err != ESP_OK) {
        return err;
    }
    return esp_sleep_enable_gpio_wakeup_on_hp_periph_powerdown(
        1ULL << CONFIG_LUMIA_SLEEP_SWITCH_GPIO,
        ESP_GPIO_WAKEUP_GPIO_HIGH);
}
