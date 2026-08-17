#include "web_server.h"

#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "cJSON.h"
#include "esp_event.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_spiffs.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "lwip/inet.h"
#include "lwip/sockets.h"
#include "ota_service.h"
#include "resource_pack.h"
#include "sdkconfig.h"
#include "wifi_channel_selector.h"

#define WEB_CONTROL_TIMEOUT_MS 1000u
#define WEB_MAX_BODY_LEN       4096u
#define WEB_FILE_CHUNK_LEN     1024u
#define WEB_STATIC_PATH_LEN    192u
#define DNS_TASK_STACK_SIZE    3072u
#define DNS_TASK_PRIORITY      3u
#define LUMIA_WIFI_TX_POWER_QDBM 34
#define LUMIA_WIFI_TX_POWER_DBM_X10 85
#define LUMIA_WIFI_SCAN_MAX_RECORDS 32u
#define LUMIA_WIFI_SCAN_ACTIVE_MIN_MS 20u
#define LUMIA_WIFI_SCAN_ACTIVE_MAX_MS 60u

static const char *TAG = "lumia_web";
static const char *ASSET_BASE_PATH = "/assets";
static const char *CAPTIVE_PORTAL_URI = "http://192.168.4.1/";
static LumiaWebServerConfig s_config;
static char s_ap_ssid[33];
static uint32_t s_next_request_id;
static httpd_handle_t s_httpd;

static esp_err_t apply_wifi_tx_power_limit(void)
{
    int8_t applied_power = 0;
    esp_err_t err = esp_wifi_set_max_tx_power(LUMIA_WIFI_TX_POWER_QDBM);

    if (err != ESP_OK) {
        ESP_LOGE(TAG,
                 "set Wi-Fi TX power to %d.%d dBm failed: %s",
                 LUMIA_WIFI_TX_POWER_DBM_X10 / 10,
                 LUMIA_WIFI_TX_POWER_DBM_X10 % 10,
                 esp_err_to_name(err));
        return err;
    }

    err = esp_wifi_get_max_tx_power(&applied_power);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "read Wi-Fi TX power failed: %s", esp_err_to_name(err));
        return err;
    }
    if (applied_power != LUMIA_WIFI_TX_POWER_QDBM) {
        ESP_LOGE(TAG,
                 "Wi-Fi TX power mismatch: expected=%d qdBm actual=%d qdBm",
                 LUMIA_WIFI_TX_POWER_QDBM,
                 applied_power);
        return ESP_ERR_INVALID_STATE;
    }

    ESP_LOGI(TAG,
             "Wi-Fi max TX power configured to %d.%d dBm (%d qdBm)",
             LUMIA_WIFI_TX_POWER_DBM_X10 / 10,
             LUMIA_WIFI_TX_POWER_DBM_X10 % 10,
             applied_power);
    return ESP_OK;
}

