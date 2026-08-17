#include "modbus_frame.h"

#include <stddef.h>

#include "modbus_crc.h"

bool modbus_frame_is_supported_function(uint8_t func)
{
    switch (func) {
        case 0x03:
        case 0x06:
        case 0x10:
        case 0x41:
            return true;
        default:
            return false;
    }
}

bool modbus_frame_is_supported_candidate(const uint8_t *data, uint16_t len)
{
    if (data == 0 || len < 4) {
        return false;
    }

    return modbus_frame_is_supported_function(data[1]);
}

ModbusFrameStatus modbus_frame_expected_request_length(const uint8_t *data, uint16_t len, uint16_t *expected_len)
{
    uint16_t frame_len;

    if (data == NULL || expected_len == NULL || len < 2) {
        return MODBUS_FRAME_UNSUPPORTED;
    }

    switch (data[1]) {
        case 0x03:
        case 0x06:
            frame_len = 8u;
            break;
        case 0x10:
            if (len < 7u) {
                return MODBUS_FRAME_INCOMPLETE;
            }
            frame_len = (uint16_t)(9u + data[6]);
            break;
        case 0x41:
            if (len < 3u) {
                return MODBUS_FRAME_INCOMPLETE;
            }
            frame_len = (uint16_t)(5u + data[2]);
            break;
        default:
            return MODBUS_FRAME_UNSUPPORTED;
    }

    *expected_len = frame_len;
    return len >= frame_len ? MODBUS_FRAME_COMPLETE : MODBUS_FRAME_INCOMPLETE;
}

bool modbus_frame_crc_ok(const uint8_t *data, uint16_t len)
{
    if (data == 0 || len < 4) {
        return false;
    }

    uint16_t actual = modbus_crc16(data, (uint16_t)(len - 2));
    uint16_t expected = (uint16_t)data[len - 2] | ((uint16_t)data[len - 1] << 8);
    return actual == expected;
}
