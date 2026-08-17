#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "esp_err.h"
#include "esp_app_desc.h"
#include "esp_flash.h"
#include "esp_log.h"
#include "esp_ota_ops.h"
#include "esp_partition.h"
#include "esp_random.h"
#include "esp_sleep.h"
#include "esp_system.h"
#include "esp_timer.h"

#include "ble_transport.h"
#include "ble_status_led.h"
#include "config_store.h"
#include "effect_engine.h"
#include "effect_session.h"
#include "led_strip_driver.h"
#include "led_tdm.h"
#include "mode_button.h"
#include "modbus_server.h"
#include "modbus_crc.h"
#include "modbus_frame.h"
#include "ota_service.h"
#include "ota_session.h"
#include "register_map.h"
#include "runtime_state.h"
#include "serial_transport.h"
#include "sleep_switch.h"
#include "temp_monitor.h"
#include "web_server.h"
#include "wireless_mode.h"

#define APP_REQUEST_QUEUE_DEPTH  8u
#define APP_FRAME_PERIOD_MS      2u
#define APP_CONFIG_SAVE_DELAY_MS 500u
#define APP_CONFIG_RETRY_MS      2000u
#define APP_TEMP_SAMPLE_MS       1000u
#define APP_LED_DIAG_LOG_MS      5000u
#define APP_SLEEP_LED_SETTLE_MS  20u
#define APP_WIRELESS_RESTART_MS  600u
#define APP_OTA_RESTART_MS       800u
#define APP_WEB_QUEUE_DEPTH       4u
#define APP_VENDOR_FUNCTION       0x41u
#define APP_OTA_CMD_GET_INFO      0x01u
#define APP_OTA_CMD_PREPARE       0x02u
#define APP_OTA_CMD_CANCEL        0x03u
#define APP_OTA_CMD_BLE_BEGIN     0x10u
#define APP_OTA_CMD_BLE_DATA      0x11u
#define APP_OTA_CMD_BLE_STATUS    0x12u
#define APP_OTA_CMD_BLE_COMMIT    0x14u
#define APP_OTA_CMD_BLE_CANCEL    0x15u
#define APP_EFFECT_CMD_BEGIN       0x20u
#define APP_EFFECT_CMD_FRAME       0x21u
#define APP_EFFECT_CMD_HEARTBEAT   0x22u
#define APP_EFFECT_CMD_END         0x23u
#define APP_EFFECT_CMD_PIXEL_FRAME 0x24u
#define APP_EFFECT_PIXEL_FORMAT_RGB888 0x01u
#define APP_EFFECT_PIXEL_FRAME_VALUE_LEN \
    (1u + 4u + 2u + 1u + 1u + LUMIA_EFFECT_LED_COUNT * 3u)

static const char *TAG = "lumia_main";

typedef struct {
    uint8_t source;
    uint16_t len;
    uint8_t data[BLE_TRANSPORT_MAX_FRAME_LEN];
} AppRequest;

typedef enum {
    APP_REQUEST_SOURCE_BLE = 0,
    APP_REQUEST_SOURCE_USB_SERIAL,
} AppRequestSource;

typedef enum {
    APP_DIAG_RX_OVERFLOW = 0,
    APP_DIAG_PARSE_ERROR,
} AppDiagEvent;

static QueueHandle_t s_request_queue;
static QueueHandle_t s_diag_queue;
static QueueHandle_t s_web_request_queue;
static QueueHandle_t s_web_response_queue;
static SemaphoreHandle_t s_web_exchange_mutex;
static TaskHandle_t s_app_task_handle;
static esp_timer_handle_t s_tick_timer;
static LumiaEffectEngine s_effect_engine;
static uint32_t s_observed_config_revision;
static uint32_t s_config_save_deadline_ms;
static uint32_t s_last_temp_sample_ms;
static bool s_temp_monitor_available;
static LumiaWirelessMode s_wireless_mode;
static bool s_wireless_restart_pending;
static uint32_t s_wireless_restart_deadline_ms;
static uint32_t s_flash_size_bytes;
static uint32_t s_app_partition_size_bytes;
static uint32_t s_last_led_diag_log_ms;
static LumiaLedTdmDiagnostics s_logged_led_diagnostics;
static bool s_flash_layout_valid;
static bool s_ota_boot_mode;
static LumiaOtaSession s_ota_session;
static LumiaEffectSession s_effect_session;

static void app_build_persistent_effect_config(LumiaEffectConfig *effect_config);

static uint32_t app_now_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

static void app_probe_flash_layout(void)
{
    const esp_partition_t *app_partition = esp_ota_get_running_partition();
    esp_err_t err = esp_flash_get_size(NULL, &s_flash_size_bytes);

    s_flash_layout_valid = false;
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "physical flash size query failed: %s",
                 esp_err_to_name(err));
        return;
    }
    if (app_partition == NULL) {
        ESP_LOGE(TAG, "running application partition not found");
        return;
    }

    s_app_partition_size_bytes = app_partition->size;
    uint64_t partition_end = (uint64_t)app_partition->address +
                             (uint64_t)app_partition->size;
    s_flash_layout_valid = partition_end <= s_flash_size_bytes;
    ESP_LOGI(TAG,
             "flash layout: physical=%lu app_offset=0x%06lx app_size=%lu end=0x%06llx",
             (unsigned long)s_flash_size_bytes,
             (unsigned long)app_partition->address,
             (unsigned long)app_partition->size,
             (unsigned long long)partition_end);
    if (!s_flash_layout_valid) {
        ESP_LOGE(TAG,
                 "partition table exceeds physical flash; web service disabled");
    }
}

static void wake_app_task(void)
{
    if (s_app_task_handle != NULL) {
        xTaskNotifyGive(s_app_task_handle);
    }
}

static void app_tick_timer_callback(void *arg)
{
    (void)arg;
    wake_app_task();
}

