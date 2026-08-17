#include "ota_service.h"

#include <ctype.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "esp_app_desc.h"
#include "esp_log.h"
#include "esp_ota_ops.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/semphr.h"
#include "freertos/stream_buffer.h"
#include "freertos/task.h"
#include "psa/crypto.h"
#include "sdkconfig.h"

#define OTA_STREAM_BYTES       (16u * 1024u)
#define OTA_STREAM_TRIGGER     1u
#define OTA_TASK_STACK_BYTES   8192u
#define OTA_TASK_PRIORITY      4u
#define OTA_HTTP_CHUNK_BYTES   4096u
#define OTA_EVENT_START        BIT0
#define OTA_EVENT_START_DONE   BIT1
#define OTA_EVENT_ABORT        BIT2
#define OTA_EVENT_TASK_DONE    BIT3

static const char *TAG = "maurya_ota";
static LumiaOtaServiceConfig s_config;
static LumiaOtaStatus s_status;
static SemaphoreHandle_t s_mutex;
static StreamBufferHandle_t s_stream;
static EventGroupHandle_t s_events;
static TaskHandle_t s_task;
static const esp_partition_t *s_target;
static esp_ota_handle_t s_ota_handle;
static uint8_t s_expected_sha[32];
static uint8_t s_ota_chunk[OTA_HTTP_CHUNK_BYTES];
static uint8_t s_http_chunk[OTA_HTTP_CHUNK_BYTES];
static uint32_t s_accepted_bytes;
static int64_t s_session_started_us;

static void status_set(LumiaOtaState state, esp_err_t error)
{
    if (xSemaphoreTake(s_mutex, pdMS_TO_TICKS(100u)) == pdTRUE) {
        s_status.state = state;
        s_status.error = error;
        xSemaphoreGive(s_mutex);
    }
}

static void status_add_received(size_t amount)
{
    if (xSemaphoreTake(s_mutex, pdMS_TO_TICKS(100u)) == pdTRUE) {
        s_status.received_bytes += (uint32_t)amount;
        xSemaphoreGive(s_mutex);
    }
}

static void set_activity(bool active)
{
    if (s_config.on_activity != NULL) {
        s_config.on_activity(active, s_config.user_ctx);
    }
}

static void return_to_ble_and_restart(void)
{
    (void)lumia_ota_session_force_ble_next_boot();
    (void)lumia_ota_session_clear();
    vTaskDelay(pdMS_TO_TICKS(300u));
    esp_restart();
}

static void fail_update(esp_err_t error)
{
    if (s_ota_handle != 0u) {
        (void)esp_ota_abort(s_ota_handle);
        s_ota_handle = 0u;
    }
    status_set(LUMIA_OTA_FAILED, error);
    set_activity(false);
    xEventGroupSetBits(s_events, OTA_EVENT_TASK_DONE);
}

static bool descriptions_are_acceptable(void)
{
    esp_app_desc_t candidate;
    const esp_app_desc_t *running = esp_app_get_description();

    if (s_target == NULL ||
        esp_ota_get_partition_description(s_target, &candidate) != ESP_OK) {
        return false;
    }
    if (candidate.secure_version <= running->secure_version ||
        candidate.secure_version <= s_config.secure_version) {
        ESP_LOGE(TAG, "same-version or downgrade image rejected");
        return false;
    }
    if (strcmp(candidate.version, running->version) == 0) {
        ESP_LOGE(TAG, "same semantic version image rejected");
        return false;
    }
    return true;
}

