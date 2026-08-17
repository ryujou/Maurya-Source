#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "config_store.h"
#include "storage_backend.h"

#define FAKE_FLASH_SIZE  0x4000u

static uint8_t s_flash[FAKE_FLASH_SIZE];
static bool s_flash_initialized;

esp_err_t storage_backend_init(void)
{
    if (!s_flash_initialized) {
        memset(s_flash, 0xFF, sizeof(s_flash));
        s_flash_initialized = true;
    }
    return ESP_OK;
}

size_t storage_backend_size(void)
{
    return sizeof(s_flash);
}

esp_err_t storage_backend_read(size_t offset, void *data, size_t length)
{
    if (offset > sizeof(s_flash) || length > sizeof(s_flash) - offset) {
        return ESP_ERR_INVALID_ARG;
    }
    memcpy(data, s_flash + offset, length);
    return ESP_OK;
}

esp_err_t storage_backend_write(size_t offset,
                                const void *data,
                                size_t length)
{
    const uint8_t *source = data;
    if (offset > sizeof(s_flash) || length > sizeof(s_flash) - offset) {
        return ESP_ERR_INVALID_ARG;
    }
    for (size_t index = 0u; index < length; ++index) {
        s_flash[offset + index] &= source[index];
    }
    return ESP_OK;
}

esp_err_t storage_backend_erase(size_t offset, size_t length)
{
    if (offset > sizeof(s_flash) || length > sizeof(s_flash) - offset) {
        return ESP_ERR_INVALID_ARG;
    }
    memset(s_flash + offset, 0xFF, length);
    return ESP_OK;
}

static PersistentConfig make_config(uint16_t hue, uint8_t address)
{
    PersistentConfig config = {
        .scene_mode = 4u,
        .scene_param = 90u,
        .device_addr = address,
        .led_global_bri = 220u,
        .led_gain_r = 255u,
        .led_gain_g = 176u,
        .led_gain_b = 240u,
    };
    for (uint8_t group = 0u; group < LUMIA_GROUP_COUNT; ++group) {
        config.groups[group].inner_mode = 1u;
        config.groups[group].hue = hue;
        config.groups[group].sat = 200u;
        config.groups[group].val = 180u;
        config.groups[group].inner_param = (uint8_t)(80u + group);
    }
    return config;
}

int main(void)
{
    PersistentConfig loaded;
    PersistentConfig first = make_config(120u, 1u);
    PersistentConfig second = make_config(240u, 2u);
    bool found;

    assert(config_store_init() == ESP_OK);
    assert(config_store_load(&loaded, &found) == ESP_OK);
    assert(!found);

    assert(config_store_save(&first) == ESP_OK);
    assert(config_store_active_slot() == 0);
    assert(config_store_active_sequence() == 1u);
    assert(config_store_load(&loaded, &found) == ESP_OK);
    assert(found && loaded.groups[0].hue == 120u && loaded.device_addr == 1u);

    assert(config_store_save(&second) == ESP_OK);
    assert(config_store_active_slot() == 1);
    assert(config_store_active_sequence() == 2u);
    assert(config_store_load(&loaded, &found) == ESP_OK);
    assert(found && loaded.groups[0].hue == 240u && loaded.device_addr == 2u);

    s_flash[CONFIG_STORE_SLOT_SIZE + 40u] = 0u;
    assert(config_store_init() == ESP_OK);
    assert(config_store_active_slot() == 0);
    assert(config_store_load(&loaded, &found) == ESP_OK);
    assert(found && loaded.groups[0].hue == 120u && loaded.device_addr == 1u);

    puts("config store host tests passed");
    return 0;
}