static void on_transport_frame(const uint8_t *data, uint16_t len, void *user_ctx)
{
    AppRequest request;
    AppRequestSource source = (AppRequestSource)(uintptr_t)user_ctx;

    if (s_request_queue == NULL || data == NULL || len == 0u ||
        len > BLE_TRANSPORT_MAX_FRAME_LEN) {
        return;
    }

    request.source = (uint8_t)source;
    request.len = len;
    memcpy(request.data, data, len);
    if (xQueueSend(s_request_queue, &request, 0) != pdTRUE) {
        AppDiagEvent event = APP_DIAG_RX_OVERFLOW;
        (void)xQueueSend(s_diag_queue, &event, 0);
        ESP_LOGW(TAG, "request queue full, dropping frame");
        return;
    }
    wake_app_task();
}

static void on_ble_transport_diag(BleTransportDiagEvent event, void *user_ctx)
{
    (void)user_ctx;
    if (s_diag_queue != NULL) {
        AppDiagEvent diag_event = event == BLE_TRANSPORT_DIAG_RX_OVERFLOW
                                      ? APP_DIAG_RX_OVERFLOW
                                      : APP_DIAG_PARSE_ERROR;
        (void)xQueueSend(s_diag_queue, &diag_event, 0);
        wake_app_task();
    }
}

static void on_serial_transport_diag(SerialTransportDiagEvent event,
                                     void *user_ctx)
{
    (void)user_ctx;
    if (s_diag_queue != NULL) {
        AppDiagEvent diag_event = event == SERIAL_TRANSPORT_DIAG_RX_OVERFLOW
                                      ? APP_DIAG_RX_OVERFLOW
                                      : APP_DIAG_PARSE_ERROR;
        (void)xQueueSend(s_diag_queue, &diag_event, 0);
        wake_app_task();
    }
}

static void app_process_diag_event(AppDiagEvent event)
{
    if (event == APP_DIAG_RX_OVERFLOW) {
        runtime_state_note_rx_overflow();
    } else {
        runtime_state_note_parse_error();
    }
}

static bool vendor_append_tlv(uint8_t *payload,
                              uint8_t *payload_len,
                              uint8_t capacity,
                              uint8_t type,
                              const void *value,
                              uint8_t value_len)
{
    if (payload == NULL || payload_len == NULL || value == NULL ||
        (uint16_t)*payload_len + 2u + value_len > capacity) {
        return false;
    }
    payload[(*payload_len)++] = type;
    payload[(*payload_len)++] = value_len;
    memcpy(payload + *payload_len, value, value_len);
    *payload_len = (uint8_t)(*payload_len + value_len);
    return true;
}

static bool vendor_build_response(uint8_t address,
                                  const uint8_t *payload,
                                  uint8_t payload_len,
                                  uint8_t *response,
                                  uint16_t response_cap,
                                  uint16_t *response_len)
{
    if (response == NULL || response_len == NULL || payload == NULL ||
        (uint16_t)payload_len + 5u > response_cap) {
        return false;
    }
    response[0] = address;
    response[1] = APP_VENDOR_FUNCTION;
    response[2] = payload_len;
    memcpy(response + 3u, payload, payload_len);
    uint16_t crc = modbus_crc16(response, (uint16_t)(3u + payload_len));
    response[3u + payload_len] = (uint8_t)(crc & 0xFFu);
    response[4u + payload_len] = (uint8_t)(crc >> 8u);
    *response_len = (uint16_t)(5u + payload_len);
    return true;
}