static void ota_task(void *arg)
{
    psa_hash_operation_t sha = PSA_HASH_OPERATION_INIT;
    uint8_t actual_sha[32];
    (void)arg;

    while (true) {
        EventBits_t bits = xEventGroupWaitBits(
            s_events, OTA_EVENT_START, pdTRUE, pdFALSE, pdMS_TO_TICKS(1000u));
        if ((bits & OTA_EVENT_START) == 0u) {
            LumiaOtaStatus snapshot;
            lumia_ota_service_get_status(&snapshot);
            int64_t elapsed_seconds =
                (esp_timer_get_time() - s_session_started_us) / 1000000;
            if (s_config.session_timeout_enabled &&
                snapshot.state == LUMIA_OTA_WAITING &&
                elapsed_seconds >= CONFIG_LUMIA_OTA_SESSION_TIMEOUT_SECONDS) {
                status_set(LUMIA_OTA_FAILED, ESP_ERR_TIMEOUT);
                return_to_ble_and_restart();
            }
            continue;
        }

        xEventGroupClearBits(s_events,
                             OTA_EVENT_ABORT | OTA_EVENT_START_DONE |
                                 OTA_EVENT_TASK_DONE);
        xStreamBufferReset(s_stream);
        s_target = esp_ota_get_next_update_partition(NULL);
        if (s_target == NULL ||
            esp_ota_begin(s_target, s_status.expected_bytes, &s_ota_handle) !=
                ESP_OK) {
            fail_update(ESP_FAIL);
            xEventGroupSetBits(s_events, OTA_EVENT_START_DONE);
            continue;
        }

        sha = psa_hash_operation_init();
        if (psa_hash_setup(&sha, PSA_ALG_SHA_256) != PSA_SUCCESS) {
            (void)psa_hash_abort(&sha);
            fail_update(ESP_FAIL);
            xEventGroupSetBits(s_events, OTA_EVENT_START_DONE);
            continue;
        }
        status_set(LUMIA_OTA_RECEIVING, ESP_OK);
        set_activity(true);
        xEventGroupSetBits(s_events, OTA_EVENT_START_DONE);
        int64_t last_data_us = esp_timer_get_time();

        while (s_status.received_bytes < s_status.expected_bytes) {
            if ((xEventGroupGetBits(s_events) & OTA_EVENT_ABORT) != 0u) {
                (void)psa_hash_abort(&sha);
                fail_update(ESP_ERR_INVALID_STATE);
                break;
            }
            size_t received = xStreamBufferReceive(
                s_stream, s_ota_chunk, sizeof(s_ota_chunk), pdMS_TO_TICKS(500u));
            if (received == 0u) {
                int64_t idle_seconds =
                    (esp_timer_get_time() - last_data_us) / 1000000;
                if (idle_seconds >= CONFIG_LUMIA_OTA_UPLOAD_TIMEOUT_SECONDS) {
                    (void)psa_hash_abort(&sha);
                    fail_update(ESP_ERR_TIMEOUT);
                    break;
                }
                continue;
            }
            if (esp_ota_write(s_ota_handle, s_ota_chunk, received) != ESP_OK ||
                psa_hash_update(&sha, s_ota_chunk, received) != PSA_SUCCESS) {
                (void)psa_hash_abort(&sha);
                fail_update(ESP_FAIL);
                break;
            }
            status_add_received(received);
            last_data_us = esp_timer_get_time();
        }

        LumiaOtaStatus finished;
        lumia_ota_service_get_status(&finished);
        if (finished.state != LUMIA_OTA_RECEIVING) {
            continue;
        }
        status_set(LUMIA_OTA_VERIFYING, ESP_OK);
        ESP_LOGI(TAG, "verifying image, OTA task stack high-water=%u bytes",
                 (unsigned)(uxTaskGetStackHighWaterMark(NULL) *
                            sizeof(StackType_t)));
        size_t hash_length = 0u;
        if (psa_hash_finish(&sha, actual_sha, sizeof(actual_sha),
                            &hash_length) != PSA_SUCCESS ||
            hash_length != sizeof(actual_sha)) {
            (void)psa_hash_abort(&sha);
            fail_update(ESP_FAIL);
            continue;
        }
        if (memcmp(actual_sha, s_expected_sha, sizeof(actual_sha)) != 0) {
            fail_update(ESP_ERR_INVALID_CRC);
            continue;
        }
        esp_err_t err = esp_ota_end(s_ota_handle);
        s_ota_handle = 0u;
        if (err != ESP_OK || !descriptions_are_acceptable()) {
            fail_update(err == ESP_OK ? ESP_ERR_INVALID_VERSION : err);
            continue;
        }
        status_set(LUMIA_OTA_VERIFIED, ESP_OK);
        set_activity(false);
        xEventGroupSetBits(s_events, OTA_EVENT_TASK_DONE);
    }
}