static uint8_t select_softap_channel(uint8_t fallback_channel)
{
#if CONFIG_LUMIA_WIFI_AP_AUTO_CHANNEL
    const wifi_scan_config_t scan_config = {
        .show_hidden = true,
        .scan_type = WIFI_SCAN_TYPE_ACTIVE,
        .scan_time.active = {
            .min = LUMIA_WIFI_SCAN_ACTIVE_MIN_MS,
            .max = LUMIA_WIFI_SCAN_ACTIVE_MAX_MS,
        },
    };
    LumiaWifiChannelObservation observations[LUMIA_WIFI_SCAN_MAX_RECORDS];
    wifi_ap_record_t *records = NULL;
    esp_netif_t *sta_netif = esp_netif_create_default_wifi_sta();
    uint16_t record_count = 0u;
    uint8_t selected_channel = lumia_wifi_select_channel(NULL, 0u,
                                                          fallback_channel);
    esp_err_t err;

    if (sta_netif == NULL) {
        ESP_LOGW(TAG, "create scan STA failed; using fallback channel %u",
                 selected_channel);
        return selected_channel;
    }
    err = esp_wifi_set_mode(WIFI_MODE_STA);
    if (err == ESP_OK) {
        err = esp_wifi_start();
    }
    if (err == ESP_OK) {
        err = esp_wifi_scan_start(&scan_config, true);
    }
    if (err == ESP_OK) {
        err = esp_wifi_scan_get_ap_num(&record_count);
    }
    if (err == ESP_OK && record_count > 0u) {
        if (record_count > LUMIA_WIFI_SCAN_MAX_RECORDS) {
            record_count = LUMIA_WIFI_SCAN_MAX_RECORDS;
        }
        records = calloc(record_count, sizeof(*records));
        if (records == NULL) {
            err = ESP_ERR_NO_MEM;
        } else {
            err = esp_wifi_scan_get_ap_records(&record_count, records);
        }
    }
    if (err == ESP_OK) {
        for (uint16_t index = 0u; index < record_count; ++index) {
            observations[index].primary_channel = records[index].primary;
            observations[index].rssi = records[index].rssi;
        }
        selected_channel = lumia_wifi_select_channel(observations,
                                                     record_count,
                                                     fallback_channel);
        ESP_LOGI(TAG,
                 "Wi-Fi startup scan found %u APs; selected channel %u (fallback %u)",
                 record_count,
                 selected_channel,
                 selected_channel);
    } else {
        ESP_LOGW(TAG,
                 "Wi-Fi startup scan failed (%s); using fallback channel %u",
                 esp_err_to_name(err),
                 fallback_channel);
    }
    free(records);
    (void)esp_wifi_clear_ap_list();

    err = esp_wifi_stop();
    esp_netif_destroy_default_wifi(sta_netif);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "stop scan STA failed: %s", esp_err_to_name(err));
        return 0u;
    }
    return selected_channel;
#else
    ESP_LOGI(TAG, "Wi-Fi automatic channel selection disabled; channel %u",
             fallback_channel);
    return fallback_channel;
#endif
}

static esp_err_t send_json_text(httpd_req_t *req,
                                const char *json,
                                const char *status)
{
    httpd_resp_set_type(req, "application/json; charset=utf-8");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    if (status != NULL) {
        httpd_resp_set_status(req, status);
    }
    return httpd_resp_sendstr(req, json);
}

static esp_err_t send_json_error(httpd_req_t *req,
                                 const char *status,
                                 const char *message)
{
    cJSON *root = cJSON_CreateObject();
    char *text;
    esp_err_t err;

    if (root == NULL) {
        return httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR,
                                   "out of memory");
    }
    cJSON_AddStringToObject(root, "error", message);
    text = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    if (text == NULL) {
        return httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR,
                                   "out of memory");
    }
    err = send_json_text(req, text, status);
    free(text);
    return err;
}

static cJSON *read_json_body(httpd_req_t *req)
{
    char *body;
    size_t received = 0u;
    int chunk_len;
    cJSON *root;

    if (req->content_len <= 0 || req->content_len > WEB_MAX_BODY_LEN) {
        return NULL;
    }
    body = malloc((size_t)req->content_len + 1u);
    if (body == NULL) {
        return NULL;
    }

    while (received < (size_t)req->content_len) {
        chunk_len = httpd_req_recv(req,
                                   body + received,
                                   (size_t)req->content_len - received);
        if (chunk_len == HTTPD_SOCK_ERR_TIMEOUT) {
            continue;
        }
        if (chunk_len <= 0) {
            free(body);
            return NULL;
        }
        received += (size_t)chunk_len;
    }
    body[received] = '\0';
    root = cJSON_ParseWithLength(body, received);
    free(body);
    return root;
}

static bool json_required_int(const cJSON *object,
                              const char *name,
                              int minimum,
                              int maximum,
                              int *value)
{
    const cJSON *item = cJSON_GetObjectItemCaseSensitive(object, name);

    if (!cJSON_IsNumber(item) || item->valuedouble != (double)item->valueint ||
        item->valueint < minimum || item->valueint > maximum) {
        return false;
    }
    *value = item->valueint;
    return true;
}