static bool app_handle_ota_vendor_request(const AppRequest *request,
                                          uint8_t *response,
                                          uint16_t response_cap,
                                          uint16_t *response_len,
                                          bool *restart_after_send)
{
    uint8_t payload[BLE_TRANSPORT_MAX_FRAME_LEN - 5u];
    uint8_t payload_len = 0u;
    uint8_t command;
    esp_err_t err = ESP_OK;

    if (request == NULL || response == NULL || response_len == NULL ||
        restart_after_send == NULL || request->len < 6u ||
        request->data[1] != APP_VENDOR_FUNCTION) {
        return false;
    }
    *restart_after_send = false;
    if (request->source != APP_REQUEST_SOURCE_BLE ||
        request->data[0] != runtime_state_get_device_addr() ||
        !modbus_frame_crc_ok(request->data, request->len) ||
        request->len != (uint16_t)(5u + request->data[2]) ||
        request->data[2] < 1u) {
        command = request->data[2] >= 1u ? request->data[3] : 0u;
        payload[payload_len++] = command;
        payload[payload_len++] = 1u;
        return vendor_build_response(request->data[0], payload, payload_len,
                                     response, response_cap, response_len);
    }

    command = request->data[3];
    payload[payload_len++] = command;
    payload[payload_len++] = 0u;
    if (command == APP_OTA_CMD_GET_INFO) {
        const esp_app_desc_t *description = esp_app_get_description();
        uint8_t protocol = CONFIG_LUMIA_OTA_PROTOCOL_VERSION;
        uint8_t layout = CONFIG_LUMIA_OTA_LAYOUT_VERSION;
        uint8_t assets = CONFIG_LUMIA_OTA_ASSET_PACK_VERSION;
        uint8_t capabilities = 0x7Fu;
        uint32_t secure_version = description->secure_version;
        uint8_t version_len = (uint8_t)strnlen(description->version, 31u);
        (void)vendor_append_tlv(payload, &payload_len, sizeof(payload),
                                0x01u, &protocol, sizeof(protocol));
        (void)vendor_append_tlv(payload, &payload_len, sizeof(payload),
                                0x02u, &layout, sizeof(layout));
        (void)vendor_append_tlv(payload, &payload_len, sizeof(payload),
                                0x03u, CONFIG_LUMIA_OTA_WEB_VARIANT,
                                (uint8_t)strlen(CONFIG_LUMIA_OTA_WEB_VARIANT));
        (void)vendor_append_tlv(payload, &payload_len, sizeof(payload),
                                0x04u, &assets, sizeof(assets));
        (void)vendor_append_tlv(payload, &payload_len, sizeof(payload),
                                0x05u, &capabilities, sizeof(capabilities));
        (void)vendor_append_tlv(payload, &payload_len, sizeof(payload),
                                0x06u, &secure_version,
                                sizeof(secure_version));
        (void)vendor_append_tlv(payload, &payload_len, sizeof(payload),
                                0x07u, description->version, version_len);
    } else if (command == APP_OTA_CMD_PREPARE) {
        if (request->data[2] != 19u || request->data[4] != 0x01u ||
            request->data[5] != LUMIA_OTA_NONCE_LEN) {
            err = ESP_ERR_INVALID_ARG;
        } else {
            err = lumia_ota_session_prepare(request->data + 6u,
                                            &s_ota_session);
        }
        if (err == ESP_OK) {
            uint32_t timeout = s_ota_session.timeout_seconds;
            (void)vendor_append_tlv(
                payload, &payload_len, sizeof(payload), 0x10u,
                s_ota_session.ssid, (uint8_t)strlen(s_ota_session.ssid));
            (void)vendor_append_tlv(
                payload, &payload_len, sizeof(payload), 0x11u,
                s_ota_session.bssid, sizeof(s_ota_session.bssid));
            (void)vendor_append_tlv(
                payload, &payload_len, sizeof(payload), 0x12u,
                s_ota_session.token, sizeof(s_ota_session.token));
            (void)vendor_append_tlv(
                payload, &payload_len, sizeof(payload), 0x13u,
                &timeout, sizeof(timeout));
            *restart_after_send = true;
        }
    } else if (command == APP_OTA_CMD_CANCEL) {
        err = lumia_ota_session_cancel_prepare();
    } else if (command == APP_EFFECT_CMD_BEGIN) {
        LumiaEffectConfig persistent;
        uint32_t session_id;
        if (request->data[2] != 1u) {
            err = ESP_ERR_INVALID_ARG;
        } else {
            app_build_persistent_effect_config(&persistent);
            do {
                session_id = esp_random();
            } while (session_id == 0u);
            err = lumia_effect_session_begin(
                      &s_effect_session, session_id, app_now_ms(), &persistent) ==
                      LUMIA_EFFECT_SESSION_OK
                      ? ESP_OK
                      : ESP_ERR_INVALID_STATE;
        }
        if (err == ESP_OK) {
            (void)vendor_append_tlv(payload, &payload_len, sizeof(payload),
                                    0x30u, &session_id,
                                    sizeof(session_id));
        }
    } else if (command == APP_EFFECT_CMD_FRAME) {
        const uint8_t *cursor = request->data + 4u;
        LumiaGroupEffectConfig groups[LUMIA_EFFECT_GROUP_COUNT];
        uint32_t session_id;
        uint16_t sequence;
        if (request->data[2] != 49u) {
            err = ESP_ERR_INVALID_ARG;
        } else {
            session_id = (uint32_t)cursor[0] |
                         ((uint32_t)cursor[1] << 8u) |
                         ((uint32_t)cursor[2] << 16u) |
                         ((uint32_t)cursor[3] << 24u);
            sequence = (uint16_t)cursor[4] | ((uint16_t)cursor[5] << 8u);
            cursor += 6u;
            for (uint8_t group = 0u; group < LUMIA_EFFECT_GROUP_COUNT;
                 ++group, cursor += 6u) {
                groups[group].inner_mode = cursor[0];
                groups[group].hue =
                    (uint16_t)cursor[1] | ((uint16_t)cursor[2] << 8u);
                groups[group].saturation = cursor[3];
                groups[group].value = cursor[4];
                groups[group].inner_param = cursor[5];
            }
            err = lumia_effect_session_frame(
                      &s_effect_session, session_id, sequence, app_now_ms(),
                      groups) == LUMIA_EFFECT_SESSION_OK
                      ? ESP_OK
                      : ESP_ERR_INVALID_STATE;
        }
        if (err == ESP_OK) {
            (void)vendor_append_tlv(payload, &payload_len, sizeof(payload),
                                    0x31u, &sequence, sizeof(sequence));
        }
    } else if (command == APP_EFFECT_CMD_PIXEL_FRAME) {
        const uint8_t *cursor = request->data + 4u;
        LumiaRgb pixels[LUMIA_EFFECT_LED_COUNT];
        uint32_t session_id;
        uint16_t sequence;
        if (request->data[2] != APP_EFFECT_PIXEL_FRAME_VALUE_LEN ||
            cursor[6] != APP_EFFECT_PIXEL_FORMAT_RGB888 ||
            cursor[7] != LUMIA_EFFECT_LED_COUNT) {
            err = ESP_ERR_INVALID_ARG;
        } else {
            session_id = (uint32_t)cursor[0] |
                         ((uint32_t)cursor[1] << 8u) |
                         ((uint32_t)cursor[2] << 16u) |
                         ((uint32_t)cursor[3] << 24u);
            sequence = (uint16_t)cursor[4] | ((uint16_t)cursor[5] << 8u);
            cursor += 8u;
            for (uint8_t index = 0u; index < LUMIA_EFFECT_LED_COUNT;
                 ++index, cursor += 3u) {
                pixels[index].r = cursor[0];
                pixels[index].g = cursor[1];
                pixels[index].b = cursor[2];
            }
            err = lumia_effect_session_pixel_frame(
                      &s_effect_session, session_id, sequence, app_now_ms(),
                      pixels) == LUMIA_EFFECT_SESSION_OK
                      ? ESP_OK
                      : ESP_ERR_INVALID_STATE;
        }
        if (err == ESP_OK) {
            (void)vendor_append_tlv(payload, &payload_len, sizeof(payload),
                                    0x31u, &sequence, sizeof(sequence));
        }
    } else if (command == APP_EFFECT_CMD_HEARTBEAT ||
               command == APP_EFFECT_CMD_END) {
        uint32_t session_id = 0u;
        if (request->data[2] != 5u) {
            err = ESP_ERR_INVALID_ARG;
        } else {
            session_id = (uint32_t)request->data[4] |
                         ((uint32_t)request->data[5] << 8u) |
                         ((uint32_t)request->data[6] << 16u) |
                         ((uint32_t)request->data[7] << 24u);
            LumiaEffectSessionStatus status =
                command == APP_EFFECT_CMD_HEARTBEAT
                    ? lumia_effect_session_heartbeat(
                          &s_effect_session, session_id, app_now_ms())
                    : lumia_effect_session_end(&s_effect_session, session_id);
            err = status == LUMIA_EFFECT_SESSION_OK
                      ? ESP_OK
                      : ESP_ERR_INVALID_STATE;
        }
    } else if (command == APP_OTA_CMD_BLE_BEGIN) {
        lumia_effect_session_cancel(&s_effect_session);
        if (request->data[2] != 38u ||
            request->data[8] != CONFIG_LUMIA_OTA_LAYOUT_VERSION) {
            err = ESP_ERR_INVALID_ARG;
        } else {
            uint32_t expected_bytes =
                (uint32_t)request->data[4] |
                ((uint32_t)request->data[5] << 8u) |
                ((uint32_t)request->data[6] << 16u) |
                ((uint32_t)request->data[7] << 24u);
            err = lumia_ota_service_begin(expected_bytes,
                                          request->data + 9u);
        }
    } else if (command == APP_OTA_CMD_BLE_DATA) {
        if (request->data[2] < 6u) {
            err = ESP_ERR_INVALID_ARG;
        } else {
            uint32_t offset =
                (uint32_t)request->data[4] |
                ((uint32_t)request->data[5] << 8u) |
                ((uint32_t)request->data[6] << 16u) |
                ((uint32_t)request->data[7] << 24u);
            uint32_t next_offset = 0u;
            err = lumia_ota_service_write(
                offset, request->data + 8u,
                (size_t)request->data[2] - 5u, &next_offset);
            if (err == ESP_OK) {
                (void)vendor_append_tlv(payload, &payload_len,
                                        sizeof(payload), 0x20u,
                                        &next_offset,
                                        sizeof(next_offset));
            }
        }
    } else if (command == APP_OTA_CMD_BLE_STATUS) {
        LumiaOtaStatus status;
        lumia_ota_service_get_status(&status);
        uint8_t state = (uint8_t)status.state;
        int32_t error = (int32_t)status.error;
        (void)vendor_append_tlv(payload, &payload_len, sizeof(payload),
                                0x21u, &state, sizeof(state));
        (void)vendor_append_tlv(payload, &payload_len, sizeof(payload),
                                0x22u, &status.received_bytes,
                                sizeof(status.received_bytes));
        (void)vendor_append_tlv(payload, &payload_len, sizeof(payload),
                                0x23u, &status.expected_bytes,
                                sizeof(status.expected_bytes));
        (void)vendor_append_tlv(payload, &payload_len, sizeof(payload),
                                0x24u, &error, sizeof(error));
    } else if (command == APP_OTA_CMD_BLE_COMMIT) {
        err = lumia_ota_service_commit();
        if (err == ESP_OK) {
            *restart_after_send = true;
        }
    } else if (command == APP_OTA_CMD_BLE_CANCEL) {
        err = lumia_ota_service_cancel();
    } else {
        err = ESP_ERR_NOT_SUPPORTED;
    }

    if (err != ESP_OK) {
        payload[1] = 1u;
        payload_len = 2u;
    }
    return vendor_build_response(request->data[0], payload, payload_len,
                                 response, response_cap, response_len);
}

