#include "modbus_server.h"

#include <stddef.h>

#include "modbus_crc.h"
#include "modbus_frame.h"
#include "register_map.h"
#include "runtime_state.h"

static uint8_t map_exception(RegisterMapStatus status)
{
    return status == REGISTER_MAP_ILLEGAL_ADDR ? 0x02u : 0x03u;
}

static bool build_crc16_suffix(uint8_t *response, uint16_t payload_len, uint16_t response_cap, uint16_t *response_len)
{
    uint16_t crc;

    if (response == NULL || response_len == NULL || (uint16_t)(payload_len + 2u) > response_cap) {
        return false;
    }

    crc = modbus_crc16(response, payload_len);
    response[payload_len] = (uint8_t)(crc & 0xFFu);
    response[payload_len + 1u] = (uint8_t)(crc >> 8u);
    *response_len = (uint16_t)(payload_len + 2u);
    return true;
}

void modbus_server_init(void)
{
}

static ModbusServerStatus handle_read_holding(const uint8_t *request,
                                              uint8_t *response,
                                              uint16_t response_cap,
                                              uint16_t *response_len)
{
    uint16_t start_reg;
    uint16_t count;
    uint16_t values[MODBUS_SERVER_MAX_REG_COUNT];
    uint16_t index;
    RegisterMapStatus reg_status;

    start_reg = (uint16_t)(((uint16_t)request[2] << 8u) | request[3]);
    count = (uint16_t)(((uint16_t)request[4] << 8u) | request[5]);
    if (count == 0u || count > MODBUS_SERVER_MAX_REG_COUNT) {
        modbus_server_build_exception(request[0], request[1], 0x03u, response, response_cap, response_len);
        return MODBUS_SERVER_OK;
    }

    reg_status = register_map_read_holding(start_reg, count, values);
    if (reg_status != REGISTER_MAP_OK) {
        modbus_server_build_exception(request[0], request[1], map_exception(reg_status), response, response_cap, response_len);
        return MODBUS_SERVER_OK;
    }

    if ((uint16_t)(3u + count * 2u + 2u) > response_cap) {
        return MODBUS_SERVER_BAD_REQUEST;
    }

    response[0] = request[0];
    response[1] = request[1];
    response[2] = (uint8_t)(count * 2u);
    for (index = 0u; index < count; ++index) {
        response[3u + index * 2u] = (uint8_t)(values[index] >> 8u);
        response[4u + index * 2u] = (uint8_t)(values[index] & 0xFFu);
    }

    build_crc16_suffix(response, (uint16_t)(3u + count * 2u), response_cap, response_len);
    return MODBUS_SERVER_OK;
}

static ModbusServerStatus handle_write_single(const uint8_t *request,
                                              uint8_t *response,
                                              uint16_t response_cap,
                                              uint16_t *response_len)
{
    uint16_t reg = (uint16_t)(((uint16_t)request[2] << 8u) | request[3]);
    uint16_t value = (uint16_t)(((uint16_t)request[4] << 8u) | request[5]);
    RegisterMapStatus reg_status = register_map_write_single(reg, value);

    if (reg_status != REGISTER_MAP_OK) {
        modbus_server_build_exception(request[0], request[1], map_exception(reg_status), response, response_cap, response_len);
        return MODBUS_SERVER_OK;
    }

    if (response_cap < 8u) {
        return MODBUS_SERVER_BAD_REQUEST;
    }

    for (uint16_t index = 0u; index < 8u; ++index) {
        response[index] = request[index];
    }
    *response_len = 8u;
    return MODBUS_SERVER_OK;
}

static ModbusServerStatus handle_write_multiple(const uint8_t *request,
                                                uint16_t request_len,
                                                uint8_t *response,
                                                uint16_t response_cap,
                                                uint16_t *response_len)
{
    uint16_t start_reg;
    uint16_t count;
    uint8_t byte_count;
    uint16_t values[MODBUS_SERVER_MAX_REG_COUNT];
    uint16_t index;
    RegisterMapStatus reg_status;

    start_reg = (uint16_t)(((uint16_t)request[2] << 8u) | request[3]);
    count = (uint16_t)(((uint16_t)request[4] << 8u) | request[5]);
    byte_count = request[6];
    if (count == 0u ||
        count > MODBUS_SERVER_MAX_REG_COUNT ||
        byte_count != (uint8_t)(count * 2u) ||
        request_len != (uint16_t)(9u + byte_count)) {
        modbus_server_build_exception(request[0], request[1], 0x03u, response, response_cap, response_len);
        return MODBUS_SERVER_OK;
    }

    for (index = 0u; index < count; ++index) {
        values[index] = (uint16_t)(((uint16_t)request[7u + index * 2u] << 8u) | request[8u + index * 2u]);
    }

    reg_status = register_map_write_multiple(start_reg, count, values);
    if (reg_status != REGISTER_MAP_OK) {
        modbus_server_build_exception(request[0], request[1], map_exception(reg_status), response, response_cap, response_len);
        return MODBUS_SERVER_OK;
    }

    if (response_cap < 8u) {
        return MODBUS_SERVER_BAD_REQUEST;
    }

    response[0] = request[0];
    response[1] = request[1];
    response[2] = request[2];
    response[3] = request[3];
    response[4] = request[4];
    response[5] = request[5];
    build_crc16_suffix(response, 6u, response_cap, response_len);
    return MODBUS_SERVER_OK;
}

ModbusServerStatus modbus_server_handle_request(const uint8_t *request,
                                                uint16_t request_len,
                                                uint8_t *response,
                                                uint16_t response_cap,
                                                uint16_t *response_len)
{
    uint16_t expected_len;
    ModbusFrameStatus frame_status;

    if (request == NULL || response == NULL || response_len == NULL) {
        return MODBUS_SERVER_BAD_REQUEST;
    }

    *response_len = 0u;
    frame_status = modbus_frame_expected_request_length(request, request_len, &expected_len);
    if (frame_status != MODBUS_FRAME_COMPLETE || expected_len != request_len) {
        return MODBUS_SERVER_BAD_REQUEST;
    }

    if (request[0] != runtime_state_get_device_addr()) {
        return MODBUS_SERVER_NO_RESPONSE;
    }

    if (!modbus_frame_crc_ok(request, request_len)) {
        return MODBUS_SERVER_CRC_ERROR;
    }

    switch (request[1]) {
        case 0x03:
            return handle_read_holding(request, response, response_cap, response_len);
        case 0x06:
            return handle_write_single(request, response, response_cap, response_len);
        case 0x10:
            return handle_write_multiple(request, request_len, response, response_cap, response_len);
        default:
            modbus_server_build_exception(request[0], request[1], 0x03u, response, response_cap, response_len);
            return MODBUS_SERVER_OK;
    }
}

bool modbus_server_build_exception(uint8_t addr, uint8_t func, uint8_t code, uint8_t *out, uint16_t out_cap, uint16_t *out_len)
{
    if (out == 0 || out_len == 0 || out_cap < 5) {
        return false;
    }

    out[0] = addr;
    out[1] = (uint8_t)(func | 0x80u);
    out[2] = code;

    uint16_t crc = modbus_crc16(out, 3);
    out[3] = (uint8_t)(crc & 0xFFu);
    out[4] = (uint8_t)(crc >> 8u);
    *out_len = 5;
    return true;
}
