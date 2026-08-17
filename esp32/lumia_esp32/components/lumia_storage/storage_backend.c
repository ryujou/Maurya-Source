#include "storage_backend.h"

#include <stdint.h>

#include "esp_partition.h"

#define LUMIA_CONFIG_PARTITION_LABEL    "lumiacfg"
#define LUMIA_CONFIG_PARTITION_SUBTYPE  0x40u

static const esp_partition_t *s_partition;

esp_err_t storage_backend_init(void)
{
    s_partition = esp_partition_find_first(
        ESP_PARTITION_TYPE_DATA,
        LUMIA_CONFIG_PARTITION_SUBTYPE,
        LUMIA_CONFIG_PARTITION_LABEL);
    return s_partition != NULL ? ESP_OK : ESP_ERR_NOT_FOUND;
}

size_t storage_backend_size(void)
{
    return s_partition != NULL ? s_partition->size : 0u;
}

esp_err_t storage_backend_read(size_t offset, void *data, size_t length)
{
    if (s_partition == NULL) {
        return ESP_ERR_INVALID_STATE;
    }
    if (data == NULL || offset > s_partition->size ||
        length > s_partition->size - offset) {
        return ESP_ERR_INVALID_ARG;
    }
    return esp_partition_read(s_partition, offset, data, length);
}

esp_err_t storage_backend_write(size_t offset, const void *data, size_t length)
{
    if (s_partition == NULL) {
        return ESP_ERR_INVALID_STATE;
    }
    if (data == NULL || offset > s_partition->size ||
        length > s_partition->size - offset) {
        return ESP_ERR_INVALID_ARG;
    }
    return esp_partition_write(s_partition, offset, data, length);
}

esp_err_t storage_backend_erase(size_t offset, size_t length)
{
    if (s_partition == NULL) {
        return ESP_ERR_INVALID_STATE;
    }
    if (offset > s_partition->size || length > s_partition->size - offset) {
        return ESP_ERR_INVALID_ARG;
    }
    return esp_partition_erase_range(s_partition, offset, length);
}
