#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#include "driver/gpio.h"
#include "sleep_switch.h"

static int s_gpio_level;

esp_err_t gpio_config(const gpio_config_t *config)
{
    assert(config != NULL);
    assert(config->pin_bit_mask == (1ULL << 4));
    return ESP_OK;
}

int gpio_get_level(int gpio_num)
{
    assert(gpio_num == 4);
    return s_gpio_level;
}

int esp_sleep_is_valid_wakeup_gpio(int gpio_num)
{
    return gpio_num == 4;
}

esp_err_t esp_sleep_disable_wakeup_source(int source)
{
    (void)source;
    return ESP_OK;
}

esp_err_t esp_sleep_enable_gpio_wakeup_on_hp_periph_powerdown(uint64_t mask,
                                                              int level)
{
    (void)mask;
    (void)level;
    return ESP_OK;
}

int main(void)
{
    bool sleep_requested = false;

    s_gpio_level = 0;
    assert(lumia_sleep_switch_init(100u, &sleep_requested) == ESP_OK);
    assert(sleep_requested);

    puts("sleep switch startup-off host test passed");
    return 0;
}
