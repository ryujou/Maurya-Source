#include "serial_transport.h"

#include <stdbool.h>
#include <string.h>

#include "driver/usb_serial_jtag.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "modbus_frame.h"

#define SERIAL_TRANSPORT_TASK_STACK_SIZE  3072u
#define SERIAL_TRANSPORT_TASK_PRIORITY    4u
#define SERIAL_TRANSPORT_READ_CHUNK       32u

static const char *TAG = "serial_transport";

static SerialTransportConfig s_config;
static TaskHandle_t s_task_handle;
static uint8_t s_rx_buffer[SERIAL_TRANSPORT_RX_BUFFER_CAP];
static uint16_t s_rx_buffer_len;

static void serial_transport_report_diag(SerialTransportDiagEvent event)
{
    if (s_config.on_diag != NULL) {
        s_config.on_diag(event, s_config.user_ctx);
    }
}

static void serial_transport_dispatch_complete_frames(void)
{
    while (s_rx_buffer_len >= 2u) {
        uint16_t expected_len = 0u;
        ModbusFrameStatus frame_status;

        if (!modbus_frame_is_supported_function(s_rx_buffer[1])) {
            serial_transport_report_diag(SERIAL_TRANSPORT_DIAG_PARSE_ERROR);
            memmove(s_rx_buffer, s_rx_buffer + 1u, s_rx_buffer_len - 1u);
            s_rx_buffer_len -= 1u;
            continue;
        }

        frame_status = modbus_frame_expected_request_length(
            s_rx_buffer, s_rx_buffer_len, &expected_len);
        if (frame_status == MODBUS_FRAME_UNSUPPORTED) {
            serial_transport_report_diag(SERIAL_TRANSPORT_DIAG_PARSE_ERROR);
            memmove(s_rx_buffer, s_rx_buffer + 1u, s_rx_buffer_len - 1u);
            s_rx_buffer_len -= 1u;
            continue;
        }

        if (expected_len > SERIAL_TRANSPORT_MAX_FRAME_LEN) {
            serial_transport_report_diag(SERIAL_TRANSPORT_DIAG_RX_OVERFLOW);
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
            memmove(s_rx_buffer,
                    s_rx_buffer + expected_len,
                    s_rx_buffer_len - expected_len);
            s_rx_buffer_len = (uint16_t)(s_rx_buffer_len - expected_len);
        }
    }
}

static void serial_transport_task(void *arg)
{
    uint8_t incoming[SERIAL_TRANSPORT_READ_CHUNK];
    (void)arg;

    while (1) {
        int read_len = usb_serial_jtag_read_bytes(
            incoming, sizeof(incoming), pdMS_TO_TICKS(20u));

        if (read_len <= 0) {
            continue;
        }

        if ((uint16_t)(s_rx_buffer_len + read_len) > sizeof(s_rx_buffer)) {
            serial_transport_report_diag(SERIAL_TRANSPORT_DIAG_RX_OVERFLOW);
            s_rx_buffer_len = 0u;
            continue;
        }

        memcpy(s_rx_buffer + s_rx_buffer_len, incoming, (size_t)read_len);
        s_rx_buffer_len = (uint16_t)(s_rx_buffer_len + read_len);
        serial_transport_dispatch_complete_frames();
    }
}

esp_err_t lumia_serial_transport_init(const SerialTransportConfig *config)
{
    usb_serial_jtag_driver_config_t driver_config =
        USB_SERIAL_JTAG_DRIVER_CONFIG_DEFAULT();
    BaseType_t task_created;
    esp_err_t err;

    if (config == NULL || config->on_frame == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    if (s_task_handle != NULL) {
        return ESP_ERR_INVALID_STATE;
    }

    memset(&s_config, 0, sizeof(s_config));
    s_config = *config;
    s_rx_buffer_len = 0u;

    err = usb_serial_jtag_driver_install(&driver_config);
    if (err != ESP_OK) {
        ESP_LOGE(TAG,
                 "usb_serial_jtag_driver_install failed: %s",
                 esp_err_to_name(err));
        return err;
    }

    task_created = xTaskCreate(serial_transport_task,
                               "serial_transport",
                               SERIAL_TRANSPORT_TASK_STACK_SIZE,
                               NULL,
                               SERIAL_TRANSPORT_TASK_PRIORITY,
                               &s_task_handle);
    if (task_created != pdPASS) {
        (void)usb_serial_jtag_driver_uninstall();
        s_task_handle = NULL;
        return ESP_ERR_NO_MEM;
    }

    ESP_LOGI(TAG, "USB Serial/JTAG transport ready");
    return ESP_OK;
}

esp_err_t lumia_serial_transport_send(const uint8_t *data, uint16_t len)
{
    size_t total_written = 0u;

    if (data == NULL || len == 0u) {
        return ESP_ERR_INVALID_ARG;
    }
    if (s_task_handle == NULL) {
        return ESP_ERR_INVALID_STATE;
    }

    while (total_written < len) {
        int written = usb_serial_jtag_write_bytes(
            data + total_written,
            len - total_written,
            pdMS_TO_TICKS(50u));
        if (written <= 0) {
            return ESP_ERR_TIMEOUT;
        }
        total_written += (size_t)written;
    }

    return usb_serial_jtag_wait_tx_done(pdMS_TO_TICKS(50u));
}

bool lumia_serial_transport_is_connected(void)
{
    return usb_serial_jtag_is_connected();
}
