#include "led_strip_driver.h"

#include "led_tdm.h"
#include "led_tdm_scan.h"
#include "sdkconfig.h"

#if CONFIG_LUMIA_LED_CH1_COUNT != LUMIA_EFFECT_GROUP_LED_COUNT || \
    CONFIG_LUMIA_LED_CH2_COUNT != LUMIA_EFFECT_GROUP_LED_COUNT || \
    CONFIG_LUMIA_LED_CH3_COUNT != LUMIA_EFFECT_GROUP_LED_COUNT || \
    CONFIG_LUMIA_LED_CH4_COUNT != LUMIA_EFFECT_GROUP_LED_COUNT || \
    CONFIG_LUMIA_LED_CH5_COUNT != LUMIA_EFFECT_GROUP_LED_COUNT || \
    CONFIG_LUMIA_LED_CH6_COUNT != LUMIA_EFFECT_GROUP_LED_COUNT || \
    CONFIG_LUMIA_LED_CH7_COUNT != LUMIA_EFFECT_GROUP_LED_COUNT
#error "Maurya requires exactly 7 LED channels with 6 LEDs per channel"
#endif

static const LumiaLedTdmConfig s_default_tdm_config = {
    .channel_count = LUMIA_LED_TDM_CHANNEL_COUNT,
    .total_leds = CONFIG_LUMIA_LED_CH1_COUNT +
                  CONFIG_LUMIA_LED_CH2_COUNT +
                  CONFIG_LUMIA_LED_CH3_COUNT +
                  CONFIG_LUMIA_LED_CH4_COUNT +
                  CONFIG_LUMIA_LED_CH5_COUNT +
                  CONFIG_LUMIA_LED_CH6_COUNT +
                  CONFIG_LUMIA_LED_CH7_COUNT,
    .channels = {
        {
            .gpio_num = CONFIG_LUMIA_LED_CH7_GPIO,
            .led_count = CONFIG_LUMIA_LED_CH7_COUNT,
            .offset = 0u,
        },
        {
            .gpio_num = CONFIG_LUMIA_LED_CH6_GPIO,
            .led_count = CONFIG_LUMIA_LED_CH6_COUNT,
            .offset = CONFIG_LUMIA_LED_CH7_COUNT,
        },
        {
            .gpio_num = CONFIG_LUMIA_LED_CH5_GPIO,
            .led_count = CONFIG_LUMIA_LED_CH5_COUNT,
            .offset = CONFIG_LUMIA_LED_CH7_COUNT +
                      CONFIG_LUMIA_LED_CH6_COUNT,
        },
        {
            .gpio_num = CONFIG_LUMIA_LED_CH4_GPIO,
            .led_count = CONFIG_LUMIA_LED_CH4_COUNT,
            .offset = CONFIG_LUMIA_LED_CH7_COUNT +
                      CONFIG_LUMIA_LED_CH6_COUNT +
                      CONFIG_LUMIA_LED_CH5_COUNT,
        },
        {
            .gpio_num = CONFIG_LUMIA_LED_CH3_GPIO,
            .led_count = CONFIG_LUMIA_LED_CH3_COUNT,
            .offset = CONFIG_LUMIA_LED_CH7_COUNT +
                      CONFIG_LUMIA_LED_CH6_COUNT +
                      CONFIG_LUMIA_LED_CH5_COUNT +
                      CONFIG_LUMIA_LED_CH4_COUNT,
        },
        {
            .gpio_num = CONFIG_LUMIA_LED_CH1_GPIO,
            .led_count = CONFIG_LUMIA_LED_CH1_COUNT,
            .offset = CONFIG_LUMIA_LED_CH7_COUNT +
                      CONFIG_LUMIA_LED_CH6_COUNT +
                      CONFIG_LUMIA_LED_CH5_COUNT +
                      CONFIG_LUMIA_LED_CH4_COUNT +
                      CONFIG_LUMIA_LED_CH3_COUNT,
        },
        {
            .gpio_num = CONFIG_LUMIA_LED_CH2_GPIO,
            .led_count = CONFIG_LUMIA_LED_CH2_COUNT,
            .offset = CONFIG_LUMIA_LED_CH7_COUNT +
                      CONFIG_LUMIA_LED_CH6_COUNT +
                      CONFIG_LUMIA_LED_CH5_COUNT +
                      CONFIG_LUMIA_LED_CH4_COUNT +
                      CONFIG_LUMIA_LED_CH3_COUNT +
                      CONFIG_LUMIA_LED_CH1_COUNT,
        },
    },

};

esp_err_t lumia_led_strip_init(void)
{
    return lumia_led_tdm_init(&s_default_tdm_config);
}

esp_err_t lumia_led_strip_write(const LumiaLedStripFrame rgb)
{
    LumiaRgb linear_frame[LUMIA_EFFECT_LED_COUNT];
    size_t index;

    for (index = 0u; index < LUMIA_EFFECT_LED_COUNT; ++index) {
        linear_frame[index].r = rgb[index][0];
        linear_frame[index].g = rgb[index][1];
        linear_frame[index].b = rgb[index][2];
    }

    esp_err_t err = lumia_led_tdm_set_linear_frame(
        linear_frame,
        LUMIA_EFFECT_LED_COUNT);
    if (err != ESP_OK) {
        return err;
    }
    return lumia_led_tdm_flush();
}

esp_err_t lumia_led_strip_clear(void)
{
    return lumia_led_tdm_clear();
}

void lumia_led_strip_set_paused(bool paused)
{
    lumia_led_tdm_scan_set_paused(paused);
}
