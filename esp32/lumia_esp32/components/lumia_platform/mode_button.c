#include "mode_button.h"

#include <stdbool.h>

#include "driver/gpio.h"
#include "sdkconfig.h"

typedef struct {
    bool initialized;
    LumiaModeButtonLogic logic;
} LumiaModeButtonState;

static LumiaModeButtonState s_mode_button;

static bool button_level_is_pressed(int level)
{
    bool high = level != 0;

    return CONFIG_LUMIA_MODE_BUTTON_ACTIVE_LOW ? !high : high;
}

esp_err_t lumia_mode_button_init(uint32_t now_ms)
{
    gpio_config_t input_config;
    int level;

    if (s_mode_button.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    if (!GPIO_IS_VALID_GPIO(CONFIG_LUMIA_MODE_BUTTON_GPIO)) {
        return ESP_ERR_INVALID_ARG;
    }

    input_config.pin_bit_mask = 1ULL << CONFIG_LUMIA_MODE_BUTTON_GPIO;
    input_config.mode = GPIO_MODE_INPUT;
    input_config.pull_up_en = CONFIG_LUMIA_MODE_BUTTON_ACTIVE_LOW
                                  ? GPIO_PULLUP_ENABLE
                                  : GPIO_PULLUP_DISABLE;
    input_config.pull_down_en = CONFIG_LUMIA_MODE_BUTTON_ACTIVE_LOW
                                    ? GPIO_PULLDOWN_DISABLE
                                    : GPIO_PULLDOWN_ENABLE;
    input_config.intr_type = GPIO_INTR_DISABLE;

    esp_err_t err = gpio_config(&input_config);
    if (err != ESP_OK) {
        return err;
    }

    level = gpio_get_level(CONFIG_LUMIA_MODE_BUTTON_GPIO);
    if (level < 0) {
        return ESP_FAIL;
    }

    lumia_mode_button_logic_init(&s_mode_button.logic,
                                 button_level_is_pressed(level),
                                 now_ms);
    s_mode_button.initialized = true;
    return ESP_OK;
}

esp_err_t lumia_mode_button_service(uint32_t now_ms,
                                    LumiaModeButtonEvent *event)
{
    bool sampled_pressed;
    int level;

    if (event != NULL) {
        *event = LUMIA_MODE_BUTTON_EVENT_NONE;
    }
    if (!s_mode_button.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    level = gpio_get_level(CONFIG_LUMIA_MODE_BUTTON_GPIO);
    if (level < 0) {
        return ESP_FAIL;
    }
    sampled_pressed = button_level_is_pressed(level);

    if (event != NULL) {
        *event = lumia_mode_button_logic_update(
            &s_mode_button.logic,
            sampled_pressed,
            now_ms,
            CONFIG_LUMIA_MODE_BUTTON_DEBOUNCE_MS,
            CONFIG_LUMIA_MODE_BUTTON_LONG_PRESS_MS);
    } else {
        (void)lumia_mode_button_logic_update(
            &s_mode_button.logic,
            sampled_pressed,
            now_ms,
            CONFIG_LUMIA_MODE_BUTTON_DEBOUNCE_MS,
            CONFIG_LUMIA_MODE_BUTTON_LONG_PRESS_MS);
    }
    return ESP_OK;
}
