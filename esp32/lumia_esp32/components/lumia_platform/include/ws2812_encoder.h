#pragma once

#include <stdint.h>

#include "driver/rmt_encoder.h"
#include "esp_err.h"

typedef struct {
    uint32_t resolution_hz;
    uint32_t reset_us;
} LumiaWs2812EncoderConfig;

esp_err_t lumia_ws2812_new_encoder(const LumiaWs2812EncoderConfig *config,
                                   rmt_encoder_handle_t *ret_encoder);