static bool token_matches(httpd_req_t *req)
{
    char provided[2u * LUMIA_OTA_TOKEN_LEN + 1u];
    uint8_t parsed[LUMIA_OTA_TOKEN_LEN];
    uint8_t difference = 0u;

    if (httpd_req_get_hdr_value_str(req,
                                    "X-Maurya-OTA-Token",
                                    provided,
                                    sizeof(provided)) != ESP_OK ||
        strlen(provided) != 2u * LUMIA_OTA_TOKEN_LEN) {
        return false;
    }
    for (size_t index = 0u; index < LUMIA_OTA_TOKEN_LEN; ++index) {
        char high = (char)tolower((unsigned char)provided[index * 2u]);
        char low = (char)tolower((unsigned char)provided[index * 2u + 1u]);
        if (!isxdigit((unsigned char)high) ||
            !isxdigit((unsigned char)low)) {
            return false;
        }
        uint8_t high_value =
            (uint8_t)(high <= '9' ? high - '0' : high - 'a' + 10);
        uint8_t low_value =
            (uint8_t)(low <= '9' ? low - '0' : low - 'a' + 10);
        parsed[index] = (uint8_t)((high_value << 4u) | low_value);
        difference |= (uint8_t)(parsed[index] ^ s_config.session.token[index]);
    }
    return difference == 0u;
}

static esp_err_t send_json(httpd_req_t *req,
                           const char *status,
                           const char *body)
{
    httpd_resp_set_type(req, "application/json; charset=utf-8");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    if (status != NULL) {
        httpd_resp_set_status(req, status);
    }
    return httpd_resp_sendstr(req, body);
}

static esp_err_t require_token(httpd_req_t *req)
{
    if (token_matches(req)) {
        return ESP_OK;
    }
    return httpd_resp_send_err(req, HTTPD_401_UNAUTHORIZED, "invalid token");
}

static esp_err_t send_plain_error(httpd_req_t *req,
                                  const char *status,
                                  const char *message)
{
    httpd_resp_set_status(req, status);
    httpd_resp_set_type(req, "text/plain; charset=utf-8");
    return httpd_resp_sendstr(req, message);
}

static esp_err_t info_handler(httpd_req_t *req)
{
    if (!token_matches(req)) {
        return require_token(req);
    }
    const esp_partition_t *target = esp_ota_get_next_update_partition(NULL);
    char body[224];
    int length = snprintf(
        body, sizeof(body),
        "{\"version\":\"%s\",\"layoutVersion\":%u,\"assetPackVersion\":%u,"
        "\"maxImageBytes\":%" PRIu32 ",\"targetSlot\":\"%s\"}",
        esp_app_get_description()->version, CONFIG_LUMIA_OTA_LAYOUT_VERSION,
        CONFIG_LUMIA_OTA_ASSET_PACK_VERSION,
        target != NULL ? target->size : 0u,
        target != NULL ? target->label : "");
    if (length < 0 || (size_t)length >= sizeof(body)) {
        return httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR,
                                   "response overflow");
    }
    return send_json(req, "200 OK", body);
}

static esp_err_t status_handler(httpd_req_t *req)
{
    if (!token_matches(req)) {
        return require_token(req);
    }
    LumiaOtaStatus status;
    lumia_ota_service_get_status(&status);
    char body[192];
    int length = snprintf(
        body, sizeof(body),
        "{\"state\":\"%s\",\"receivedBytes\":%" PRIu32
        ",\"expectedBytes\":%" PRIu32 ",\"errorCode\":%d}",
        lumia_ota_state_name(status.state), status.received_bytes,
        status.expected_bytes, status.error);
    if (length < 0 || (size_t)length >= sizeof(body)) {
        return httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR,
                                   "response overflow");
    }
    return send_json(req, "200 OK", body);
}

static bool parse_sha_header(httpd_req_t *req, uint8_t output[32])
{
    char text[65];
    if (httpd_req_get_hdr_value_str(req, "X-Image-SHA256",
                                    text, sizeof(text)) != ESP_OK ||
        strlen(text) != 64u) {
        return false;
    }
    for (size_t index = 0u; index < 32u; ++index) {
        unsigned int byte = 0u;
        if (sscanf(&text[index * 2u], "%2x", &byte) != 1) {
            return false;
        }
        output[index] = (uint8_t)byte;
    }
    return true;
}

