#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>

#include "led_strip_driver.h"
#include "led_tdm.h"

static LumiaLedTdmConfig captured_config;
static bool init_called;
static bool set_linear_called;
static bool flush_called;
static const LumiaRgb *last_pixels;
static size_t last_pixel_count;
static size_t flush_call_count;
static LumiaRgb first_captured_pixel;
static LumiaRgb last_captured_pixel;
static bool scan_paused;

void lumia_led_tdm_scan_set_paused(bool paused)
{
    scan_paused = paused;
}

esp_err_t lumia_led_tdm_init(const LumiaLedTdmConfig *config)
{
    assert(config != NULL);
    captured_config = *config;
    init_called = true;
    return ESP_OK;
}

esp_err_t lumia_led_tdm_set_linear_frame(const LumiaRgb *pixels, size_t pixel_count)
{
    assert(pixels != NULL);
    set_linear_called = true;
    last_pixels = pixels;
    last_pixel_count = pixel_count;
    if (pixel_count > 0u) {
        first_captured_pixel = pixels[0];
        last_captured_pixel = pixels[pixel_count - 1u];
    }
    return ESP_OK;
}

esp_err_t lumia_led_tdm_flush(void)
{
    ++flush_call_count;
    flush_called = true;
    return ESP_OK;
}

esp_err_t lumia_led_tdm_clear(void)
{
    return ESP_OK;
}

static void assert_default_routing(void)
{
    const uint8_t expected_gpios[LUMIA_LED_TDM_CHANNEL_COUNT] = {
        21u, 20u, 10u, 7u, 3u, 0u, 1u,
    };
    const uint16_t expected_offsets[LUMIA_LED_TDM_CHANNEL_COUNT] = {
        0u, 6u, 12u, 18u, 24u, 30u, 36u,
    };
    size_t index;

    assert(lumia_led_strip_init() == ESP_OK);
    assert(init_called);
    assert(captured_config.channel_count == LUMIA_LED_TDM_CHANNEL_COUNT);
    assert(captured_config.total_leds == LUMIA_EFFECT_LED_COUNT);

    for (index = 0u; index < LUMIA_LED_TDM_CHANNEL_COUNT; ++index) {
        assert(captured_config.channels[index].gpio_num == expected_gpios[index]);
        assert(captured_config.channels[index].led_count ==
               LUMIA_EFFECT_GROUP_LED_COUNT);
        assert(captured_config.channels[index].offset == expected_offsets[index]);
    }
}

static void assert_write_preserves_linear_pixels(void)
{
    LumiaLedStripFrame frame = {0};

    frame[0][0] = 1u;
    frame[0][1] = 2u;
    frame[0][2] = 3u;
    frame[LUMIA_EFFECT_LED_COUNT - 1u][0] = 4u;
    frame[LUMIA_EFFECT_LED_COUNT - 1u][1] = 5u;
    frame[LUMIA_EFFECT_LED_COUNT - 1u][2] = 6u;

    assert(lumia_led_strip_write(frame) == ESP_OK);
    assert(set_linear_called);
    assert(flush_called);
    assert(last_pixels != NULL);
    assert(flush_call_count == 1u);
    assert(last_pixel_count == LUMIA_EFFECT_LED_COUNT);
    assert(first_captured_pixel.r == 1u);
    assert(first_captured_pixel.g == 2u);
    assert(first_captured_pixel.b == 3u);
    assert(last_captured_pixel.r == 4u);
    assert(last_captured_pixel.g == 5u);
    assert(last_captured_pixel.b == 6u);
}

static void assert_pause_is_forwarded(void)
{
    lumia_led_strip_set_paused(true);
    assert(scan_paused);
    lumia_led_strip_set_paused(false);
    assert(!scan_paused);
}

int main(void)
{
    assert_default_routing();
    assert_write_preserves_linear_pixels();
    assert_pause_is_forwarded();
    puts("led strip routing tests passed");
    return 0;
}