static void app_process_request(const AppRequest *request)
{
    uint8_t response[MODBUS_SERVER_MAX_RESPONSE_LEN];
    uint16_t response_len = 0u;
    esp_err_t err;

    runtime_state_note_rx_request();
    if (request->data[1] == APP_VENDOR_FUNCTION) {
        if (request->source != APP_REQUEST_SOURCE_BLE) {
            runtime_state_note_parse_error();
            return;
        }
        bool restart_after_send = false;
        if (!app_handle_ota_vendor_request(
                request, response, sizeof(response), &response_len,
                &restart_after_send)) {
            runtime_state_note_parse_error();
            return;
        }
        err = lumia_ble_transport_notify(response, response_len);
        if (err != ESP_OK) {
            (void)lumia_ota_session_cancel_prepare();
            runtime_state_note_tx_drop();
            return;
        }
        if (restart_after_send) {
            (void)lumia_status_led_set_pattern(
                LUMIA_STATUS_LED_SWITCHING, app_now_ms());
            s_wireless_restart_deadline_ms =
                app_now_ms() + APP_OTA_RESTART_MS;
            s_wireless_restart_pending = true;
        }
        return;
    }
    lumia_effect_session_cancel(&s_effect_session);
    switch (modbus_server_handle_request(request->data,
                                         request->len,
                                         response,
                                         sizeof(response),
                                         &response_len)) {
        case MODBUS_SERVER_OK:
            if (response_len > 0u) {
                if (request->source == APP_REQUEST_SOURCE_BLE) {
                    err = lumia_ble_transport_notify(response, response_len);
                } else {
                    err = lumia_serial_transport_send(response, response_len);
                }
                if (err != ESP_OK) {
                    runtime_state_note_tx_drop();
                    ESP_LOGW(TAG, "transport send failed: %s", esp_err_to_name(err));
                }
            }
            break;
        case MODBUS_SERVER_NO_RESPONSE:
            break;
        case MODBUS_SERVER_CRC_ERROR:
            runtime_state_note_parse_error();
            ESP_LOGW(TAG, "CRC error on request");
            break;
        case MODBUS_SERVER_BAD_REQUEST:
        default:
            runtime_state_note_parse_error();
            ESP_LOGW(TAG, "bad Modbus request");
            break;
    }
}

static RegisterMapStatus app_write_group_registers(
    uint16_t start_reg,
    const LumiaGroupInnerConfig *groups,
    uint8_t group_count)
{
    uint16_t values[LUMIA_GROUP_COUNT * LUMIA_REG_GROUP_STRIDE];
    uint16_t value_index = 0u;

    for (uint8_t group = 0u; group < group_count; ++group) {
        values[value_index++] = groups[group].inner_mode;
        values[value_index++] = groups[group].hue;
        values[value_index++] = groups[group].sat;
        values[value_index++] = groups[group].val;
        values[value_index++] = groups[group].inner_param;
    }
    return register_map_write_multiple(start_reg, value_index, values);
}