static bool parse_group(const cJSON *object, LumiaGroupInnerConfig *group)
{
    int inner_mode;
    int hue;
    int sat;
    int value;
    int inner_param;

    if (!cJSON_IsObject(object) || group == NULL ||
        !json_required_int(object, "innerMode", 1, 4, &inner_mode) ||
        !json_required_int(object, "hue", 0, 359, &hue) ||
        !json_required_int(object, "sat", 0, 255, &sat) ||
        !json_required_int(object, "value", 0, 255, &value) ||
        !json_required_int(object, "innerParam", 0, 255, &inner_param)) {
        return false;
    }

    group->inner_mode = (uint8_t)inner_mode;
    group->hue = (uint16_t)hue;
    group->sat = (uint8_t)sat;
    group->val = (uint8_t)value;
    group->inner_param = (uint8_t)inner_param;
    return true;
}

static esp_err_t exchange_control(LumiaWebControlRequest *request,
                                  LumiaWebControlResponse *response)
{
    request->id = __atomic_add_fetch(&s_next_request_id, 1u, __ATOMIC_RELAXED);
    return s_config.exchange(request,
                             response,
                             WEB_CONTROL_TIMEOUT_MS,
                             s_config.user_ctx);
}

static cJSON *state_to_json(const LumiaWebControlResponse *response)
{
    const RuntimeState *state = &response->state;
    cJSON *root = cJSON_CreateObject();
    cJSON *global;
    cJSON *groups;
    cJSON *diagnostics;

    if (root == NULL) {
        return NULL;
    }
    cJSON_AddStringToObject(root, "wirelessMode", "wifi");

    global = cJSON_AddObjectToObject(root, "global");
    cJSON_AddNumberToObject(global, "sceneMode", state->cfg.scene_mode);
    cJSON_AddNumberToObject(global, "sceneParam", state->cfg.scene_param);
    cJSON_AddNumberToObject(global, "globalBrightness", state->cfg.led_global_bri);
    cJSON_AddNumberToObject(global, "gainR", state->cfg.led_gain_r);
    cJSON_AddNumberToObject(global, "gainG", state->cfg.led_gain_g);
    cJSON_AddNumberToObject(global, "gainB", state->cfg.led_gain_b);
    cJSON_AddNumberToObject(global, "deviceAddr", state->cfg.device_addr);
    cJSON_AddNumberToObject(global, "saveState", state->save_state);

    groups = cJSON_AddArrayToObject(root, "groups");
    for (uint8_t index = 0u; index < LUMIA_GROUP_COUNT; ++index) {
        const LumiaGroupInnerConfig *group = &state->cfg.groups[index];
        cJSON *item = cJSON_CreateObject();
        cJSON_AddNumberToObject(item, "innerMode", group->inner_mode);
        cJSON_AddNumberToObject(item, "hue", group->hue);
        cJSON_AddNumberToObject(item, "sat", group->sat);
        cJSON_AddNumberToObject(item, "value", group->val);
        cJSON_AddNumberToObject(item, "innerParam", group->inner_param);
        cJSON_AddItemToArray(groups, item);
    }

    diagnostics = cJSON_AddObjectToObject(root, "diagnostics");
    cJSON_AddNumberToObject(diagnostics, "rxCount", state->rx_request_count);
    cJSON_AddNumberToObject(diagnostics, "rxOverflow", state->rx_overflow_count);
    cJSON_AddNumberToObject(diagnostics, "txDrop", state->tx_drop_count);
    cJSON_AddNumberToObject(diagnostics, "parseError", state->parse_error_count);
    cJSON_AddNumberToObject(diagnostics, "tempCx100", state->temp_c_x100);
    cJSON_AddNumberToObject(diagnostics, "vddaMv", state->vdda_mv);
    cJSON_AddNumberToObject(diagnostics, "flashSizeBytes",
                            response->flash_size_bytes);
    cJSON_AddNumberToObject(diagnostics, "appPartitionBytes",
                            response->app_partition_size_bytes);
    cJSON_AddNumberToObject(diagnostics, "ledTxErrorCount",
                            response->led_tx_error_count);
    cJSON_AddNumberToObject(diagnostics, "ledGpioSwitchErrorCount",
                            response->led_gpio_switch_error_count);
    cJSON_AddNumberToObject(diagnostics, "ledInitErrorCount",
                            response->led_init_error_count);
    cJSON_AddNumberToObject(diagnostics, "ledMaxScanGapUs",
                            response->led_max_scan_gap_us);
    return root;
}

