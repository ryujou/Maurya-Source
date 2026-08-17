#include "led_tdm_framebuffer.h"

#include <stdlib.h>
#include <string.h>

#include "freertos/FreeRTOS.h"

typedef struct {
    bool initialized;
    LumiaLedTdmConfig config;
    LumiaRgb *front_buffer;
    LumiaRgb *back_buffer;
    LumiaRgb *pending_buffer;
    LumiaRgb *spare_buffer;
    portMUX_TYPE buffer_lock;
} LumiaLedTdmFramebufferState;

static LumiaLedTdmFramebufferState s_fb;

static bool config_is_valid(const LumiaLedTdmConfig *config)
{
    size_t index;
    uint32_t total_leds = 0u;
    uint32_t expected_offset = 0u;

    if (config == NULL ||
        config->channel_count == 0u ||
        config->channel_count > LUMIA_LED_TDM_CHANNEL_COUNT) {
        return false;
    }

    for (index = 0u; index < config->channel_count; ++index) {
        const LumiaLedTdmChannelConfig *channel = &config->channels[index];

        if (channel->led_count == 0u ||
            channel->offset != expected_offset) {
            return false;
        }
        total_leds += channel->led_count;
        expected_offset += channel->led_count;
    }

    return total_leds == config->total_leds && total_leds <= UINT16_MAX;
}

static void clear_rgb_frame(LumiaRgb *buffer, size_t count)
{
    if (buffer != NULL) {
        memset(buffer, 0, count * sizeof(*buffer));
    }
}

static esp_err_t validate_channel_index(uint8_t channel)
{
    if (!s_fb.initialized || channel >= s_fb.config.channel_count) {
        return ESP_ERR_INVALID_ARG;
    }
    return ESP_OK;
}