static esp_err_t image_handler(httpd_req_t *req)
{
    char layout[12];
    uint8_t expected_sha[32];
    size_t total = 0u;

    if (!token_matches(req)) {
        return require_token(req);
    }
    const esp_partition_t *target = esp_ota_get_next_update_partition(NULL);
    if (target == NULL || req->content_len <= 0 ||
        (size_t)req->content_len > target->size ||
        !parse_sha_header(req, expected_sha) ||
        httpd_req_get_hdr_value_str(req, "X-Layout-Version",
                                    layout, sizeof(layout)) != ESP_OK ||
        strtoul(layout, NULL, 10) != CONFIG_LUMIA_OTA_LAYOUT_VERSION) {
        return httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST,
                                   "invalid image metadata");
    }

    if (xSemaphoreTake(s_mutex, pdMS_TO_TICKS(100u)) != pdTRUE) {
        return send_plain_error(req, "503 Service Unavailable", "OTA busy");
    }
    if (s_status.state != LUMIA_OTA_WAITING &&
        s_status.state != LUMIA_OTA_FAILED) {
        xSemaphoreGive(s_mutex);
        return send_plain_error(req, "409 Conflict", "OTA busy");
    }
    s_status.state = LUMIA_OTA_WAITING;
    s_status.error = ESP_OK;
    s_status.received_bytes = 0u;
    s_status.expected_bytes = (uint32_t)req->content_len;
    memcpy(s_expected_sha, expected_sha, sizeof(s_expected_sha));
    xSemaphoreGive(s_mutex);
    xEventGroupSetBits(s_events, OTA_EVENT_START);
    EventBits_t started = xEventGroupWaitBits(
        s_events, OTA_EVENT_START_DONE, pdTRUE, pdFALSE,
        pdMS_TO_TICKS(5000u));
    if ((started & OTA_EVENT_START_DONE) == 0u ||
        s_status.state != LUMIA_OTA_RECEIVING) {
        return send_plain_error(req, "503 Service Unavailable",
                                "OTA start failed");
    }

    while (total < (size_t)req->content_len) {
        size_t wanted = (size_t)req->content_len - total;
        if (wanted > sizeof(s_http_chunk)) {
            wanted = sizeof(s_http_chunk);
        }
        int received = httpd_req_recv(req, (char *)s_http_chunk, wanted);
        if (received == HTTPD_SOCK_ERR_TIMEOUT) {
            continue;
        }
        if (received <= 0 ||
            xStreamBufferSend(s_stream, s_http_chunk, (size_t)received,
                              pdMS_TO_TICKS(5000u)) != (size_t)received) {
            xEventGroupSetBits(s_events, OTA_EVENT_ABORT);
            return httpd_resp_send_err(req,
                                       HTTPD_500_INTERNAL_SERVER_ERROR,
                                       "upload interrupted");
        }
        total += (size_t)received;
    }

    EventBits_t done = xEventGroupWaitBits(
        s_events, OTA_EVENT_TASK_DONE, pdTRUE, pdFALSE,
        pdMS_TO_TICKS((CONFIG_LUMIA_OTA_UPLOAD_TIMEOUT_SECONDS + 10u) * 1000u));
    LumiaOtaStatus status;
    lumia_ota_service_get_status(&status);
    if ((done & OTA_EVENT_TASK_DONE) == 0u ||
        status.state != LUMIA_OTA_VERIFIED) {
        return httpd_resp_send_err(req,
                                   HTTPD_400_BAD_REQUEST,
                                   "image verification failed");
    }
    char body[80];
    int length = snprintf(body, sizeof(body),
                          "{\"verified\":true,\"receivedBytes\":%" PRIu32 "}",
                          status.received_bytes);
    if (length < 0 || (size_t)length >= sizeof(body)) {
        return httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR,
                                   "response overflow");
    }
    return send_json(req, "200 OK", body);
}

