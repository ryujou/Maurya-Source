#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "esp_err.h"

typedef struct {
    const uint8_t *data;
    size_t length;
} MauryaEmbeddedResource;

typedef struct {
    FILE *file;
    uint32_t offset;
    uint32_t length;
} MauryaFileResource;

esp_err_t maurya_resource_pack_init(void);
bool maurya_resource_find_core(const char *uri,
                               MauryaEmbeddedResource *resource);
bool maurya_resource_open_asset(const char *uri,
                                MauryaFileResource *resource);
void maurya_resource_close_asset(MauryaFileResource *resource);
