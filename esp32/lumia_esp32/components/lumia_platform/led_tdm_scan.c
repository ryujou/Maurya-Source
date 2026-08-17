#include "led_tdm_scan.h"

#include <stdlib.h>
#include <string.h>

#include "sdkconfig.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_timer.h"
#include "effect_types.h"
#include "led_color_pipeline.h"
#include "led_route.h"
#include "led_tdm_framebuffer.h"

#define LUMIA_LED_TDM_SCAN_TASK_STACK_SIZE  3072u
#define LUMIA_LED_TDM_SCAN_TASK_PRIORITY    4u

typedef struct {
    bool initialized;
    uint8_t (*tx_buffer)[3];
    size_t tx_capacity;
    uint8_t next_channel;
    TaskHandle_t task_handle;
    uint32_t tx_error_count;
    uint32_t gpio_switch_error_count;
    uint32_t init_error_count;
    uint32_t max_scan_gap_us;
    int64_t last_scan_started_us;
    bool paused;
} LumiaLedTdmScanState;

static LumiaLedTdmScanState s_scan;

static size_t scan_max_leds_per_channel(void)
{
    size_t max_count = CONFIG_LUMIA_LED_TX_PHYSICAL_MAX_COUNT;
    size_t index;

    for (index = 0u; index < lumia_led_tdm_framebuffer_channel_count(); ++index) {
        uint16_t led_count = 0u;
        (void)lumia_led_tdm_framebuffer_front_channel((uint8_t)index,
                                                      &led_count,
                                                      NULL);
        if (led_count > max_count) {
            max_count = led_count;
        }
    }
    return max_count;
}

static void lumia_led_tdm_scan_task(void *arg)
{
    (void)arg;

    while (1) {
        if (__atomic_load_n(&s_scan.paused, __ATOMIC_ACQUIRE)) {
            vTaskDelay(pdMS_TO_TICKS(5u));
            continue;
        }
        if (s_scan.next_channel == 0u) {
            (void)lumia_led_tdm_framebuffer_consume_pending();
        }

        esp_err_t err = lumia_led_tdm_scan_step();
        if (err != ESP_OK) {
            vTaskDelay(pdMS_TO_TICKS(1u));
            continue;
        }
    }
}

esp_err_t lumia_led_tdm_scan_init(void)
{
    size_t max_leds_per_channel;
    esp_err_t err;
    BaseType_t task_created;

    if (s_scan.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    if (!lumia_led_tdm_framebuffer_is_initialized()) {
        return ESP_ERR_INVALID_STATE;
    }

    max_leds_per_channel = scan_max_leds_per_channel();
    if (max_leds_per_channel == 0u) {
        return ESP_ERR_INVALID_SIZE;
    }

    s_scan.tx_buffer = calloc(max_leds_per_channel, sizeof(*s_scan.tx_buffer));
    if (s_scan.tx_buffer == NULL) {
        return ESP_ERR_NO_MEM;
    }

    uint8_t initial_gpio = 0u;
    (void)lumia_led_tdm_framebuffer_front_channel(0u, NULL, &initial_gpio);
    err = lumia_led_route_init(max_leds_per_channel, initial_gpio);
    if (err != ESP_OK) {
        free(s_scan.tx_buffer);
        s_scan.tx_buffer = NULL;
        __atomic_add_fetch(&s_scan.init_error_count, 1u, __ATOMIC_RELAXED);
        return err;
    }

    s_scan.tx_capacity = max_leds_per_channel;
    s_scan.initialized = true;
    s_scan.next_channel = 0u;
    task_created = xTaskCreate(lumia_led_tdm_scan_task,
                               "led_tdm_scan",
                               LUMIA_LED_TDM_SCAN_TASK_STACK_SIZE,
                               NULL,
                               LUMIA_LED_TDM_SCAN_TASK_PRIORITY,
                               &s_scan.task_handle);
    if (task_created != pdPASS) {
        free(s_scan.tx_buffer);
        memset(&s_scan, 0, sizeof(s_scan));
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}

esp_err_t lumia_led_tdm_scan_step(void)
{
    uint16_t led_count = 0u;
    uint8_t gpio_num = 0u;
    const LumiaRgb *source;

    if (!s_scan.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    int64_t scan_started_us = esp_timer_get_time();
    if (s_scan.last_scan_started_us != 0) {
        uint32_t gap_us = (uint32_t)(scan_started_us - s_scan.last_scan_started_us);
        uint32_t current_max = __atomic_load_n(&s_scan.max_scan_gap_us,
                                               __ATOMIC_RELAXED);
        while (gap_us > current_max &&
               !__atomic_compare_exchange_n(&s_scan.max_scan_gap_us,
                                            &current_max,
                                            gap_us,
                                            false,
                                            __ATOMIC_RELAXED,
                                            __ATOMIC_RELAXED)) {
        }
    }
    s_scan.last_scan_started_us = scan_started_us;

    source = lumia_led_tdm_framebuffer_front_channel(s_scan.next_channel,
                                                     &led_count,
                                                     &gpio_num);
    if (source == NULL || led_count > s_scan.tx_capacity) {
        return ESP_ERR_INVALID_STATE;
    }

    lumia_led_color_pipeline_prepare(source, s_scan.tx_buffer, led_count);

    esp_err_t err = lumia_led_route_select(gpio_num);
    if (err != ESP_OK) {
        __atomic_add_fetch(&s_scan.gpio_switch_error_count, 1u,
                           __ATOMIC_RELAXED);
        return err;
    }
    err = lumia_led_route_write(s_scan.tx_buffer, led_count);
    if (err != ESP_OK) {
        __atomic_add_fetch(&s_scan.tx_error_count, 1u, __ATOMIC_RELAXED);
        return err;
    }

    s_scan.next_channel =
        (uint8_t)((s_scan.next_channel + 1u) %
                  lumia_led_tdm_framebuffer_channel_count());
    return ESP_OK;
}

esp_err_t lumia_led_tdm_scan_flush(void)
{
    if (!s_scan.initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    (void)lumia_led_tdm_framebuffer_publish();
    return ESP_OK;
}

bool lumia_led_tdm_scan_is_initialized(void)
{
    return s_scan.initialized;
}

void lumia_led_tdm_scan_get_diagnostics(LumiaLedTdmDiagnostics *diagnostics)
{
    if (diagnostics == NULL) {
        return;
    }
    diagnostics->tx_error_count =
        __atomic_load_n(&s_scan.tx_error_count, __ATOMIC_RELAXED);
    diagnostics->gpio_switch_error_count =
        __atomic_load_n(&s_scan.gpio_switch_error_count, __ATOMIC_RELAXED);
    diagnostics->init_error_count =
        __atomic_load_n(&s_scan.init_error_count, __ATOMIC_RELAXED);
    diagnostics->max_scan_gap_us =
        __atomic_load_n(&s_scan.max_scan_gap_us, __ATOMIC_RELAXED);
}

void lumia_led_tdm_scan_clear_diagnostics(void)
{
    __atomic_store_n(&s_scan.tx_error_count, 0u, __ATOMIC_RELAXED);
    __atomic_store_n(&s_scan.gpio_switch_error_count, 0u, __ATOMIC_RELAXED);
    __atomic_store_n(&s_scan.init_error_count, 0u, __ATOMIC_RELAXED);
    __atomic_store_n(&s_scan.max_scan_gap_us, 0u, __ATOMIC_RELAXED);
}

void lumia_led_tdm_scan_set_paused(bool paused)
{
    __atomic_store_n(&s_scan.paused, paused, __ATOMIC_RELEASE);
}