static esp_err_t send_control_response(httpd_req_t *req,
                                       LumiaWebControlRequest *request)
{
    LumiaWebControlResponse response;
    cJSON *json;
    char *text;
    esp_err_t err = exchange_control(request, &response);

    if (err != ESP_OK) {
        return send_json_error(req, "503 Service Unavailable",
                               err == ESP_ERR_TIMEOUT
                                   ? "control request timed out"
                                   : "control service unavailable");
    }
    if (response.status != REGISTER_MAP_OK) {
        return send_json_error(req, "400 Bad Request",
                               response.status == REGISTER_MAP_ILLEGAL_ADDR
                                   ? "illegal register address"
                                   : "illegal value");
    }

    json = state_to_json(&response);
    if (json == NULL) {
        return send_json_error(req, "500 Internal Server Error",
                               "out of memory");
    }
    text = cJSON_PrintUnformatted(json);
    cJSON_Delete(json);
    if (text == NULL) {
        return send_json_error(req, "500 Internal Server Error",
                               "out of memory");
    }
    err = send_json_text(req, text, "200 OK");
    free(text);
    return err;
}

static esp_err_t api_state_handler(httpd_req_t *req)
{
    LumiaWebControlRequest request = {
        .type = LUMIA_WEB_CONTROL_READ_STATE,
    };
    return send_control_response(req, &request);
}

static esp_err_t api_scene_handler(httpd_req_t *req)
{
    LumiaWebControlRequest request = {
        .type = LUMIA_WEB_CONTROL_WRITE_SCENE,
    };
    cJSON *root = read_json_body(req);
    int mode;
    int param;

    if (root == NULL ||
        !json_required_int(root, "sceneMode", 1, 4, &mode) ||
        !json_required_int(root, "sceneParam", 0, 255, &param)) {
        cJSON_Delete(root);
        return send_json_error(req, "400 Bad Request", "invalid scene payload");
    }
    request.global.scene_mode = (uint8_t)mode;
    request.global.scene_param = (uint8_t)param;
    cJSON_Delete(root);
    return send_control_response(req, &request);
}

static esp_err_t api_global_handler(httpd_req_t *req)
{
    LumiaWebControlRequest request = {
        .type = LUMIA_WEB_CONTROL_WRITE_GLOBAL,
    };
    cJSON *root = read_json_body(req);
    int brightness;
    int gain_r;
    int gain_g;
    int gain_b;

    if (root == NULL ||
        !json_required_int(root, "globalBrightness", 0, 255, &brightness) ||
        !json_required_int(root, "gainR", 0, 255, &gain_r) ||
        !json_required_int(root, "gainG", 0, 255, &gain_g) ||
        !json_required_int(root, "gainB", 0, 255, &gain_b)) {
        cJSON_Delete(root);
        return send_json_error(req, "400 Bad Request", "invalid global payload");
    }
    request.global.global_brightness = (uint8_t)brightness;
    request.global.gain_r = (uint8_t)gain_r;
    request.global.gain_g = (uint8_t)gain_g;
    request.global.gain_b = (uint8_t)gain_b;
    cJSON_Delete(root);
    return send_control_response(req, &request);
}

static esp_err_t api_group_handler(httpd_req_t *req)
{
    const char *prefix = "/api/v1/groups/";
    const char *index_text = req->uri + strlen(prefix);
    char *end = NULL;
    long index = strtol(index_text, &end, 10);
    LumiaWebControlRequest request = {
        .type = LUMIA_WEB_CONTROL_WRITE_GROUP,
    };
    cJSON *root;

    if (end == index_text || *end != '\0' || index < 0 ||
        index >= LUMIA_GROUP_COUNT) {
        return send_json_error(req, "400 Bad Request", "invalid group index");
    }
    root = read_json_body(req);
    if (root == NULL || !parse_group(root, &request.groups[0])) {
        cJSON_Delete(root);
        return send_json_error(req, "400 Bad Request", "invalid group payload");
    }
    request.group_index = (uint8_t)index;
    cJSON_Delete(root);
    return send_control_response(req, &request);
}