static esp_err_t cancel_handler(httpd_req_t *req)
{
    if (!token_matches(req)) {
        return require_token(req);
    }
    xEventGroupSetBits(s_events, OTA_EVENT_ABORT);
    (void)lumia_ota_session_force_ble_next_boot();
    esp_err_t err = send_json(req, "200 OK", "{\"cancelled\":true}");
    vTaskDelay(pdMS_TO_TICKS(250u));
    esp_restart();
    return err;
}

static esp_err_t commit_handler(httpd_req_t *req)
{
    if (!token_matches(req)) {
        return require_token(req);
    }
    LumiaOtaStatus status;
    lumia_ota_service_get_status(&status);
    if (status.state != LUMIA_OTA_VERIFIED || s_target == NULL) {
        return send_plain_error(req, "409 Conflict",
                                "image is not verified");
    }
    esp_err_t err = esp_ota_set_boot_partition(s_target);
    if (err != ESP_OK || lumia_ota_session_force_ble_next_boot() != ESP_OK) {
        return httpd_resp_send_err(req,
                                   HTTPD_500_INTERNAL_SERVER_ERROR,
                                   "commit failed");
    }
    status_set(LUMIA_OTA_REBOOTING, ESP_OK);
    err = send_json(req, "200 OK", "{\"rebooting\":true}");
    vTaskDelay(pdMS_TO_TICKS(500u));
    esp_restart();
    return err;
}

