#include "ble_transport.h"

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "ble_status_led.h"
#include "esp_bt.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "sdkconfig.h"
#include "host/ble_gatt.h"
#include "host/ble_hs.h"
#include "host/ble_hs_mbuf.h"
#include "host/ble_uuid.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#include "modbus_frame.h"

#ifndef CONFIG_LUMIA_BLE_DEVICE_NAME
#define CONFIG_LUMIA_BLE_DEVICE_NAME "Lumia-ESP32"
#endif

#ifndef CONFIG_LUMIA_WIFI_AP_SSID_PREFIX
#define CONFIG_LUMIA_WIFI_AP_SSID_PREFIX CONFIG_LUMIA_BLE_DEVICE_NAME
#endif

#define LUMIA_BLE_TX_POWER_DBM   6
#define LUMIA_BLE_TX_POWER_LEVEL ESP_PWR_LVL_P6

static const char *TAG = "ble_transport";

static uint16_t s_tx_value_handle;
static uint16_t s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
static bool s_notify_enabled;
static uint8_t s_own_addr_type;
static BleTransportConfig s_config;
static uint8_t s_rx_buffer[BLE_TRANSPORT_RX_BUFFER_CAP];
static uint16_t s_rx_buffer_len;
static char s_device_name[33];

static const ble_uuid16_t s_service_uuid = BLE_UUID16_INIT(LUMIA_BLE_SERVICE_UUID16);
static const ble_uuid16_t s_rx_uuid = BLE_UUID16_INIT(LUMIA_BLE_RX_UUID16);
static const ble_uuid16_t s_tx_uuid = BLE_UUID16_INIT(LUMIA_BLE_TX_UUID16);

void ble_store_config_init(void);

static void ble_transport_advertise(void);

static bool ble_transport_set_power(esp_ble_power_type_t power_type,
                                    const char *stage)
{
    esp_power_level_t applied_power;
    esp_err_t err = esp_ble_tx_power_set(power_type, LUMIA_BLE_TX_POWER_LEVEL);

    if (err != ESP_OK) {
        ESP_LOGE(TAG,
                 "set BLE %s TX power to %d dBm failed: %s",
                 stage,
                 LUMIA_BLE_TX_POWER_DBM,
                 esp_err_to_name(err));
        return false;
    }

    applied_power = esp_ble_tx_power_get(power_type);
    if (applied_power != LUMIA_BLE_TX_POWER_LEVEL) {
        ESP_LOGE(TAG,
                 "BLE %s TX power mismatch: expected_level=%d actual_level=%d",
                 stage,
                 (int)LUMIA_BLE_TX_POWER_LEVEL,
                 (int)applied_power);
        return false;
    }
    return true;
}

static bool ble_transport_set_connection_power(uint16_t conn_handle)
{
    esp_power_level_t applied_power;
    esp_err_t err = esp_ble_tx_power_set_enhanced(ESP_BLE_ENHANCED_PWR_TYPE_CONN,
                                                  conn_handle,
                                                  LUMIA_BLE_TX_POWER_LEVEL);

    if (err != ESP_OK) {
        ESP_LOGE(TAG,
                 "set BLE connection TX power to %d dBm failed: handle=%u err=%s",
                 LUMIA_BLE_TX_POWER_DBM,
                 conn_handle,
                 esp_err_to_name(err));
        return false;
    }

    applied_power = esp_ble_tx_power_get_enhanced(ESP_BLE_ENHANCED_PWR_TYPE_CONN,
                                                  conn_handle);
    if (applied_power != LUMIA_BLE_TX_POWER_LEVEL) {
        ESP_LOGE(TAG,
                 "BLE connection TX power mismatch: handle=%u expected_level=%d actual_level=%d",
                 conn_handle,
                 (int)LUMIA_BLE_TX_POWER_LEVEL,
                 (int)applied_power);
        return false;
    }
    return true;
}

static void ble_transport_report_diag(BleTransportDiagEvent event)
{
    if (s_config.on_diag != NULL) {
        s_config.on_diag(event, s_config.user_ctx);
    }
}

static void ble_transport_host_task(void *param)
{
    ESP_LOGI(TAG, "NimBLE host task started");
    nimble_port_run();
    nimble_port_freertos_deinit();
}

