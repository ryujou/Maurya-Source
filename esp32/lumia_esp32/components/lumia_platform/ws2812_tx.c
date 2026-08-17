#include "ws2812_tx.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "driver/gpio.h"
#include "driver/rmt_tx.h"
#include "esp_check.h"
#include "sdkconfig.h"
#include "ws2812_encoder.h"

#define LUMIA_WS2812_RESOLUTION_HZ  (10u * 1000u * 1000u)
#define LUMIA_WS2812_MEM_SYMBOLS    96u
#define LUMIA_WS2812_INTR_PRIORITY  3

typedef struct {
    rmt_channel_handle_t channel;
    rmt_encoder_handle_t encoder;
    uint8_t *payload;
    size_t max_leds;
    int active_gpio;
    bool initialized;
} LumiaWs2812TxState;

static LumiaWs2812TxState s_tx;

static void ws2812_release(void)
{
    if (s_tx.channel != NULL) {
        (void)rmt_disable(s_tx.channel);
    }
    if (s_tx.encoder != NULL) {
        (void)rmt_del_encoder(s_tx.encoder);
    }
    if (s_tx.channel != NULL) {
        (void)rmt_del_channel(s_tx.channel);
    }
    free(s_tx.payload);
    memset(&s_tx, 0, sizeof(s_tx));
    s_tx.active_gpio = -1;
}

esp_err_t lumia_ws2812_tx_init(size_t max_leds, int initial_gpio)
{
    esp_err_t err;

    if (s_tx.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    if (max_leds == 0u || !GPIO_IS_VALID_OUTPUT_GPIO(initial_gpio)) {
        return ESP_ERR_INVALID_ARG;
    }

    s_tx.payload = calloc(max_leds, 3u);
    if (s_tx.payload == NULL) {
        return ESP_ERR_NO_MEM;
    }
    s_tx.max_leds = max_leds;
    s_tx.active_gpio = initial_gpio;

    const rmt_tx_channel_config_t channel_config = {
        .gpio_num = initial_gpio,
        .clk_src = RMT_CLK_SRC_DEFAULT,
        .resolution_hz = LUMIA_WS2812_RESOLUTION_HZ,
        .mem_block_symbols = LUMIA_WS2812_MEM_SYMBOLS,
        .trans_queue_depth = 1,
        .intr_priority = LUMIA_WS2812_INTR_PRIORITY,
        .flags.with_dma = false,
        .flags.invert_out = false,
    };
    err = rmt_new_tx_channel(&channel_config, &s_tx.channel);
    if (err != ESP_OK) {
        ws2812_release();
        return err;
    }

    const LumiaWs2812EncoderConfig encoder_config = {
        .resolution_hz = LUMIA_WS2812_RESOLUTION_HZ,
        .reset_us = CONFIG_LUMIA_LED_TX_RESET_US,
    };
    err = lumia_ws2812_new_encoder(&encoder_config, &s_tx.encoder);
    if (err != ESP_OK) {
        ws2812_release();
        return err;
    }
    err = rmt_enable(s_tx.channel);
    if (err != ESP_OK) {
        ws2812_release();
        return err;
    }

    s_tx.initialized = true;
    return ESP_OK;
}

esp_err_t lumia_ws2812_tx_select_gpio(int gpio_num)
{
    esp_err_t err;

    if (!s_tx.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    if (!GPIO_IS_VALID_OUTPUT_GPIO(gpio_num)) {
        return ESP_ERR_INVALID_ARG;
    }
    if (s_tx.active_gpio == gpio_num) {
        return ESP_OK;
    }

    ESP_RETURN_ON_ERROR(rmt_tx_wait_all_done(s_tx.channel, -1),
                        "lumia_ws2812", "wait before GPIO switch failed");
    ESP_RETURN_ON_ERROR(rmt_disable(s_tx.channel),
                        "lumia_ws2812", "disable before GPIO switch failed");
    err = rmt_tx_switch_gpio(s_tx.channel, gpio_num, false);
    if (err != ESP_OK) {
        (void)rmt_enable(s_tx.channel);
        return err;
    }
    err = rmt_enable(s_tx.channel);
    if (err != ESP_OK) {
        return err;
    }
    s_tx.active_gpio = gpio_num;
    return ESP_OK;
}

esp_err_t lumia_ws2812_tx_write_selected(const uint8_t (*grb)[3],
                                         size_t led_count)
{
    if (!s_tx.initialized || s_tx.channel == NULL || s_tx.encoder == NULL) {
        return ESP_ERR_INVALID_STATE;
    }
    if (grb == NULL || led_count > s_tx.max_leds) {
        return ESP_ERR_INVALID_ARG;
    }

    memcpy(s_tx.payload, grb, led_count * 3u);
    if (led_count < s_tx.max_leds) {
        memset(s_tx.payload + led_count * 3u, 0,
               (s_tx.max_leds - led_count) * 3u);
    }

    const rmt_transmit_config_t tx_config = {
        .loop_count = 0,
        .flags.eot_level = 0,
    };
    ESP_RETURN_ON_ERROR(rmt_transmit(s_tx.channel,
                                     s_tx.encoder,
                                     s_tx.payload,
                                     s_tx.max_leds * 3u,
                                     &tx_config),
                        "lumia_ws2812", "transmit failed");
    return rmt_tx_wait_all_done(s_tx.channel, -1);
}

esp_err_t lumia_ws2812_tx_clear_selected(void)
{
    if (!s_tx.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    memset(s_tx.payload, 0, s_tx.max_leds * 3u);
    return lumia_ws2812_tx_write_selected((const uint8_t (*)[3])s_tx.payload,
                                          s_tx.max_leds);
}
