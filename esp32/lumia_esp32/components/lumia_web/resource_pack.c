#include "resource_pack.h"

#include <string.h>

#include "esp_log.h"

#define RESOURCE_MAGIC        "MRPK"
#define RESOURCE_VERSION      1u
#define RESOURCE_HEADER_SIZE  44u
#define RESOURCE_RECORD_SIZE  42u
#define ASSET_PACK_PATH       "/assets/assets.pack"

extern const uint8_t web_core_pack_start[]
    asm("_binary_web_core_pack_start");
extern const uint8_t web_core_pack_end[]
    asm("_binary_web_core_pack_end");

static const char *TAG = "resource_pack";

static uint16_t read_u16(const uint8_t *data)
{
    return (uint16_t)data[0] | ((uint16_t)data[1] << 8u);
}

static uint32_t read_u32(const uint8_t *data)
{
    return (uint32_t)data[0] |
           ((uint32_t)data[1] << 8u) |
           ((uint32_t)data[2] << 16u) |
           ((uint32_t)data[3] << 24u);
}

static bool valid_header(const uint8_t *data, size_t length)
{
    return data != NULL && length >= RESOURCE_HEADER_SIZE &&
           memcmp(data, RESOURCE_MAGIC, 4u) == 0 &&
           read_u16(data + 4u) == RESOURCE_VERSION &&
           read_u32(data + 8u) >= RESOURCE_HEADER_SIZE &&
           read_u32(data + 8u) <= length;
}

static bool uri_matches(const uint8_t *path,
                        uint16_t path_len,
                        const char *uri)
{
    size_t uri_len = strlen(uri);
    return uri_len == path_len && memcmp(path, uri, path_len) == 0;
}

esp_err_t maurya_resource_pack_init(void)
{
    size_t core_length = (size_t)(web_core_pack_end - web_core_pack_start);
    if (!valid_header(web_core_pack_start, core_length)) {
        return ESP_ERR_INVALID_CRC;
    }

    FILE *file = fopen(ASSET_PACK_PATH, "rb");
    if (file == NULL) {
        return ESP_ERR_NOT_FOUND;
    }
    uint8_t header[RESOURCE_HEADER_SIZE];
    size_t read = fread(header, 1u, sizeof(header), file);
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return ESP_FAIL;
    }
    long file_size = ftell(file);
    fclose(file);
    if (read != sizeof(header) || file_size < 0 ||
        !valid_header(header, (size_t)file_size)) {
        return ESP_ERR_INVALID_CRC;
    }
    ESP_LOGI(TAG, "resource packs ready: core=%u assets=%ld",
             (unsigned)core_length, file_size);
    return ESP_OK;
}

bool maurya_resource_find_core(const char *uri,
                               MauryaEmbeddedResource *resource)
{
    const uint8_t *cursor = web_core_pack_start + RESOURCE_HEADER_SIZE;
    const uint8_t *end = web_core_pack_end;
    uint16_t count;

    if (uri == NULL || resource == NULL ||
        !valid_header(web_core_pack_start,
                      (size_t)(web_core_pack_end - web_core_pack_start))) {
        return false;
    }
    count = read_u16(web_core_pack_start + 6u);
    for (uint16_t index = 0u; index < count; ++index) {
        if ((size_t)(end - cursor) < RESOURCE_RECORD_SIZE) {
            return false;
        }
        uint16_t path_len = read_u16(cursor);
        uint32_t offset = read_u32(cursor + 2u);
        uint32_t length = read_u32(cursor + 6u);
        const uint8_t *path = cursor + RESOURCE_RECORD_SIZE;
        if ((size_t)(end - path) < path_len ||
            (uint64_t)offset + length >
                (uint64_t)(web_core_pack_end - web_core_pack_start)) {
            return false;
        }
        if (uri_matches(path, path_len, uri)) {
            resource->data = web_core_pack_start + offset;
            resource->length = length;
            return true;
        }
        cursor = path + path_len;
    }
    return false;
}

bool maurya_resource_open_asset(const char *uri,
                                MauryaFileResource *resource)
{
    uint8_t header[RESOURCE_HEADER_SIZE];
    uint8_t record[RESOURCE_RECORD_SIZE];
    char path[192];
    FILE *file;

    if (uri == NULL || resource == NULL) {
        return false;
    }
    file = fopen(ASSET_PACK_PATH, "rb");
    if (file == NULL ||
        fread(header, 1u, sizeof(header), file) != sizeof(header)) {
        if (file != NULL) {
            fclose(file);
        }
        return false;
    }
    uint16_t count = read_u16(header + 6u);
    for (uint16_t index = 0u; index < count; ++index) {
        if (fread(record, 1u, sizeof(record), file) != sizeof(record)) {
            fclose(file);
            return false;
        }
        uint16_t path_len = read_u16(record);
        if (path_len == 0u || path_len >= sizeof(path) ||
            fread(path, 1u, path_len, file) != path_len) {
            fclose(file);
            return false;
        }
        path[path_len] = '\0';
        if (strcmp(path, uri) == 0) {
            resource->file = file;
            resource->offset = read_u32(record + 2u);
            resource->length = read_u32(record + 6u);
            if (fseek(file, (long)resource->offset, SEEK_SET) != 0) {
                fclose(file);
                memset(resource, 0, sizeof(*resource));
                return false;
            }
            return true;
        }
    }
    fclose(file);
    return false;
}

void maurya_resource_close_asset(MauryaFileResource *resource)
{
    if (resource != NULL && resource->file != NULL) {
        fclose(resource->file);
        memset(resource, 0, sizeof(*resource));
    }
}