static int ble_transport_gap_event(struct ble_gap_event *event, void *arg)
{
    (void)arg;

    switch (event->type) {
        case BLE_GAP_EVENT_CONNECT:
            if (event->connect.status == 0) {
                if (!ble_transport_set_connection_power(event->connect.conn_handle)) {
                    int terminate_rc;

                    ESP_LOGE(TAG,
                             "disconnecting BLE handle=%u after TX power setup failure",
                             event->connect.conn_handle);
                    terminate_rc = ble_gap_terminate(event->connect.conn_handle,
                                                     BLE_ERR_REM_USER_CONN_TERM);
                    if (terminate_rc != 0) {
                        ESP_LOGE(TAG,
                                 "BLE terminate failed after TX power setup failure: handle=%u rc=%d",
                                 event->connect.conn_handle,
                                 terminate_rc);
                    }
                    return 0;
                }
                s_conn_handle = event->connect.conn_handle;
                s_notify_enabled = false;
                (void)lumia_ble_status_led_set_connected(true);
                ESP_LOGI(TAG, "BLE connected, handle=%u", s_conn_handle);
            } else {
                ESP_LOGW(TAG, "BLE connect failed, status=%d", event->connect.status);
                (void)lumia_ble_status_led_set_connected(false);
                ble_transport_advertise();
            }
            return 0;

        case BLE_GAP_EVENT_DISCONNECT:
            ESP_LOGI(TAG, "BLE disconnected, reason=%d", event->disconnect.reason);
            s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
            s_notify_enabled = false;
            (void)lumia_ble_status_led_set_connected(false);
            ble_transport_advertise();
            return 0;

        case BLE_GAP_EVENT_ADV_COMPLETE:
            ESP_LOGI(TAG, "BLE advertising completed, reason=%d", event->adv_complete.reason);
            ble_transport_advertise();
            return 0;

        case BLE_GAP_EVENT_SUBSCRIBE:
            if (event->subscribe.attr_handle == s_tx_value_handle) {
                s_notify_enabled = event->subscribe.cur_notify != 0;
                ESP_LOGI(TAG,
                         "notify subscription changed: conn=%u enabled=%d",
                         event->subscribe.conn_handle,
                         s_notify_enabled);
            }
            return 0;

        case BLE_GAP_EVENT_MTU:
            ESP_LOGI(TAG,
                     "MTU updated: conn=%u mtu=%u",
                     event->mtu.conn_handle,
                     event->mtu.value);
            return 0;

        default:
            return 0;
    }
}

static void ble_transport_advertise(void)
{
    struct ble_hs_adv_fields fields;
    struct ble_gap_adv_params adv_params;
    const char *device_name;
    int rc;

    memset(&fields, 0, sizeof(fields));
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.tx_pwr_lvl_is_present = 1;
    fields.tx_pwr_lvl = BLE_HS_ADV_TX_PWR_LVL_AUTO;

    device_name = ble_svc_gap_device_name();
    fields.name = (const uint8_t *)device_name;
    fields.name_len = (uint8_t)strlen(device_name);
    fields.name_is_complete = 1;
    fields.uuids16 = (ble_uuid16_t *)&s_service_uuid;
    fields.num_uuids16 = 1;
    fields.uuids16_is_complete = 1;

    rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gap_adv_set_fields failed: %d", rc);
        return;
    }

    memset(&adv_params, 0, sizeof(adv_params));
    adv_params.conn_mode = BLE_GAP_CONN_MODE_UND;
    adv_params.disc_mode = BLE_GAP_DISC_MODE_GEN;

    rc = ble_gap_adv_start(s_own_addr_type,
                           NULL,
                           BLE_HS_FOREVER,
                           &adv_params,
                           ble_transport_gap_event,
                           NULL);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gap_adv_start failed: %d", rc);
    }
}

static void ble_transport_on_sync(void)
{
    int rc = ble_hs_id_infer_auto(0, &s_own_addr_type);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_hs_id_infer_auto failed: %d", rc);
        return;
    }

    if (!ble_transport_set_power(ESP_BLE_PWR_TYPE_DEFAULT, "default") ||
        !ble_transport_set_power(ESP_BLE_PWR_TYPE_ADV, "advertising")) {
        ESP_LOGE(TAG, "BLE advertising disabled because TX power limiting failed");
        return;
    }

    ESP_LOGI(TAG, "BLE default and advertising TX power limited to %d dBm",
             LUMIA_BLE_TX_POWER_DBM);

    ble_transport_advertise();
}

