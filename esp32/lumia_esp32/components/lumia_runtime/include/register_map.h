#pragma once

#include <stdbool.h>
#include <stdint.h>

#define LUMIA_REG_SCENE_MODE        0x0000u
#define LUMIA_REG_SCENE_PARAM       0x0001u
#define LUMIA_REG_LED_GLOBAL_BRI    0x0002u
#define LUMIA_REG_LED_GAIN_R        0x0003u
#define LUMIA_REG_LED_GAIN_G        0x0004u
#define LUMIA_REG_LED_GAIN_B        0x0005u
#define LUMIA_REG_RESERVED_0009     0x0009u
#define LUMIA_REG_CFG_SAVE_STATE    0x000Au
#define LUMIA_REG_DEVICE_ADDR       0x000Bu
#define LUMIA_REG_UART_RX_COUNT     0x000Cu
#define LUMIA_REG_UART_RX_OVERFLOW  0x000Du
#define LUMIA_REG_UART_TX_DROP      0x000Eu
#define LUMIA_REG_UART_PARSE_ERROR  0x000Fu
#define LUMIA_REG_TEMP_C_X100       0x0010u
#define LUMIA_REG_VDDA_MV           0x0011u
#define LUMIA_REG_GROUP_BASE        0x0020u
#define LUMIA_REG_GROUP_STRIDE      0x0005u
#define LUMIA_REG_GROUP_COUNT       7u
#define LUMIA_REG_GROUP_END         0x0043u

#define LUMIA_DIAG_CLEAR_KEY        0xA55Au

typedef enum {
    REGISTER_MAP_OK = 0,
    REGISTER_MAP_ILLEGAL_ADDR,
    REGISTER_MAP_ILLEGAL_VALUE,
} RegisterMapStatus;

void register_map_init(void);
bool register_map_is_range_supported(uint16_t start_reg, uint16_t count);
RegisterMapStatus register_map_read_holding(uint16_t start_reg, uint16_t count, uint16_t *out_values);
RegisterMapStatus register_map_write_single(uint16_t reg, uint16_t value);
RegisterMapStatus register_map_write_multiple(uint16_t start_reg, uint16_t count, const uint16_t *values);
