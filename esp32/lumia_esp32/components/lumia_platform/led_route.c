#include "led_route.h"

#include "ws2812_tx.h"

esp_err_t lumia_led_route_init(size_t max_leds, int initial_gpio)
{
    return lumia_ws2812_tx_init(max_leds, initial_gpio);
}

esp_err_t lumia_led_route_select(int gpio_num)
{
    return lumia_ws2812_tx_select_gpio(gpio_num);
}

esp_err_t lumia_led_route_write(const uint8_t (*grb)[3], size_t led_count)
{
    return lumia_ws2812_tx_write_selected(grb, led_count);
}

esp_err_t lumia_led_route_clear(void)
{
    return lumia_ws2812_tx_clear_selected();
}
