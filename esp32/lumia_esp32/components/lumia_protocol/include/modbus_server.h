#pragma once

#include <stdbool.h>
#include <stdint.h>

#define MODBUS_SERVER_MAX_REG_COUNT     64u
#define MODBUS_SERVER_MAX_RESPONSE_LEN  160u

typedef enum {
    MODBUS_SERVER_OK = 0,
    MODBUS_SERVER_NO_RESPONSE,
    MODBUS_SERVER_BAD_REQUEST,
    MODBUS_SERVER_CRC_ERROR,
} ModbusServerStatus;

void modbus_server_init(void);
ModbusServerStatus modbus_server_handle_request(const uint8_t *request,
                                                uint16_t request_len,
                                                uint8_t *response,
                                                uint16_t response_cap,
                                                uint16_t *response_len);
bool modbus_server_build_exception(uint8_t addr, uint8_t func, uint8_t code, uint8_t *out, uint16_t out_cap, uint16_t *out_len);