static esp_err_t api_groups_handler(httpd_req_t *req)
{
    LumiaWebControlRequest request = {
        .type = LUMIA_WEB_CONTROL_WRITE_ALL_GROUPS,
    };
    cJSON *root = read_json_body(req);
    cJSON *groups = root != NULL
                        ? cJSON_GetObjectItemCaseSensitive(root, "groups")
                        : NULL;

    if (!cJSON_IsArray(groups) || cJSON_GetArraySize(groups) != LUMIA_GROUP_COUNT) {
        cJSON_Delete(root);
        return send_json_error(req, "400 Bad Request", "groups must contain 7 items");
    }
    for (uint8_t index = 0u; index < LUMIA_GROUP_COUNT; ++index) {
        if (!parse_group(cJSON_GetArrayItem(groups, index),
                         &request.groups[index])) {
            cJSON_Delete(root);
            return send_json_error(req, "400 Bad Request", "invalid group payload");
        }
    }
    cJSON_Delete(root);
    return send_control_response(req, &request);
}

static esp_err_t api_clear_handler(httpd_req_t *req)
{
    LumiaWebControlRequest request = {
        .type = LUMIA_WEB_CONTROL_CLEAR_DIAGNOSTICS,
    };
    return send_control_response(req, &request);
}

static const char *content_type_for_uri(const char *uri)
{
    if (strstr(uri, ".js") != NULL) {
        return "application/javascript; charset=utf-8";
    }
    if (strstr(uri, ".css") != NULL) {
        return "text/css; charset=utf-8";
    }
    if (strstr(uri, ".json") != NULL) {
        return "application/json; charset=utf-8";
    }
    if (strstr(uri, ".webp") != NULL) {
        return "image/webp";
    }
    if (strstr(uri, ".svg") != NULL) {
        return "image/svg+xml";
    }
    return "text/html; charset=utf-8";
}

static bool uri_path_equals(const char *uri, const char *path)
{
    size_t path_length = strlen(path);

    return strncmp(uri, path, path_length) == 0 &&
           (uri[path_length] == '\0' || uri[path_length] == '?');
}

static bool has_suffix(const char *text, const char *suffix)
{
    size_t text_length = strlen(text);
    size_t suffix_length = strlen(suffix);

    return text_length >= suffix_length &&
           strcmp(text + text_length - suffix_length, suffix) == 0;
}

static bool should_serve_gzip(const char *path)
{
    return has_suffix(path, ".html") || has_suffix(path, ".css") ||
           has_suffix(path, ".js") || has_suffix(path, ".json") ||
           has_suffix(path, ".svg");
}

static bool normalized_uri_path(const char *uri,
                                char *path,
                                size_t path_size,
                                bool *gzip_encoded)
{
    size_t uri_length = strcspn(uri, "?");

    if (uri_length == 1u && uri[0] == '/') {
        uri = "/index.html";
        uri_length = strlen(uri);
    }
    if (uri_length == 0u || uri[0] != '/' ||
        uri_length >= path_size) {
        return false;
    }
    memcpy(path, uri, uri_length);
    path[uri_length] = '\0';
    if (strstr(path, "..") != NULL || strchr(path, '\\') != NULL) {
        return false;
    }

    *gzip_encoded = should_serve_gzip(path);
    return true;
}