esp_err_t lumia_ota_service_start(const LumiaOtaServiceConfig *config)
{
    if (config == NULL || s_task != NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    s_config = *config;
    if (psa_crypto_init() != PSA_SUCCESS) {
        return ESP_FAIL;
    }
    s_mutex = xSemaphoreCreateMutex();
    s_stream = xStreamBufferCreate(OTA_STREAM_BYTES, OTA_STREAM_TRIGGER);
    s_events = xEventGroupCreate();
    if (s_mutex == NULL || s_stream == NULL || s_events == NULL) {
        return ESP_ERR_NO_MEM;
    }
    memset(&s_status, 0, sizeof(s_status));
    s_status.state = LUMIA_OTA_WAITING;
    s_accepted_bytes = 0u;
    s_session_started_us = esp_timer_get_time();
    return xTaskCreate(ota_task, "ota_task", OTA_TASK_STACK_BYTES, NULL,
                       OTA_TASK_PRIORITY, &s_task) == pdPASS
               ? ESP_OK
               : ESP_ERR_NO_MEM;
}

esp_err_t lumia_ota_service_begin(uint32_t expected_bytes,
                                  const uint8_t expected_sha[32])
{
    const esp_partition_t *target = esp_ota_get_next_update_partition(NULL);
    if (s_task == NULL || expected_sha == NULL || expected_bytes == 0u ||
        target == NULL || expected_bytes > target->size) {
        return ESP_ERR_INVALID_ARG;
    }
    if (xSemaphoreTake(s_mutex, pdMS_TO_TICKS(100u)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    if (s_status.state != LUMIA_OTA_WAITING &&
        s_status.state != LUMIA_OTA_FAILED) {
        xSemaphoreGive(s_mutex);
        return ESP_ERR_INVALID_STATE;
    }
    s_status.state = LUMIA_OTA_WAITING;
    s_status.error = ESP_OK;
    s_status.received_bytes = 0u;
    s_status.expected_bytes = expected_bytes;
    s_accepted_bytes = 0u;
    memcpy(s_expected_sha, expected_sha, sizeof(s_expected_sha));
    xSemaphoreGive(s_mutex);

    xEventGroupClearBits(s_events, OTA_EVENT_ABORT | OTA_EVENT_START_DONE |
                                       OTA_EVENT_TASK_DONE);
    xEventGroupSetBits(s_events, OTA_EVENT_START);
    EventBits_t started = xEventGroupWaitBits(
        s_events, OTA_EVENT_START_DONE, pdTRUE, pdFALSE,
        pdMS_TO_TICKS(5000u));
    LumiaOtaStatus status;
    lumia_ota_service_get_status(&status);
    return (started & OTA_EVENT_START_DONE) != 0u &&
                   status.state == LUMIA_OTA_RECEIVING
               ? ESP_OK
               : ESP_FAIL;
}

esp_err_t lumia_ota_service_write(uint32_t offset,
                                  const uint8_t *data,
                                  size_t length,
                                  uint32_t *next_offset)
{
    if (s_task == NULL || data == NULL || length == 0u ||
        next_offset == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    if (xSemaphoreTake(s_mutex, pdMS_TO_TICKS(100u)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    if (s_status.state != LUMIA_OTA_RECEIVING ||
        offset != s_accepted_bytes ||
        length > s_status.expected_bytes - s_accepted_bytes) {
        xSemaphoreGive(s_mutex);
        return ESP_ERR_INVALID_STATE;
    }
    xSemaphoreGive(s_mutex);

    if (xStreamBufferSend(s_stream, data, length,
                          pdMS_TO_TICKS(5000u)) != length) {
        return ESP_ERR_TIMEOUT;
    }
    if (xSemaphoreTake(s_mutex, pdMS_TO_TICKS(100u)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    s_accepted_bytes += (uint32_t)length;
    *next_offset = s_accepted_bytes;
    xSemaphoreGive(s_mutex);
    return ESP_OK;
}

esp_err_t lumia_ota_service_commit(void)
{
    LumiaOtaStatus status;
    lumia_ota_service_get_status(&status);
    if (status.state != LUMIA_OTA_VERIFIED || s_target == NULL) {
        return ESP_ERR_INVALID_STATE;
    }
    esp_err_t err = esp_ota_set_boot_partition(s_target);
    if (err == ESP_OK) {
        err = lumia_ota_session_force_ble_next_boot();
    }
    if (err == ESP_OK) {
        status_set(LUMIA_OTA_REBOOTING, ESP_OK);
    }
    return err;
}

esp_err_t lumia_ota_service_cancel(void)
{
    if (s_task == NULL) {
        return ESP_ERR_INVALID_STATE;
    }
    xEventGroupSetBits(s_events, OTA_EVENT_ABORT);
    return ESP_OK;
}

esp_err_t lumia_ota_service_register_http(httpd_handle_t server)
{
    const httpd_uri_t handlers[] = {
        {.uri = "/api/v1/ota/info", .method = HTTP_GET,
         .handler = info_handler},
        {.uri = "/api/v1/ota/image", .method = HTTP_PUT,
         .handler = image_handler},
        {.uri = "/api/v1/ota/status", .method = HTTP_GET,
         .handler = status_handler},
        {.uri = "/api/v1/ota/commit", .method = HTTP_POST,
         .handler = commit_handler},
        {.uri = "/api/v1/ota/cancel", .method = HTTP_POST,
         .handler = cancel_handler},
    };
    if (server == NULL || s_task == NULL) {
        return ESP_ERR_INVALID_STATE;
    }
    for (size_t index = 0u;
         index < sizeof(handlers) / sizeof(handlers[0]); ++index) {
        esp_err_t err = httpd_register_uri_handler(server, &handlers[index]);
        if (err != ESP_OK) {
            return err;
        }
    }
    return ESP_OK;
}

void lumia_ota_service_get_status(LumiaOtaStatus *status)
{
    if (status == NULL || s_mutex == NULL) {
        return;
    }
    if (xSemaphoreTake(s_mutex, pdMS_TO_TICKS(100u)) == pdTRUE) {
        *status = s_status;
        xSemaphoreGive(s_mutex);
    }
}

bool lumia_ota_service_is_receiving(void)
{
    LumiaOtaStatus status = {0};
    lumia_ota_service_get_status(&status);
    return status.state == LUMIA_OTA_RECEIVING ||
           status.state == LUMIA_OTA_VERIFYING;
}

const char *lumia_ota_state_name(LumiaOtaState state)
{
    switch (state) {
        case LUMIA_OTA_WAITING:
            return "waiting";
        case LUMIA_OTA_RECEIVING:
            return "receiving";
        case LUMIA_OTA_VERIFYING:
            return "verifying";
        case LUMIA_OTA_VERIFIED:
            return "verified";
        case LUMIA_OTA_REBOOTING:
            return "rebooting";
        case LUMIA_OTA_FAILED:
        default:
            return "failed";
    }
}
