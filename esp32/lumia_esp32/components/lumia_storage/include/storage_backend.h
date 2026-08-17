#pragma once

#include <stddef.h>

#include "esp_err.h"

esp_err_t storage_backend_init(void);
size_t storage_backend_size(void);
esp_err_t storage_backend_read(size_t offset, void *data, size_t length);
esp_err_t storage_backend_write(size_t offset, const void *data, size_t length);
esp_err_t storage_backend_erase(size_t offset, size_t length);