static esp_err_t static_handler(httpd_req_t *req)
{
    char path[WEB_STATIC_PATH_LEN];
    bool gzip_encoded = false;
    char chunk[WEB_FILE_CHUNK_LEN];
    MauryaEmbeddedResource core = {0};
    MauryaFileResource asset = {0};

    if (!normalized_uri_path(req->uri, path, sizeof(path), &gzip_encoded)) {
        httpd_resp_set_status(req, "302 Found");
        httpd_resp_set_hdr(req, "Location", "http://192.168.4.1/");
        return httpd_resp_send(req, NULL, 0);
    }
    bool found_core = maurya_resource_find_core(path, &core);
    bool found_asset = !found_core && maurya_resource_open_asset(path, &asset);
    if (!found_core && !found_asset) {
        ESP_LOGD(TAG, "asset not found, redirecting: %s", path);
        httpd_resp_set_status(req, "302 Found");
        httpd_resp_set_hdr(req, "Location", CAPTIVE_PORTAL_URI);
        return httpd_resp_send(req, NULL, 0);
    }

    httpd_resp_set_type(req, content_type_for_uri(req->uri));
    if (gzip_encoded) {
        httpd_resp_set_hdr(req, "Content-Encoding", "gzip");
    }
    httpd_resp_set_hdr(req,
                       "Cache-Control",
                       uri_path_equals(req->uri, "/")
                           ? "no-cache"
                           : "public, max-age=86400");
    if (found_core) {
        esp_err_t err = httpd_resp_send(req, (const char *)core.data,
                                        core.length);
        return err;
    }

    uint32_t remaining = asset.length;
    while (remaining > 0u) {
        size_t wanted = remaining < sizeof(chunk) ? remaining : sizeof(chunk);
        size_t count = fread(chunk, 1u, wanted, asset.file);
        if (count == 0u ||
            httpd_resp_send_chunk(req, chunk, count) != ESP_OK) {
            maurya_resource_close_asset(&asset);
            (void)httpd_resp_sendstr_chunk(req, NULL);
            return ESP_FAIL;
        }
        remaining -= (uint32_t)count;
    }
    maurya_resource_close_asset(&asset);
    return httpd_resp_send_chunk(req, NULL, 0);
}

static esp_err_t not_found_handler(httpd_req_t *req, httpd_err_code_t error)
{
    (void)error;
    if (strncmp(req->uri, "/api/", 5u) == 0) {
        return send_json_error(req, "405 Method Not Allowed", "method not allowed");
    }
    return static_handler(req);
}

static void dns_task(void *arg)
{
    uint8_t packet[512];
    struct sockaddr_in server = {
        .sin_family = AF_INET,
        .sin_port = htons(53),
        .sin_addr.s_addr = htonl(INADDR_ANY),
    };
    struct sockaddr_in client;
    socklen_t client_len;
    int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    (void)arg;

    if (sock < 0 || bind(sock, (struct sockaddr *)&server, sizeof(server)) < 0) {
        ESP_LOGE(TAG, "captive DNS start failed: errno=%d", errno);
        if (sock >= 0) {
            close(sock);
        }
        vTaskDelete(NULL);
        return;
    }

    while (1) {
        client_len = sizeof(client);
        int length = recvfrom(sock,
                              packet,
                              sizeof(packet) - 16u,
                              0,
                              (struct sockaddr *)&client,
                              &client_len);
        if (length < 17) {
            continue;
        }

        size_t question_end = 12u;
        while (question_end < (size_t)length && packet[question_end] != 0u) {
            uint8_t label_len = packet[question_end];
            question_end += (size_t)label_len + 1u;
        }
        question_end += 1u;
        if (question_end + 4u > (size_t)length ||
            packet[question_end] != 0u || packet[question_end + 1u] != 1u) {
            continue;
        }

        packet[2] = 0x81u;
        packet[3] = 0x80u;
        packet[6] = 0u;
        packet[7] = 1u;
        packet[8] = packet[9] = packet[10] = packet[11] = 0u;
        size_t offset = (size_t)length;
        const uint8_t answer[] = {
            0xC0u, 0x0Cu, 0x00u, 0x01u, 0x00u, 0x01u,
            0x00u, 0x00u, 0x00u, 0x00u, 0x00u, 0x04u,
            192u, 168u, 4u, 1u,
        };
        memcpy(packet + offset, answer, sizeof(answer));
        offset += sizeof(answer);
        (void)sendto(sock,
                     packet,
                     offset,
                     0,
                     (struct sockaddr *)&client,
                     client_len);
    }
}