static void app_process_web_request(const LumiaWebControlRequest *request)
{
    LumiaLedTdmDiagnostics led_diagnostics = {0};
    LumiaWebControlResponse response = {
        .id = request->id,
        .status = REGISTER_MAP_OK,
        .flash_size_bytes = s_flash_size_bytes,
        .app_partition_size_bytes = s_app_partition_size_bytes,
    };
    uint16_t values[4];

    if (request->type != LUMIA_WEB_CONTROL_READ_STATE) {
        lumia_effect_session_cancel(&s_effect_session);
    }
    switch (request->type) {
        case LUMIA_WEB_CONTROL_READ_STATE:
            break;
        case LUMIA_WEB_CONTROL_WRITE_SCENE:
            values[0] = request->global.scene_mode;
            values[1] = request->global.scene_param;
            response.status = register_map_write_multiple(
                LUMIA_REG_SCENE_MODE, 2u, values);
            break;
        case LUMIA_WEB_CONTROL_WRITE_GLOBAL:
            values[0] = request->global.global_brightness;
            values[1] = request->global.gain_r;
            values[2] = request->global.gain_g;
            values[3] = request->global.gain_b;
            response.status = register_map_write_multiple(
                LUMIA_REG_LED_GLOBAL_BRI, 4u, values);
            break;
        case LUMIA_WEB_CONTROL_WRITE_GROUP:
            if (request->group_index >= LUMIA_GROUP_COUNT) {
                response.status = REGISTER_MAP_ILLEGAL_ADDR;
            } else {
                response.status = app_write_group_registers(
                    (uint16_t)(LUMIA_REG_GROUP_BASE +
                               request->group_index * LUMIA_REG_GROUP_STRIDE),
                    request->groups,
                    1u);
            }
            break;
        case LUMIA_WEB_CONTROL_WRITE_ALL_GROUPS:
            response.status = app_write_group_registers(
                LUMIA_REG_GROUP_BASE,
                request->groups,
                LUMIA_GROUP_COUNT);
            break;
        case LUMIA_WEB_CONTROL_CLEAR_DIAGNOSTICS:
            response.status = register_map_write_single(
                LUMIA_REG_UART_PARSE_ERROR, LUMIA_DIAG_CLEAR_KEY);
            if (response.status == REGISTER_MAP_OK) {
                lumia_led_tdm_clear_diagnostics();
            }
            break;
        default:
            response.status = REGISTER_MAP_ILLEGAL_ADDR;
            break;
    }

    lumia_led_tdm_get_diagnostics(&led_diagnostics);
    response.led_tx_error_count = led_diagnostics.tx_error_count;
    response.led_gpio_switch_error_count =
        led_diagnostics.gpio_switch_error_count;
    response.led_init_error_count = led_diagnostics.init_error_count;
    response.led_max_scan_gap_us = led_diagnostics.max_scan_gap_us;
    response.state = *runtime_state_get();
    if (xQueueSend(s_web_response_queue, &response, 0) != pdTRUE) {
        runtime_state_note_tx_drop();
        ESP_LOGW(TAG, "web response queue full, dropping response %lu",
                 (unsigned long)response.id);
    }
}

static esp_err_t app_web_exchange(const LumiaWebControlRequest *request,
                                  LumiaWebControlResponse *response,
                                  uint32_t timeout_ms,
                                  void *user_ctx)
{
    LumiaWebControlResponse candidate;
    TickType_t started;
    TickType_t timeout_ticks = pdMS_TO_TICKS(timeout_ms);
    (void)user_ctx;

    if (request == NULL || response == NULL || timeout_ms == 0u ||
        s_web_exchange_mutex == NULL || s_web_request_queue == NULL ||
        s_web_response_queue == NULL) {
        return ESP_ERR_INVALID_STATE;
    }
    started = xTaskGetTickCount();
    if (xSemaphoreTake(s_web_exchange_mutex, timeout_ticks) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }

    TickType_t elapsed = (TickType_t)(xTaskGetTickCount() - started);
    if (elapsed >= timeout_ticks) {
        xSemaphoreGive(s_web_exchange_mutex);
        return ESP_ERR_TIMEOUT;
    }

    while (xQueueReceive(s_web_response_queue, &candidate, 0) == pdTRUE) {
    }
    if (xQueueSend(s_web_request_queue, request, 0) != pdTRUE) {
        xSemaphoreGive(s_web_exchange_mutex);
        return ESP_ERR_TIMEOUT;
    }
    wake_app_task();

    while ((TickType_t)(xTaskGetTickCount() - started) < timeout_ticks) {
        elapsed = (TickType_t)(xTaskGetTickCount() - started);
        TickType_t remaining = timeout_ticks - elapsed;
        if (xQueueReceive(s_web_response_queue, &candidate, remaining) != pdTRUE) {
            break;
        }
        if (candidate.id == request->id) {
            *response = candidate;
            xSemaphoreGive(s_web_exchange_mutex);
            return ESP_OK;
        }
    }

    xSemaphoreGive(s_web_exchange_mutex);
    return ESP_ERR_TIMEOUT;
}

static void app_build_persistent_effect_config(LumiaEffectConfig *effect_config)
{
    const RuntimeState *state = runtime_state_get();
    uint8_t group;

    effect_config->scene_mode = state->cfg.scene_mode;
    effect_config->scene_param = state->cfg.scene_param;
    effect_config->global_brightness = state->cfg.led_global_bri;
    effect_config->white_balance_r = state->cfg.led_gain_r;
    effect_config->white_balance_g = state->cfg.led_gain_g;
    effect_config->white_balance_b = state->cfg.led_gain_b;
    for (group = 0u; group < LUMIA_GROUP_COUNT; ++group) {
        effect_config->groups[group].inner_mode =
            state->cfg.groups[group].inner_mode;
        effect_config->groups[group].hue = state->cfg.groups[group].hue;
        effect_config->groups[group].saturation = state->cfg.groups[group].sat;
        effect_config->groups[group].value = state->cfg.groups[group].val;
        effect_config->groups[group].inner_param =
            state->cfg.groups[group].inner_param;
    }
}

