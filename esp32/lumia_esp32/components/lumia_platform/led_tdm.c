#include "led_tdm.h"

#include "esp_log.h"

#include "led_tdm_framebuffer.h"
#include "led_tdm_scan.h"

static const char *TAG = "lumia_led_tdm";

esp_err_t lumia_led_tdm_init(const LumiaLedTdmConfig *config)
{
    esp_err_t err = lumia_led_tdm_framebuffer_init(config);
    if (err != ESP_OK) {
        return err;
    }

    err = lumia_led_tdm_scan_init();
    if (err == ESP_OK) {
        ESP_LOGI(TAG,
                 "initialized: channels=%u total_leds=%u",
                 (unsigned)lumia_led_tdm_framebuffer_channel_count(),
                 (unsigned)lumia_led_tdm_framebuffer_total_leds());
    }
    return err;
}

esp_err_t lumia_led_tdm_set_linear_frame(const LumiaRgb *pixels, size_t pixel_count)
{
    return lumia_led_tdm_framebuffer_set_linear(pixels, pixel_count);
}

esp_err_t lumia_led_tdm_set_pixel(uint8_t channel,
                                  uint16_t index,
                                  uint8_t r,
                                  uint8_t g,
                                  uint8_t b)
{
    return lumia_led_tdm_framebuffer_set_pixel(channel, index, r, g, b);
}

esp_err_t lumia_led_tdm_set_channel_frame(uint8_t channel,
                                          const LumiaRgb *pixels,
                                          uint16_t count)
{
    return lumia_led_tdm_framebuffer_set_channel(channel, pixels, count);
}

esp_err_t lumia_led_tdm_flush(void)
{
    return lumia_led_tdm_scan_flush();
}

esp_err_t lumia_led_tdm_clear(void)
{
    lumia_led_tdm_framebuffer_clear_all();
    return lumia_led_tdm_scan_flush();
}

size_t lumia_led_tdm_total_leds(void)
{
    return lumia_led_tdm_framebuffer_total_leds();
}

bool lumia_led_tdm_is_initialized(void)
{
    return lumia_led_tdm_framebuffer_is_initialized() &&
           lumia_led_tdm_scan_is_initialized();
}

void lumia_led_tdm_get_diagnostics(LumiaLedTdmDiagnostics *diagnostics)
{
    lumia_led_tdm_scan_get_diagnostics(diagnostics);
}

void lumia_led_tdm_clear_diagnostics(void)
{
    lumia_led_tdm_scan_clear_diagnostics();
}