static void ble_transport_on_reset(int reason)
{
    ESP_LOGE(TAG, "NimBLE reset, reason=%d", reason);
}

static void ble_transport_dispatch_complete_frames(void)
{
    while (s_rx_buffer_len >= 2u) {
        uint16_t expected_len = 0u;
        ModbusFrameStatus frame_status;

        if (!modbus_frame_is_supported_function(s_rx_buffer[1])) {
            ble_transport_report_diag(BLE_TRANSPORT_DIAG_PARSE_ERROR);
            memmove(s_rx_buffer, s_rx_buffer + 1u, s_rx_buffer_len - 1u);
            s_rx_buffer_len -= 1u;
            continue;
        }

        frame_status = modbus_frame_expected_request_length(s_rx_buffer, s_rx_buffer_len, &expected_len);
        if (frame_status == MODBUS_FRAME_UNSUPPORTED) {
            ble_transport_report_diag(BLE_TRANSPORT_DIAG_PARSE_ERROR);
            memmove(s_rx_buffer, s_rx_buffer + 1u, s_rx_buffer_len - 1u);
            s_rx_buffer_len -= 1u;
            continue;
        }

        if (expected_len > BLE_TRANSPORT_MAX_FRAME_LEN) {
            ble_transport_report_diag(BLE_TRANSPORT_DIAG_RX_OVERFLOW);
            s_rx_buffer_len = 0u;
            return;
        }

        if (frame_status == MODBUS_FRAME_INCOMPLETE) {
            return;
        }

        if (s_config.on_frame != NULL) {
            s_config.on_frame(s_rx_buffer, expected_len, s_config.user_ctx);
        }

        if (s_rx_buffer_len == expected_len) {
            s_rx_buffer_len = 0u;
        } else {
            memmove(s_rx_buffer, s_rx_buffer + expected_len, s_rx_buffer_len - expected_len);
            s_rx_buffer_len = (uint16_t)(s_rx_buffer_len - expected_len);
        }
    }
}

static int ble_transport_gatt_access(uint16_t conn_handle,
                                     uint16_t attr_handle,
                                     struct ble_gatt_access_ctxt *ctxt,
                                     void *arg)
{
    uint8_t incoming[BLE_TRANSPORT_RX_BUFFER_CAP];
    uint16_t incoming_len = 0u;
    int rc;

    (void)conn_handle;
    (void)attr_handle;
    (void)arg;

    if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) {
        return BLE_ATT_ERR_UNLIKELY;
    }

    incoming_len = (uint16_t)OS_MBUF_PKTLEN(ctxt->om);
    if (incoming_len == 0u) {
        return 0;
    }

    if (incoming_len > sizeof(incoming)) {
        ble_transport_report_diag(BLE_TRANSPORT_DIAG_RX_OVERFLOW);
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }

    rc = ble_hs_mbuf_to_flat(ctxt->om, incoming, sizeof(incoming), NULL);
    if (rc != 0) {
        ble_transport_report_diag(BLE_TRANSPORT_DIAG_PARSE_ERROR);
        ESP_LOGW(TAG, "ble_hs_mbuf_to_flat failed: %d", rc);
        return BLE_ATT_ERR_UNLIKELY;
    }

    if ((uint16_t)(s_rx_buffer_len + incoming_len) > sizeof(s_rx_buffer)) {
        ble_transport_report_diag(BLE_TRANSPORT_DIAG_RX_OVERFLOW);
        s_rx_buffer_len = 0u;
        return BLE_ATT_ERR_INSUFFICIENT_RES;
    }

    memcpy(s_rx_buffer + s_rx_buffer_len, incoming, incoming_len);
    s_rx_buffer_len = (uint16_t)(s_rx_buffer_len + incoming_len);
    ble_transport_dispatch_complete_frames();
    return 0;
}