static void app_render_frame(void)
{
    LumiaEffectConfig effect_config;
    const LumiaRgb *override_pixels =
        lumia_effect_session_pixels(&s_effect_session);
    const LumiaEffectConfig *base_config =
        lumia_effect_session_base_config(&s_effect_session);
    const LumiaEffectConfig *override_config =
        lumia_effect_session_config(&s_effect_session);
    RgbFrame frame;

    if (override_pixels != NULL && base_config != NULL) {
        for (uint8_t index = 0u; index < LUMIA_EFFECT_LED_COUNT; ++index) {
            frame.pixels[index] = lumia_effect_apply_color_correction(
                override_pixels[index], base_config);
        }
    } else if (override_config != NULL) {
        effect_config = *override_config;
    } else {
        app_build_persistent_effect_config(&effect_config);
    }
    if (override_pixels == NULL &&
        !lumia_effect_engine_tick_frame(&s_effect_engine,
                                        &effect_config, &frame)) {
        ESP_LOGW(TAG, "effect render rejected by active group configuration");
        return;
    }
    esp_err_t err = lumia_led_strip_write(
        (const uint8_t (*)[LUMIA_LED_STRIP_RGB_COMPONENTS])frame.pixels);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "LED refresh failed: %s", esp_err_to_name(err));
    }
}

static void app_config_save_scheduler_init(uint32_t now_ms)
{
    const RuntimeState *state = runtime_state_get();

    s_observed_config_revision = state->config_revision;
    s_config_save_deadline_ms = now_ms + APP_CONFIG_SAVE_DELAY_MS;
}

static void app_service_config_store(uint32_t now_ms)
{
    RuntimeState *state = runtime_state_get();

    if (state->config_revision != s_observed_config_revision) {
        s_observed_config_revision = state->config_revision;
        s_config_save_deadline_ms = now_ms + APP_CONFIG_SAVE_DELAY_MS;
        runtime_state_set_save_state(1u);
    }
    if (!state->cfg_dirty ||
        (int32_t)(now_ms - s_config_save_deadline_ms) < 0) {
        return;
    }

    PersistentConfig snapshot = state->cfg;
    uint32_t saved_revision = state->config_revision;
    runtime_state_set_save_state(2u);

    esp_err_t err = config_store_save(&snapshot);
    if (err == ESP_OK) {
        runtime_state_mark_config_saved(saved_revision);
        ESP_LOGI(TAG,
                 "configuration saved: slot=%d seq=%lu",
                 config_store_active_slot(),
                 (unsigned long)config_store_active_sequence());
        if (state->cfg_dirty) {
            s_config_save_deadline_ms = now_ms + APP_CONFIG_SAVE_DELAY_MS;
        }
        return;
    }

    runtime_state_set_save_state(3u);
    s_config_save_deadline_ms = now_ms + APP_CONFIG_RETRY_MS;
    ESP_LOGE(TAG, "configuration save failed: %s", esp_err_to_name(err));
}

static void app_service_temp_monitor(uint32_t now_ms)
{
    int16_t temp_c_x100;
    uint16_t vdda_mv;

    if (!s_temp_monitor_available ||
        (uint32_t)(now_ms - s_last_temp_sample_ms) < APP_TEMP_SAMPLE_MS) {
        return;
    }
    s_last_temp_sample_ms = now_ms;
    esp_err_t err = temp_monitor_sample(&temp_c_x100, &vdda_mv);
    if (err == ESP_OK) {
        runtime_state_set_telemetry(temp_c_x100, vdda_mv);
    } else {
        ESP_LOGW(TAG, "temperature sample failed: %s", esp_err_to_name(err));
    }
}

static void app_service_led_diagnostics(uint32_t now_ms)
{
    LumiaLedTdmDiagnostics diagnostics;

    if ((uint32_t)(now_ms - s_last_led_diag_log_ms) < APP_LED_DIAG_LOG_MS) {
        return;
    }
    s_last_led_diag_log_ms = now_ms;
    lumia_led_tdm_get_diagnostics(&diagnostics);
    if (diagnostics.tx_error_count == s_logged_led_diagnostics.tx_error_count &&
        diagnostics.gpio_switch_error_count ==
            s_logged_led_diagnostics.gpio_switch_error_count &&
        diagnostics.init_error_count ==
            s_logged_led_diagnostics.init_error_count) {
        return;
    }
    s_logged_led_diagnostics = diagnostics;
    if (diagnostics.tx_error_count == 0u &&
        diagnostics.gpio_switch_error_count == 0u &&
        diagnostics.init_error_count == 0u) {
        return;
    }
    ESP_LOGW(TAG,
             "LED diagnostics: tx=%lu gpio=%lu init=%lu max_gap=%lu us",
             (unsigned long)diagnostics.tx_error_count,
             (unsigned long)diagnostics.gpio_switch_error_count,
             (unsigned long)diagnostics.init_error_count,
             (unsigned long)diagnostics.max_scan_gap_us);
}

static uint8_t app_next_scene_mode(uint8_t current_mode)
{
    switch (current_mode) {
        case LUMIA_SCENE_MODE_STATIC:
            return LUMIA_SCENE_MODE_CHASE_LR;
        case LUMIA_SCENE_MODE_CHASE_LR:
            return LUMIA_SCENE_MODE_CHASE_RL;
        case LUMIA_SCENE_MODE_CHASE_RL:
            return LUMIA_SCENE_MODE_PINGPONG;
        case LUMIA_SCENE_MODE_PINGPONG:
        default:
            return LUMIA_SCENE_MODE_STATIC;
    }
}

