#include "ble_status_led.h"

#include <stdbool.h>

#include "driver/gpio.h"
#include "sdkconfig.h"

static bool s_initialized;
static LumiaStatusLedPattern s_pattern;
static uint32_t s_pattern_started_ms;

static int led_level_for_on(bool on)
{
#if CONFIG_LUMIA_BLE_STATUS_LED_ACTIVE_LOW
    return on ? 0 : 1;
#else
    return on ? 1 : 0;
#endif
}

static esp_err_t set_led_on(bool on)
{
    return gpio_set_level(CONFIG_LUMIA_BLE_STATUS_LED_GPIO,
                          led_level_for_on(on));
}

esp_err_t lumia_ble_status_led_init(void)
{
    if (s_initialized) {
        return ESP_OK;
    }
    if (!GPIO_IS_VALID_OUTPUT_GPIO(CONFIG_LUMIA_BLE_STATUS_LED_GPIO)) {
        return ESP_ERR_INVALID_ARG;
    }

    const gpio_config_t io_conf = {
        .pin_bit_mask = 1ULL << CONFIG_LUMIA_BLE_STATUS_LED_GPIO,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };

    esp_err_t err = gpio_config(&io_conf);
    if (err != ESP_OK) {
        return err;
    }

    err = set_led_on(false);
    if (err != ESP_OK) {
        return err;
    }

    s_initialized = true;
    s_pattern = LUMIA_STATUS_LED_OFF;
    s_pattern_started_ms = 0u;
    return ESP_OK;
}

esp_err_t lumia_ble_status_led_set_connected(bool connected)
{
    if (!s_initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    s_pattern = connected ? LUMIA_STATUS_LED_SOLID : LUMIA_STATUS_LED_OFF;
    return set_led_on(connected);
}

esp_err_t lumia_status_led_set_pattern(LumiaStatusLedPattern pattern,
                                       uint32_t now_ms)
{
    if (!s_initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    if (pattern < LUMIA_STATUS_LED_OFF ||
        pattern > LUMIA_STATUS_LED_OTA) {
        return ESP_ERR_INVALID_ARG;
    }

    s_pattern = pattern;
    s_pattern_started_ms = now_ms;
    return lumia_status_led_service(now_ms);
}

esp_err_t lumia_status_led_service(uint32_t now_ms)
{
    uint32_t interval_ms;
    bool on;

    if (!s_initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    switch (s_pattern) {
        case LUMIA_STATUS_LED_SOLID:
            on = true;
            break;
        case LUMIA_STATUS_LED_WIFI_BLINK:
            interval_ms = 500u;
            on = ((uint32_t)(now_ms - s_pattern_started_ms) / interval_ms) % 2u == 0u;
            break;
        case LUMIA_STATUS_LED_SWITCHING:
            interval_ms = 100u;
            on = ((uint32_t)(now_ms - s_pattern_started_ms) / interval_ms) % 2u == 0u;
            break;
        case LUMIA_STATUS_LED_OTA: {
            uint32_t phase = (uint32_t)(now_ms - s_pattern_started_ms) % 1200u;
            on = phase < 100u || (phase >= 200u && phase < 300u);
            break;
        }
        case LUMIA_STATUS_LED_OFF:
        default:
            on = false;
            break;
    }
    return set_led_on(on);
}
