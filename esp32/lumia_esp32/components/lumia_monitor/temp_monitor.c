#include "temp_monitor.h"

#include <limits.h>
#include <stdbool.h>

#include "driver/temperature_sensor.h"

#define TEMP_IIR_DENOMINATOR  10

static temperature_sensor_handle_t s_sensor;
static int32_t s_filtered_temp_x100;
static bool s_filter_valid;

esp_err_t temp_monitor_init(void)
{
    const temperature_sensor_config_t config =
        TEMPERATURE_SENSOR_CONFIG_DEFAULT(10, 50);
    esp_err_t err = temperature_sensor_install(&config, &s_sensor);

    if (err != ESP_OK) {
        s_sensor = NULL;
        return err;
    }
    err = temperature_sensor_enable(s_sensor);
    if (err != ESP_OK) {
        (void)temperature_sensor_uninstall(s_sensor);
        s_sensor = NULL;
        return err;
    }
    return ESP_OK;
}

esp_err_t temp_monitor_sample(int16_t *temp_c_x100, uint16_t *vdda_mv)
{
    float celsius;

    if (temp_c_x100 == NULL || vdda_mv == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    if (s_sensor == NULL) {
        return ESP_ERR_INVALID_STATE;
    }

    esp_err_t err = temperature_sensor_get_celsius(s_sensor, &celsius);
    if (err != ESP_OK) {
        return err;
    }

    int32_t sample = celsius >= 0.0f
        ? (int32_t)(celsius * 100.0f + 0.5f)
        : (int32_t)(celsius * 100.0f - 0.5f);
    if (!s_filter_valid) {
        s_filtered_temp_x100 = sample;
        s_filter_valid = true;
    } else {
        s_filtered_temp_x100 +=
            (sample - s_filtered_temp_x100) / TEMP_IIR_DENOMINATOR;
    }
    if (s_filtered_temp_x100 > INT16_MAX) {
        s_filtered_temp_x100 = INT16_MAX;
    } else if (s_filtered_temp_x100 < INT16_MIN) {
        s_filtered_temp_x100 = INT16_MIN;
    }

    *temp_c_x100 = (int16_t)s_filtered_temp_x100;
    *vdda_mv = LUMIA_NOMINAL_VDDA_MV;
    return ESP_OK;
}