static void app_service_mode_button(uint32_t now_ms)
{
    const RuntimeState *state = runtime_state_get();
    if (s_ota_boot_mode) {
        return;
    }
    LumiaModeButtonEvent event = LUMIA_MODE_BUTTON_EVENT_NONE;
    esp_err_t err = lumia_mode_button_service(now_ms, &event);

    if (err != ESP_OK) {
        ESP_LOGE(TAG, "mode button service failed: %s", esp_err_to_name(err));
        return;
    }
    if (event == LUMIA_MODE_BUTTON_EVENT_NONE) {
        return;
    }
    lumia_effect_session_cancel(&s_effect_session);

    if (event == LUMIA_MODE_BUTTON_EVENT_LONG_PRESS) {
        LumiaWirelessMode next_mode =
            s_wireless_mode == LUMIA_WIRELESS_MODE_BLE
                ? LUMIA_WIRELESS_MODE_WIFI
                : LUMIA_WIRELESS_MODE_BLE;
        err = lumia_wireless_mode_save(next_mode);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "wireless mode save failed: %s", esp_err_to_name(err));
            return;
        }
        ESP_LOGI(TAG,
                 "wireless mode switching: %s -> %s",
                 lumia_wireless_mode_name(s_wireless_mode),
                 lumia_wireless_mode_name(next_mode));
        (void)lumia_status_led_set_pattern(LUMIA_STATUS_LED_SWITCHING, now_ms);
        s_wireless_restart_deadline_ms = now_ms + APP_WIRELESS_RESTART_MS;
        s_wireless_restart_pending = true;
        return;
    }

    uint8_t next_mode = app_next_scene_mode(state->cfg.scene_mode);
    if (register_map_write_single(LUMIA_REG_SCENE_MODE, next_mode) !=
        REGISTER_MAP_OK) {
        ESP_LOGE(TAG, "mode button failed to switch scene mode");
        return;
    }

    ESP_LOGI(TAG, "mode button switched scene mode to %u", next_mode);
}

static void app_service_wireless_restart(uint32_t now_ms)
{
    if (s_wireless_restart_pending &&
        (int32_t)(now_ms - s_wireless_restart_deadline_ms) >= 0) {
        ESP_LOGI(TAG, "restarting into selected wireless mode");
        esp_restart();
    }
}

static void app_enter_deep_sleep(void)
{
    lumia_effect_session_cancel(&s_effect_session);
    esp_err_t err = lumia_led_strip_clear();

    if (err != ESP_OK) {
        ESP_LOGE(TAG, "LED clear before sleep failed: %s", esp_err_to_name(err));
    }
    vTaskDelay(pdMS_TO_TICKS(APP_SLEEP_LED_SETTLE_MS));

    err = lumia_sleep_switch_prepare_high_wakeup();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "sleep wakeup config failed: %s", esp_err_to_name(err));
        return;
    }

    ESP_LOGI(TAG, "entering deep sleep, wake on GPIO4 high");
    esp_deep_sleep_start();
}

static void app_service_sleep_switch(uint32_t now_ms)
{
    bool sleep_requested = false;
    esp_err_t err = lumia_sleep_switch_service(now_ms, &sleep_requested);

    if (err != ESP_OK) {
        ESP_LOGE(TAG, "sleep switch service failed: %s", esp_err_to_name(err));
        return;
    }
    if (!sleep_requested) {
        return;
    }

    app_enter_deep_sleep();
}

static void app_task(void *arg)
{
    AppRequest request;
    AppDiagEvent diag_event;
    LumiaWebControlRequest web_request;
    uint32_t last_tick_ms = app_now_ms();
    uint32_t last_frame_ms = last_tick_ms;
    (void)arg;

    while (1) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);

        while (xQueueReceive(s_diag_queue, &diag_event, 0) == pdTRUE) {
            app_process_diag_event(diag_event);
        }
        while (xQueueReceive(s_request_queue, &request, 0) == pdTRUE) {
            app_process_request(&request);
        }
        while (xQueueReceive(s_web_request_queue, &web_request, 0) == pdTRUE) {
            app_process_web_request(&web_request);
        }

        uint32_t now_ms = app_now_ms();
        if (lumia_effect_session_service_timeout(&s_effect_session, now_ms)) {
            ESP_LOGI(TAG, "volatile effect session expired");
        }
        while ((int32_t)(now_ms - last_tick_ms) > 0) {
            last_tick_ms++;
            lumia_effect_engine_tick_1ms(&s_effect_engine);
        }

        app_service_mode_button(now_ms);
        app_service_sleep_switch(now_ms);
        (void)lumia_status_led_service(now_ms);
        app_service_wireless_restart(now_ms);

        if (!lumia_ota_service_is_receiving() &&
            (uint32_t)(now_ms - last_frame_ms) >= APP_FRAME_PERIOD_MS) {
            last_frame_ms = now_ms;
            app_render_frame();
        }
        app_service_config_store(now_ms);
        app_service_temp_monitor(now_ms);
        app_service_led_diagnostics(now_ms);
    }
}

static void app_ota_activity_changed(bool receiving, void *user_ctx)
{
    (void)user_ctx;
    lumia_led_strip_set_paused(receiving);
}

static void app_confirm_running_image(void)
{
    const esp_partition_t *running = esp_ota_get_running_partition();
    esp_ota_img_states_t state;
    if (running != NULL &&
        esp_ota_get_state_partition(running, &state) == ESP_OK &&
        state == ESP_OTA_IMG_PENDING_VERIFY) {
        esp_err_t err = esp_ota_mark_app_valid_cancel_rollback();
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "failed to confirm OTA image: %s",
                     esp_err_to_name(err));
        } else {
            ESP_LOGI(TAG, "OTA image confirmed");
        }
    }
}

