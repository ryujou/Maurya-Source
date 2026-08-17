#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"
#include "runtime_state.h"

#define CONFIG_STORE_SLOT_SIZE      4096u
#define CONFIG_STORE_RECORD_SIZE    128u
#define CONFIG_STORE_PAYLOAD_SIZE   80u

esp_err_t config_store_init(void);
esp_err_t config_store_load(PersistentConfig *config, bool *found);
esp_err_t config_store_save(const PersistentConfig *config);
int config_store_active_slot(void);
uint32_t config_store_active_sequence(void);