static const struct ble_gatt_svc_def s_gatt_services[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = (ble_uuid_t *)&s_service_uuid,
        .characteristics =
            (struct ble_gatt_chr_def[]) {
                {
                    .uuid = (ble_uuid_t *)&s_rx_uuid,
                    .access_cb = ble_transport_gatt_access,
                    .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_NO_RSP,
                },
                {
                    .uuid = (ble_uuid_t *)&s_tx_uuid,
                    .access_cb = ble_transport_gatt_access,
                    .val_handle = &s_tx_value_handle,
                    .flags = BLE_GATT_CHR_F_NOTIFY,
                },
                {0},
            },
    },
    {0},
};

esp_err_t lumia_ble_transport_init(const BleTransportConfig *config)
{
    esp_err_t err;
    uint8_t softap_mac[6];
    int name_len;
    int rc;

    if (config == NULL || config->on_frame == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    memset(&s_config, 0, sizeof(s_config));
    s_config = *config;
    s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
    s_notify_enabled = false;
    s_rx_buffer_len = 0u;

    err = lumia_ble_status_led_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "ble status led init failed: %s", esp_err_to_name(err));
        return err;
    }

    err = nimble_port_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "nimble_port_init failed: %s", esp_err_to_name(err));
        return err;
    }

    ble_hs_cfg.reset_cb = ble_transport_on_reset;
    ble_hs_cfg.sync_cb = ble_transport_on_sync;

    ble_svc_gap_init();
    ble_svc_gatt_init();

    err = esp_read_mac(softap_mac, ESP_MAC_WIFI_SOFTAP);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "read SoftAP MAC for BLE name failed: %s", esp_err_to_name(err));
        return err;
    }
    name_len = snprintf(s_device_name,
                        sizeof(s_device_name),
                        "%s-%02X%02X",
                        CONFIG_LUMIA_WIFI_AP_SSID_PREFIX,
                        softap_mac[4],
                        softap_mac[5]);
    if (name_len <= 0 || name_len >= (int)sizeof(s_device_name)) {
        ESP_LOGE(TAG, "BLE device name is too long");
        return ESP_ERR_INVALID_SIZE;
    }

    rc = ble_svc_gap_device_name_set(s_device_name);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_svc_gap_device_name_set failed: %d", rc);
        return ESP_FAIL;
    }

    rc = ble_gatts_count_cfg(s_gatt_services);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gatts_count_cfg failed: %d", rc);
        return ESP_FAIL;
    }

    rc = ble_gatts_add_svcs(s_gatt_services);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gatts_add_svcs failed: %d", rc);
        return ESP_FAIL;
    }

    ble_store_config_init();
    nimble_port_freertos_init(ble_transport_host_task);

    ESP_LOGI(TAG,
             "BLE transport ready: name=%s svc=0x%04X rx=0x%04X tx=0x%04X",
             s_device_name,
             LUMIA_BLE_SERVICE_UUID16,
             LUMIA_BLE_RX_UUID16,
             LUMIA_BLE_TX_UUID16);
    return ESP_OK;
}

bool lumia_ble_transport_is_connected(void)
{
    return s_conn_handle != BLE_HS_CONN_HANDLE_NONE;
}

esp_err_t lumia_ble_transport_notify(const uint8_t *data, uint16_t len)
{
    struct os_mbuf *om;
    int rc;

    if (data == NULL || len == 0u) {
        return ESP_ERR_INVALID_ARG;
    }

    if (s_conn_handle == BLE_HS_CONN_HANDLE_NONE || !s_notify_enabled) {
        return ESP_ERR_INVALID_STATE;
    }

    om = ble_hs_mbuf_from_flat(data, len);
    if (om == NULL) {
        return ESP_ERR_NO_MEM;
    }

    rc = ble_gatts_notify_custom(s_conn_handle, s_tx_value_handle, om);
    if (rc != 0) {
        return ESP_FAIL;
    }

    return ESP_OK;
}

const char *lumia_ble_transport_service_uuid(void)
{
    return "0000FFE0-0000-1000-8000-00805F9B34FB";
}

const char *lumia_ble_transport_rx_uuid(void)
{
    return "0000FFE1-0000-1000-8000-00805F9B34FB";
}

const char *lumia_ble_transport_tx_uuid(void)
{
    return "0000FFE2-0000-1000-8000-00805F9B34FB";
}