void app_main(void)
{
    const esp_timer_create_args_t tick_timer_args = {
        .callback = app_tick_timer_callback,
        .arg = NULL,
        .dispatch_method = ESP_TIMER_TASK,
        .name = "lumia_tick",
        .skip_unhandled_events = true,
    };
    BleTransportConfig ble_config = {
        .on_frame = on_transport_frame,
        .on_diag = on_ble_transport_diag,
        .user_ctx = (void *)(uintptr_t)APP_REQUEST_SOURCE_BLE,
    };
    SerialTransportConfig serial_config = {
        .on_frame = on_transport_frame,
        .on_diag = on_serial_transport_diag,
        .user_ctx = (void *)(uintptr_t)APP_REQUEST_SOURCE_USB_SERIAL,
    };
    PersistentConfig stored_config;
    bool config_found = false;
    bool startup_sleep_requested = false;
    bool force_ble_once = false;
    esp_err_t err;

    ESP_LOGI(TAG, "Lumia ESP32-C3 runtime booting");

    app_probe_flash_layout();

    ESP_ERROR_CHECK(lumia_wireless_mode_store_init());
    ESP_ERROR_CHECK(lumia_ota_session_take_boot(&s_ota_session,
                                                &s_ota_boot_mode));
    ESP_ERROR_CHECK(lumia_ota_session_take_force_ble(&force_ble_once));
    ESP_ERROR_CHECK(lumia_wireless_mode_load(&s_wireless_mode));
    if (force_ble_once) {
        s_wireless_mode = LUMIA_WIRELESS_MODE_BLE;
    }
    ESP_LOGI(TAG, "wireless mode: %s", lumia_wireless_mode_name(s_wireless_mode));

    runtime_state_init();
    ESP_ERROR_CHECK(config_store_init());
    err = config_store_load(&stored_config, &config_found);
    ESP_ERROR_CHECK(err);
    if (config_found) {
        runtime_state_restore_config(&stored_config);
        ESP_LOGI(TAG,
                 "configuration loaded: slot=%d seq=%lu addr=%u",
                 config_store_active_slot(),
                 (unsigned long)config_store_active_sequence(),
                 stored_config.device_addr);
    } else {
        runtime_state_mark_config_changed();
        ESP_LOGW(TAG, "no valid configuration; defaults will be saved");
    }

    register_map_init();
    modbus_server_init();
    lumia_effect_engine_init(&s_effect_engine);
    lumia_effect_session_init(&s_effect_session);
    app_config_save_scheduler_init(app_now_ms());

    s_request_queue = xQueueCreate(APP_REQUEST_QUEUE_DEPTH, sizeof(AppRequest));
    ESP_ERROR_CHECK(s_request_queue != NULL ? ESP_OK : ESP_ERR_NO_MEM);
    s_diag_queue = xQueueCreate(16u, sizeof(AppDiagEvent));
    ESP_ERROR_CHECK(s_diag_queue != NULL ? ESP_OK : ESP_ERR_NO_MEM);
    s_web_request_queue = xQueueCreate(APP_WEB_QUEUE_DEPTH,
                                       sizeof(LumiaWebControlRequest));
    ESP_ERROR_CHECK(s_web_request_queue != NULL ? ESP_OK : ESP_ERR_NO_MEM);
    s_web_response_queue = xQueueCreate(APP_WEB_QUEUE_DEPTH,
                                        sizeof(LumiaWebControlResponse));
    ESP_ERROR_CHECK(s_web_response_queue != NULL ? ESP_OK : ESP_ERR_NO_MEM);
    s_web_exchange_mutex = xSemaphoreCreateMutex();
    ESP_ERROR_CHECK(s_web_exchange_mutex != NULL ? ESP_OK : ESP_ERR_NO_MEM);
    ESP_ERROR_CHECK(lumia_led_strip_init());
    ESP_ERROR_CHECK(lumia_ble_status_led_init());
    ESP_ERROR_CHECK(lumia_mode_button_init(app_now_ms()));
    ESP_ERROR_CHECK(lumia_sleep_switch_init(app_now_ms(),
                                            &startup_sleep_requested));
    if (startup_sleep_requested) {
        ESP_LOGI(TAG, "sleep switch is off at boot; skipping wireless startup");
        app_enter_deep_sleep();
    }
    err = temp_monitor_init();
    s_temp_monitor_available = err == ESP_OK;
    s_last_temp_sample_ms = app_now_ms() - APP_TEMP_SAMPLE_MS;
    if (!s_temp_monitor_available) {
        ESP_LOGW(TAG,
                 "internal temperature sensor unavailable: %s",
                 esp_err_to_name(err));
    }

    BaseType_t task_created = xTaskCreate(app_task,
                                          "app_task",
                                          4096u,
                                          NULL,
                                          5u,
                                          &s_app_task_handle);
    ESP_ERROR_CHECK(task_created == pdPASS ? ESP_OK : ESP_ERR_NO_MEM);

    ESP_ERROR_CHECK(esp_timer_create(&tick_timer_args, &s_tick_timer));
    ESP_ERROR_CHECK(esp_timer_start_periodic(s_tick_timer, 1000u));

    ESP_ERROR_CHECK(lumia_serial_transport_init(&serial_config));
    if (s_ota_boot_mode) {
        const LumiaOtaServiceConfig ota_config = {
            .session = s_ota_session,
            .secure_version = esp_app_get_description()->secure_version,
            .session_timeout_enabled = true,
            .on_activity = app_ota_activity_changed,
            .user_ctx = NULL,
        };
        (void)lumia_status_led_set_pattern(LUMIA_STATUS_LED_OTA,
                                           app_now_ms());
        ESP_ERROR_CHECK(lumia_ota_service_start(&ota_config));
        ESP_ERROR_CHECK(lumia_web_server_start_ota());
    } else if (s_wireless_mode == LUMIA_WIRELESS_MODE_BLE) {
        const LumiaOtaServiceConfig ota_config = {
            .secure_version = esp_app_get_description()->secure_version,
            .session_timeout_enabled = false,
            .on_activity = app_ota_activity_changed,
            .user_ctx = NULL,
        };
        ESP_ERROR_CHECK(lumia_ota_service_start(&ota_config));
        ESP_ERROR_CHECK(lumia_ble_transport_init(&ble_config));
    } else {
        const LumiaWebServerConfig web_config = {
            .exchange = app_web_exchange,
            .user_ctx = NULL,
        };
        (void)lumia_status_led_set_pattern(LUMIA_STATUS_LED_WIFI_BLINK,
                                           app_now_ms());
        if (s_flash_layout_valid) {
            ESP_ERROR_CHECK(lumia_web_server_start(&web_config));
        } else {
            ESP_LOGE(TAG,
                     "WiFi mode running without HTTP because flash layout is invalid");
        }
    }

    ESP_LOGI(TAG,
             "startup resources: heap_free=%lu heap_min=%lu app_stack_hwm=%lu",
             (unsigned long)esp_get_free_heap_size(),
             (unsigned long)esp_get_minimum_free_heap_size(),
             (unsigned long)uxTaskGetStackHighWaterMark(s_app_task_handle));
    if (!s_ota_boot_mode) {
        app_confirm_running_image();
    }
}
