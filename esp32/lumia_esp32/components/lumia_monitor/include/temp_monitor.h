#pragma once

#include <stdint.h>

#include "esp_err.h"

#define LUMIA_NOMINAL_VDDA_MV  3300u

esp_err_t temp_monitor_init(void);
esp_err_t temp_monitor_sample(int16_t *temp_c_x100, uint16_t *vdda_mv);
