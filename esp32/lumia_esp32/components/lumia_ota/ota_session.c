#include "ota_session.h"

#include <stdio.h>
#include <string.h>

#include "esp_mac.h"
#include "esp_random.h"
#include "nvs.h"
#include "sdkconfig.h"

#define OTA_NAMESPACE "maurya_ota"
#define KEY_PENDING   "pending"
#define KEY_FORCE_BLE "force_ble"
#define KEY_TOKEN     "token"
#define KEY_NONCE     "nonce"

static esp_err_t open_store(nvs_open_mode_t mode, nvs_handle_t *handle)
{
    return nvs_open(OTA_NAMESPACE, mode, handle);
}

static void fill_identity(LumiaOtaSession *session)
{
    (void)esp_read_mac(session->bssid, ESP_MAC_WIFI_SOFTAP);
    snprintf(session->ssid,
             sizeof(session->ssid),
             "%s-%02X%02X",
             CONFIG_LUMIA_WIFI_AP_SSID_PREFIX,
             session->bssid[4],
             session->bssid[5]);
    session->timeout_seconds = CONFIG_LUMIA_OTA_SESSION_TIMEOUT_SECONDS;
}

esp_err_t lumia_ota_session_prepare(const uint8_t nonce[LUMIA_OTA_NONCE_LEN],
                                    LumiaOtaSession *session)
{
    nvs_handle_t handle;
    esp_err_t err;

    if (nonce == NULL || session == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    memset(session, 0, sizeof(*session));
    fill_identity(session);
    esp_fill_random(session->token, sizeof(session->token));

    err = open_store(NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        return err;
    }
    err = nvs_set_blob(handle, KEY_NONCE, nonce, LUMIA_OTA_NONCE_LEN);
    if (err == ESP_OK) {
        err = nvs_set_blob(handle, KEY_TOKEN, session->token,
                           sizeof(session->token));
    }
    if (err == ESP_OK) {
        err = nvs_set_u8(handle, KEY_PENDING, 1u);
    }
    if (err == ESP_OK) {
        err = nvs_commit(handle);
    }
    nvs_close(handle);
    return err;
}

esp_err_t lumia_ota_session_cancel_prepare(void)
{
    return lumia_ota_session_clear();
}

esp_err_t lumia_ota_session_take_boot(LumiaOtaSession *session,
                                      bool *requested)
{
    nvs_handle_t handle;
    uint8_t pending = 0u;
    size_t token_len = LUMIA_OTA_TOKEN_LEN;
    esp_err_t err;

    if (session == NULL || requested == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    *requested = false;
    memset(session, 0, sizeof(*session));
    fill_identity(session);

    err = open_store(NVS_READWRITE, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;
    }
    if (err != ESP_OK) {
        return err;
    }
    err = nvs_get_u8(handle, KEY_PENDING, &pending);
    if (err == ESP_ERR_NVS_NOT_FOUND || pending != 1u) {
        nvs_close(handle);
        return ESP_OK;
    }
    err = nvs_get_blob(handle, KEY_TOKEN, session->token, &token_len);
    if (err != ESP_OK || token_len != LUMIA_OTA_TOKEN_LEN) {
        (void)nvs_erase_all(handle);
        (void)nvs_commit(handle);
        nvs_close(handle);
        return err == ESP_OK ? ESP_ERR_INVALID_SIZE : err;
    }
    err = nvs_erase_key(handle, KEY_PENDING);
    if (err == ESP_OK || err == ESP_ERR_NVS_NOT_FOUND) {
        err = nvs_commit(handle);
    }
    nvs_close(handle);
    if (err == ESP_OK) {
        *requested = true;
    }
    return err;
}

esp_err_t lumia_ota_session_force_ble_next_boot(void)
{
    nvs_handle_t handle;
    esp_err_t err = open_store(NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        return err;
    }
    err = nvs_set_u8(handle, KEY_FORCE_BLE, 1u);
    if (err == ESP_OK) {
        err = nvs_commit(handle);
    }
    nvs_close(handle);
    return err;
}

esp_err_t lumia_ota_session_take_force_ble(bool *force_ble)
{
    nvs_handle_t handle;
    uint8_t value = 0u;
    esp_err_t err;

    if (force_ble == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    *force_ble = false;
    err = open_store(NVS_READWRITE, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;
    }
    if (err != ESP_OK) {
        return err;
    }
    err = nvs_get_u8(handle, KEY_FORCE_BLE, &value);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        nvs_close(handle);
        return ESP_OK;
    }
    if (err == ESP_OK) {
        (void)nvs_erase_key(handle, KEY_FORCE_BLE);
        err = nvs_commit(handle);
    }
    nvs_close(handle);
    if (err == ESP_OK) {
        *force_ble = value == 1u;
    }
    return err;
}

esp_err_t lumia_ota_session_clear(void)
{
    nvs_handle_t handle;
    esp_err_t err = open_store(NVS_READWRITE, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;
    }
    if (err != ESP_OK) {
        return err;
    }
    err = nvs_erase_key(handle, KEY_PENDING);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        err = ESP_OK;
    }
    if (err == ESP_OK) {
        (void)nvs_erase_key(handle, KEY_TOKEN);
        (void)nvs_erase_key(handle, KEY_NONCE);
        err = nvs_commit(handle);
    }
    nvs_close(handle);
    return err;
}
