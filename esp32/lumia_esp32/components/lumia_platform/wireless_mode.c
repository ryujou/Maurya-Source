#include "wireless_mode.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "nvs.h"
#include "nvs_flash.h"

#define WIRELESS_MODE_NAMESPACE "lumia_sys"
#define WIRELESS_MODE_KEY       "wireless"

static bool mode_is_valid(uint8_t value)
{
    return value == (uint8_t)LUMIA_WIRELESS_MODE_BLE ||
           value == (uint8_t)LUMIA_WIRELESS_MODE_WIFI;
}

esp_err_t lumia_wireless_mode_store_init(void)
{
    esp_err_t err = nvs_flash_init();

    if (err == ESP_ERR_NVS_NO_FREE_PAGES ||
        err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        err = nvs_flash_erase();
        if (err == ESP_OK) {
            err = nvs_flash_init();
        }
    }
    return err;
}

esp_err_t lumia_wireless_mode_load(LumiaWirelessMode *mode)
{
    nvs_handle_t handle;
    uint8_t stored = (uint8_t)LUMIA_WIRELESS_MODE_BLE;
    esp_err_t err;

    if (mode == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    *mode = LUMIA_WIRELESS_MODE_BLE;

    err = nvs_open(WIRELESS_MODE_NAMESPACE, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;
    }
    if (err != ESP_OK) {
        return err;
    }

    err = nvs_get_u8(handle, WIRELESS_MODE_KEY, &stored);
    nvs_close(handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;
    }
    if (err != ESP_OK) {
        return err;
    }
    if (!mode_is_valid(stored)) {
        return lumia_wireless_mode_save(LUMIA_WIRELESS_MODE_BLE);
    }

    *mode = (LumiaWirelessMode)stored;
    return ESP_OK;
}

esp_err_t lumia_wireless_mode_save(LumiaWirelessMode mode)
{
    nvs_handle_t handle;
    esp_err_t err;

    if (!mode_is_valid((uint8_t)mode)) {
        return ESP_ERR_INVALID_ARG;
    }

    err = nvs_open(WIRELESS_MODE_NAMESPACE, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        return err;
    }
    err = nvs_set_u8(handle, WIRELESS_MODE_KEY, (uint8_t)mode);
    if (err == ESP_OK) {
        err = nvs_commit(handle);
    }
    nvs_close(handle);
    return err;
}

const char *lumia_wireless_mode_name(LumiaWirelessMode mode)
{
    return mode == LUMIA_WIRELESS_MODE_WIFI ? "wifi" : "ble";
}