static esp_err_t start_softap(void)
{
    wifi_init_config_t init_config = WIFI_INIT_CONFIG_DEFAULT();
    wifi_config_t ap_config = {0};
    esp_netif_ip_info_t ip_info = {
        .ip = {.addr = ESP_IP4TOADDR(192, 168, 4, 1)},
        .gw = {.addr = ESP_IP4TOADDR(192, 168, 4, 1)},
        .netmask = {.addr = ESP_IP4TOADDR(255, 255, 255, 0)},
    };
    esp_netif_t *ap_netif;
    uint8_t mac[6];
    uint8_t selected_channel;
    uint8_t applied_channel = 0u;
    wifi_second_chan_t secondary_channel = WIFI_SECOND_CHAN_NONE;
    size_t password_len = strlen(CONFIG_LUMIA_WIFI_AP_PASSWORD);
    esp_err_t err;

    if (password_len < 8u || password_len > 63u) {
        return ESP_ERR_INVALID_ARG;
    }
    err = esp_netif_init();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        return err;
    }
    err = esp_event_loop_create_default();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        return err;
    }
    err = esp_wifi_init(&init_config);
    if (err != ESP_OK) {
        return err;
    }
    selected_channel = select_softap_channel(CONFIG_LUMIA_WIFI_AP_CHANNEL);
    if (selected_channel == 0u) {
        return ESP_FAIL;
    }
    ap_netif = esp_netif_create_default_wifi_ap();
    if (ap_netif == NULL) {
        return ESP_FAIL;
    }
    err = esp_netif_dhcps_stop(ap_netif);
    if (err != ESP_OK && err != ESP_ERR_ESP_NETIF_DHCP_ALREADY_STOPPED) {
        return err;
    }
    err = esp_netif_set_ip_info(ap_netif, &ip_info);
    if (err != ESP_OK) {
        return err;
    }
    err = esp_netif_dhcps_option(ap_netif,
                                 ESP_NETIF_OP_SET,
                                 ESP_NETIF_CAPTIVEPORTAL_URI,
                                 (void *)CAPTIVE_PORTAL_URI,
                                 strlen(CAPTIVE_PORTAL_URI));
    if (err != ESP_OK) {
        return err;
    }
    err = esp_netif_dhcps_start(ap_netif);
    if (err != ESP_OK && err != ESP_ERR_ESP_NETIF_DHCP_ALREADY_STARTED) {
        return err;
    }
    err = esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
    if (err != ESP_OK) {
        return err;
    }
    snprintf(s_ap_ssid,
             sizeof(s_ap_ssid),
             "%s-%02X%02X",
             CONFIG_LUMIA_WIFI_AP_SSID_PREFIX,
             mac[4],
             mac[5]);

    strlcpy((char *)ap_config.ap.ssid, s_ap_ssid, sizeof(ap_config.ap.ssid));
    ap_config.ap.ssid_len = (uint8_t)strlen(s_ap_ssid);
    strlcpy((char *)ap_config.ap.password,
            CONFIG_LUMIA_WIFI_AP_PASSWORD,
            sizeof(ap_config.ap.password));
    ap_config.ap.channel = selected_channel;
    ap_config.ap.max_connection = CONFIG_LUMIA_WIFI_AP_MAX_CLIENTS;
    ap_config.ap.authmode = WIFI_AUTH_WPA2_PSK;
    ap_config.ap.pmf_cfg.required = false;

    err = esp_wifi_set_mode(WIFI_MODE_AP);
    if (err == ESP_OK) {
        err = esp_wifi_set_config(WIFI_IF_AP, &ap_config);
    }
    if (err == ESP_OK) {
        err = esp_wifi_start();
    }
    if (err == ESP_OK) {
        err = esp_wifi_get_channel(&applied_channel, &secondary_channel);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "read SoftAP channel failed: %s", esp_err_to_name(err));
        } else if (applied_channel != selected_channel) {
            ESP_LOGE(TAG,
                     "SoftAP channel mismatch: expected=%u actual=%u",
                     selected_channel,
                     applied_channel);
            err = ESP_ERR_INVALID_STATE;
        }
    }
    if (err == ESP_OK) {
        err = apply_wifi_tx_power_limit();
        if (err != ESP_OK) {
            esp_err_t stop_err = esp_wifi_stop();
            if (stop_err != ESP_OK) {
                ESP_LOGE(TAG,
                         "stop Wi-Fi after TX power setup failure failed: %s",
                         esp_err_to_name(stop_err));
            }
            return err;
        }
    }
    if (err == ESP_OK) {
        ESP_LOGI(TAG,
                 "SoftAP ready: ssid=%s ip=192.168.4.1 channel=%u",
                 s_ap_ssid,
                 applied_channel);
    } else {
        (void)esp_wifi_stop();
    }
    return err;
}

