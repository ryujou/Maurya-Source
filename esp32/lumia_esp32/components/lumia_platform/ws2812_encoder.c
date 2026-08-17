#include "ws2812_encoder.h"

#include <stdlib.h>

#include "esp_attr.h"
#include "esp_check.h"

static const char *TAG = "lumia_ws2812_enc";

typedef struct {
    rmt_encoder_t base;
    rmt_encoder_t *bytes_encoder;
    rmt_encoder_t *copy_encoder;
    rmt_symbol_word_t reset_symbol;
    int state;
} LumiaWs2812Encoder;

RMT_ENCODER_FUNC_ATTR
static size_t ws2812_encode(rmt_encoder_t *encoder,
                            rmt_channel_handle_t channel,
                            const void *primary_data,
                            size_t data_size,
                            rmt_encode_state_t *ret_state)
{
    LumiaWs2812Encoder *self = __containerof(encoder, LumiaWs2812Encoder, base);
    rmt_encode_state_t session_state = RMT_ENCODING_RESET;
    rmt_encode_state_t state = RMT_ENCODING_RESET;
    size_t symbols = 0u;

    if (self->state == 0) {
        symbols += self->bytes_encoder->encode(self->bytes_encoder,
                                               channel,
                                               primary_data,
                                               data_size,
                                               &session_state);
        if (session_state & RMT_ENCODING_COMPLETE) {
            self->state = 1;
        }
        if (session_state & RMT_ENCODING_MEM_FULL) {
            state |= RMT_ENCODING_MEM_FULL;
            goto done;
        }
    }

    if (self->state == 1) {
        session_state = RMT_ENCODING_RESET;
        symbols += self->copy_encoder->encode(self->copy_encoder,
                                              channel,
                                              &self->reset_symbol,
                                              sizeof(self->reset_symbol),
                                              &session_state);
        if (session_state & RMT_ENCODING_COMPLETE) {
            self->state = 0;
            state |= RMT_ENCODING_COMPLETE;
        }
        if (session_state & RMT_ENCODING_MEM_FULL) {
            state |= RMT_ENCODING_MEM_FULL;
        }
    }

done:
    *ret_state = state;
    return symbols;
}

static esp_err_t ws2812_delete(rmt_encoder_t *encoder)
{
    LumiaWs2812Encoder *self = __containerof(encoder, LumiaWs2812Encoder, base);
    (void)rmt_del_encoder(self->bytes_encoder);
    (void)rmt_del_encoder(self->copy_encoder);
    free(self);
    return ESP_OK;
}

RMT_ENCODER_FUNC_ATTR
static esp_err_t ws2812_reset(rmt_encoder_t *encoder)
{
    LumiaWs2812Encoder *self = __containerof(encoder, LumiaWs2812Encoder, base);
    ESP_RETURN_ON_ERROR(rmt_encoder_reset(self->bytes_encoder), TAG,
                        "reset bytes encoder failed");
    ESP_RETURN_ON_ERROR(rmt_encoder_reset(self->copy_encoder), TAG,
                        "reset copy encoder failed");
    self->state = 0;
    return ESP_OK;
}

esp_err_t lumia_ws2812_new_encoder(const LumiaWs2812EncoderConfig *config,
                                   rmt_encoder_handle_t *ret_encoder)
{
    esp_err_t ret = ESP_OK;
    LumiaWs2812Encoder *self = NULL;
    uint32_t half_reset_ticks;

    ESP_GOTO_ON_FALSE(config != NULL && ret_encoder != NULL &&
                          config->resolution_hz != 0u && config->reset_us != 0u,
                      ESP_ERR_INVALID_ARG, fail, TAG, "invalid encoder config");

    self = rmt_alloc_encoder_mem(sizeof(*self));
    ESP_GOTO_ON_FALSE(self != NULL, ESP_ERR_NO_MEM, fail, TAG,
                      "allocate encoder failed");
    self->base.encode = ws2812_encode;
    self->base.del = ws2812_delete;
    self->base.reset = ws2812_reset;

    const rmt_bytes_encoder_config_t bytes_config = {
        .bit0 = {.level0 = 1, .duration0 = 4, .level1 = 0, .duration1 = 8},
        .bit1 = {.level0 = 1, .duration0 = 8, .level1 = 0, .duration1 = 4},
        .flags.msb_first = 1,
    };
    ESP_GOTO_ON_ERROR(rmt_new_bytes_encoder(&bytes_config, &self->bytes_encoder),
                      fail, TAG, "create bytes encoder failed");

    const rmt_copy_encoder_config_t copy_config = {};
    ESP_GOTO_ON_ERROR(rmt_new_copy_encoder(&copy_config, &self->copy_encoder),
                      fail, TAG, "create copy encoder failed");

    half_reset_ticks = (config->resolution_hz / 1000000u) * config->reset_us / 2u;
    ESP_GOTO_ON_FALSE(half_reset_ticks > 0u && half_reset_ticks <= 32767u,
                      ESP_ERR_INVALID_ARG, fail, TAG, "reset duration out of range");
    self->reset_symbol = (rmt_symbol_word_t) {
        .level0 = 0, .duration0 = half_reset_ticks,
        .level1 = 0, .duration1 = half_reset_ticks,
    };
    *ret_encoder = &self->base;
    return ESP_OK;

fail:
    if (self != NULL) {
        if (self->bytes_encoder != NULL) {
            (void)rmt_del_encoder(self->bytes_encoder);
        }
        if (self->copy_encoder != NULL) {
            (void)rmt_del_encoder(self->copy_encoder);
        }
        free(self);
    }
    return ret;
}