esp_err_t lumia_led_tdm_framebuffer_init(const LumiaLedTdmConfig *config)
{
    if (s_fb.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    if (!config_is_valid(config)) {
        return ESP_ERR_INVALID_ARG;
    }

    s_fb.front_buffer = calloc(config->total_leds, sizeof(*s_fb.front_buffer));
    s_fb.back_buffer = calloc(config->total_leds, sizeof(*s_fb.back_buffer));
    s_fb.spare_buffer = calloc(config->total_leds, sizeof(*s_fb.spare_buffer));
    if (s_fb.front_buffer == NULL || s_fb.back_buffer == NULL ||
        s_fb.spare_buffer == NULL) {
        free(s_fb.front_buffer);
        free(s_fb.back_buffer);
        free(s_fb.spare_buffer);
        memset(&s_fb, 0, sizeof(s_fb));
        return ESP_ERR_NO_MEM;
    }

    s_fb.config = *config;
    clear_rgb_frame(s_fb.front_buffer, config->total_leds);
    clear_rgb_frame(s_fb.back_buffer, config->total_leds);
    clear_rgb_frame(s_fb.spare_buffer, config->total_leds);
    s_fb.buffer_lock = (portMUX_TYPE)portMUX_INITIALIZER_UNLOCKED;
    s_fb.initialized = true;
    return ESP_OK;
}

esp_err_t lumia_led_tdm_framebuffer_set_linear(const LumiaRgb *pixels,
                                               size_t pixel_count)
{
    size_t copy_count;

    if (!s_fb.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    if (pixels == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    copy_count = pixel_count < s_fb.config.total_leds
                     ? pixel_count
                     : s_fb.config.total_leds;
    memcpy(s_fb.back_buffer, pixels, copy_count * sizeof(*pixels));
    if (copy_count < s_fb.config.total_leds) {
        memset(s_fb.back_buffer + copy_count,
               0,
               (s_fb.config.total_leds - copy_count) * sizeof(*s_fb.back_buffer));
    }
    return ESP_OK;
}

esp_err_t lumia_led_tdm_framebuffer_set_pixel(uint8_t channel,
                                              uint16_t index,
                                              uint8_t r,
                                              uint8_t g,
                                              uint8_t b)
{
    const LumiaLedTdmChannelConfig *cfg;
    uint16_t linear_index;
    esp_err_t err = validate_channel_index(channel);

    if (err != ESP_OK) {
        return err;
    }

    cfg = &s_fb.config.channels[channel];
    if (index >= cfg->led_count) {
        return ESP_ERR_INVALID_ARG;
    }

    linear_index = (uint16_t)(cfg->offset + index);
    s_fb.back_buffer[linear_index] = (LumiaRgb) {.r = r, .g = g, .b = b};
    return ESP_OK;
}

esp_err_t lumia_led_tdm_framebuffer_set_channel(uint8_t channel,
                                                const LumiaRgb *pixels,
                                                uint16_t count)
{
    const LumiaLedTdmChannelConfig *cfg;
    uint16_t copy_count;
    esp_err_t err = validate_channel_index(channel);

    if (err != ESP_OK) {
        return err;
    }
    if (pixels == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    cfg = &s_fb.config.channels[channel];
    copy_count = count < cfg->led_count ? count : cfg->led_count;
    memcpy(&s_fb.back_buffer[cfg->offset], pixels, copy_count * sizeof(*pixels));
    if (copy_count < cfg->led_count) {
        memset(&s_fb.back_buffer[cfg->offset + copy_count],
               0,
               (cfg->led_count - copy_count) * sizeof(*s_fb.back_buffer));
    }
    return ESP_OK;
}

bool lumia_led_tdm_framebuffer_publish(void)
{
    bool published = false;

    if (!s_fb.initialized) {
        return false;
    }

    portENTER_CRITICAL(&s_fb.buffer_lock);
    if (s_fb.pending_buffer == NULL && s_fb.spare_buffer != NULL) {
        s_fb.pending_buffer = s_fb.back_buffer;
        s_fb.back_buffer = s_fb.spare_buffer;
        s_fb.spare_buffer = NULL;
        published = true;
    }
    portEXIT_CRITICAL(&s_fb.buffer_lock);
    return published;
}

bool lumia_led_tdm_framebuffer_consume_pending(void)
{
    bool consumed = false;

    if (!s_fb.initialized) {
        return false;
    }

    portENTER_CRITICAL(&s_fb.buffer_lock);
    if (s_fb.pending_buffer != NULL) {
        s_fb.spare_buffer = s_fb.front_buffer;
        s_fb.front_buffer = s_fb.pending_buffer;
        s_fb.pending_buffer = NULL;
        consumed = true;
    }
    portEXIT_CRITICAL(&s_fb.buffer_lock);
    return consumed;
}

const LumiaRgb *lumia_led_tdm_framebuffer_front_channel(uint8_t channel,
                                                        uint16_t *led_count,
                                                        uint8_t *gpio_num)
{
    const LumiaLedTdmChannelConfig *cfg;

    if (validate_channel_index(channel) != ESP_OK) {
        return NULL;
    }

    cfg = &s_fb.config.channels[channel];
    if (led_count != NULL) {
        *led_count = cfg->led_count;
    }
    if (gpio_num != NULL) {
        *gpio_num = cfg->gpio_num;
    }
    return &s_fb.front_buffer[cfg->offset];
}

void lumia_led_tdm_framebuffer_clear_all(void)
{
    if (!s_fb.initialized) {
        return;
    }

    clear_rgb_frame(s_fb.front_buffer, s_fb.config.total_leds);
    clear_rgb_frame(s_fb.back_buffer, s_fb.config.total_leds);
    clear_rgb_frame(s_fb.pending_buffer, s_fb.config.total_leds);
    clear_rgb_frame(s_fb.spare_buffer, s_fb.config.total_leds);
}

size_t lumia_led_tdm_framebuffer_total_leds(void)
{
    return s_fb.initialized ? s_fb.config.total_leds : 0u;
}

size_t lumia_led_tdm_framebuffer_channel_count(void)
{
    return s_fb.initialized ? s_fb.config.channel_count : 0u;
}

bool lumia_led_tdm_framebuffer_is_initialized(void)
{
    return s_fb.initialized;
}