static esp_err_t mount_assetsfs(void)
{
    const esp_vfs_spiffs_conf_t config = {
        .base_path = ASSET_BASE_PATH,
        .partition_label = "assetsfs",
        .max_files = 2,
        .format_if_mount_failed = false,
    };
    return esp_vfs_spiffs_register(&config);
}

static esp_err_t start_http_server(bool ota_only)
{
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    const httpd_uri_t handlers[] = {
        {.uri = "/api/v1/state", .method = HTTP_GET, .handler = api_state_handler},
        {.uri = "/api/v1/scene", .method = HTTP_PUT, .handler = api_scene_handler},
        {.uri = "/api/v1/global", .method = HTTP_PUT, .handler = api_global_handler},
        {.uri = "/api/v1/groups", .method = HTTP_PUT, .handler = api_groups_handler},
        {.uri = "/api/v1/groups/*", .method = HTTP_PUT, .handler = api_group_handler},
        {.uri = "/api/v1/diagnostics/clear", .method = HTTP_POST, .handler = api_clear_handler},
        {.uri = "/*", .method = HTTP_GET, .handler = static_handler},
    };
    esp_err_t err;

    config.stack_size = 6144u;
    config.max_uri_handlers = 12u;
    config.uri_match_fn = httpd_uri_match_wildcard;
    err = httpd_start(&s_httpd, &config);
    if (err != ESP_OK) {
        return err;
    }
    if (ota_only) {
        return lumia_ota_service_register_http(s_httpd);
    }
    for (size_t index = 0u;
         index < sizeof(handlers) / sizeof(handlers[0]); ++index) {
        err = httpd_register_uri_handler(s_httpd, &handlers[index]);
        if (err != ESP_OK) {
            return err;
        }
    }
    return httpd_register_err_handler(s_httpd,
                                      HTTPD_404_NOT_FOUND,
                                      not_found_handler);
}

esp_err_t lumia_web_server_start(const LumiaWebServerConfig *config)
{
    esp_err_t err;

    if (config == NULL || config->exchange == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    s_config = *config;

    err = mount_assetsfs();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "assetsfs mount failed: %s", esp_err_to_name(err));
        return err;
    }
    err = maurya_resource_pack_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "resource pack validation failed: %s",
                 esp_err_to_name(err));
        return err;
    }
    err = start_softap();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "SoftAP start failed: %s", esp_err_to_name(err));
        return err;
    }
#if CONFIG_LUMIA_WIFI_CAPTIVE_DNS
    if (xTaskCreate(dns_task,
                    "captive_dns",
                    DNS_TASK_STACK_SIZE,
                    NULL,
                    DNS_TASK_PRIORITY,
                    NULL) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
#endif
    err = start_http_server(false);
    if (err == ESP_OK) {
        ESP_LOGI(TAG, "web control ready at http://192.168.4.1/");
    }
    return err;
}

esp_err_t lumia_web_server_start_ota(void)
{
    esp_err_t err = start_softap();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "OTA SoftAP start failed: %s", esp_err_to_name(err));
        return err;
    }
    err = start_http_server(true);
    if (err == ESP_OK) {
        ESP_LOGI(TAG, "OTA service ready at http://192.168.4.1/");
    }
    return err;
}

const char *lumia_web_server_ssid(void)
{
    return s_ap_ssid;
}
