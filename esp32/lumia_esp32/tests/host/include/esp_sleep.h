#pragma once

#include <stdint.h>

#include "esp_err.h"

#define ESP_SLEEP_WAKEUP_ALL 0
#define ESP_GPIO_WAKEUP_GPIO_HIGH 1

int esp_sleep_is_valid_wakeup_gpio(int gpio_num);
esp_err_t esp_sleep_disable_wakeup_source(int source);
esp_err_t esp_sleep_enable_gpio_wakeup_on_hp_periph_powerdown(uint64_t mask,
                                                              int level);
