#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "modbus_crc.h"
#include "modbus_server.h"
#include "register_map.h"
#include "runtime_state.h"
#include "ble_transport.h"
#include "modbus_frame.h"

static void append_crc(uint8_t *frame, uint16_t payload_length)
{
    uint16_t crc = modbus_crc16(frame, payload_length);
    frame[payload_length] = (uint8_t)crc;
    frame[payload_length + 1u] = (uint8_t)(crc >> 8u);
}

static void test_register_map(void)
{
    uint16_t values[22];

    runtime_state_init();
    register_map_init();
    assert(register_map_read_holding(0x0000u, 22u, values) ==
           REGISTER_MAP_OK);
    assert(values[0] == 1u);
    assert(values[1] == 80u);
    assert(values[2] == 255u);
    assert(values[3] == 255u);
    assert(values[5] == 240u);
    assert(values[9] == 0u);
    assert(values[11] == 1u);
    assert(values[17] == 3300u);
    assert(register_map_write_single(LUMIA_REG_SCENE_MODE, 0u) ==
           REGISTER_MAP_ILLEGAL_VALUE);
    assert(register_map_write_single(LUMIA_REG_CFG_SAVE_STATE, 1u) ==
           REGISTER_MAP_ILLEGAL_ADDR);
}

static void test_diagnostics_and_telemetry(void)
{
    uint16_t values[4];

    runtime_state_note_rx_request();
    runtime_state_note_rx_overflow();
    runtime_state_note_tx_drop();
    runtime_state_note_parse_error();
    assert(register_map_read_holding(LUMIA_REG_UART_RX_COUNT,
                                     4u,
                                     values) == REGISTER_MAP_OK);
    assert(values[0] == 1u && values[1] == 1u &&
           values[2] == 1u && values[3] == 1u);
    assert(register_map_write_single(LUMIA_REG_UART_PARSE_ERROR,
                                     LUMIA_DIAG_CLEAR_KEY) ==
           REGISTER_MAP_OK);
    assert(register_map_read_holding(LUMIA_REG_UART_RX_COUNT,
                                     4u,
                                     values) == REGISTER_MAP_OK);
    assert(values[0] == 0u && values[1] == 0u &&
           values[2] == 0u && values[3] == 0u);

    runtime_state_set_telemetry(-500, 3300u);
    assert(register_map_read_holding(LUMIA_REG_TEMP_C_X100,
                                     2u,
                                     values) == REGISTER_MAP_OK);
    assert((int16_t)values[0] == -500);
    assert(values[1] == 3300u);
}

static void test_device_address_transition(void)
{
    uint8_t request[8] = {
        1u, 0x06u, 0x00u, 0x0Bu, 0x00u, 0x02u, 0u, 0u,
    };
    uint8_t response[MODBUS_SERVER_MAX_RESPONSE_LEN];
    uint16_t response_length = 0u;

    modbus_server_init();
    append_crc(request, 6u);
    assert(modbus_server_handle_request(request,
                                        sizeof(request),
                                        response,
                                        sizeof(response),
                                        &response_length) ==
           MODBUS_SERVER_OK);
    assert(response_length == sizeof(request));
    assert(memcmp(response, request, sizeof(request)) == 0);
    assert(runtime_state_get_device_addr() == 2u);

    request[0] = 1u;
    request[1] = 0x03u;
    request[2] = 0x00u;
    request[3] = 0x0Bu;
    request[4] = 0x00u;
    request[5] = 0x01u;
    append_crc(request, 6u);
    assert(modbus_server_handle_request(request,
                                        sizeof(request),
                                        response,
                                        sizeof(response),
                                        &response_length) ==
           MODBUS_SERVER_NO_RESPONSE);

    request[0] = 2u;
    append_crc(request, 6u);
    assert(modbus_server_handle_request(request,
                                        sizeof(request),
                                        response,
                                        sizeof(response),
                                        &response_length) ==
           MODBUS_SERVER_OK);
    assert(response[0] == 2u);
    assert(response[3] == 0u && response[4] == 2u);
}

static void test_group_block_modbus_access(void)
{
    uint8_t read_request[8] = {
        1u, 0x03u, 0x00u, 0x20u, 0x00u, 0x23u, 0u, 0u,
    };
    uint8_t write_request[79];
    uint8_t response[MODBUS_SERVER_MAX_RESPONSE_LEN];
    uint16_t response_length = 0u;

    runtime_state_init();
    register_map_init();
    modbus_server_init();

    append_crc(read_request, 6u);
    assert(modbus_server_handle_request(read_request,
                                        sizeof(read_request),
                                        response,
                                        sizeof(response),
                                        &response_length) ==
           MODBUS_SERVER_OK);
    assert(response_length == 75u);
    assert(response[0] == 1u);
    assert(response[1] == 0x03u);
    assert(response[2] == 70u);

    write_request[0] = 1u;
    write_request[1] = 0x10u;
    write_request[2] = 0x00u;
    write_request[3] = 0x20u;
    write_request[4] = 0x00u;
    write_request[5] = 0x23u;
    write_request[6] = 70u;
    for (uint16_t group = 0u; group < 7u; ++group) {
        uint16_t base = (uint16_t)(7u + group * 10u);
        uint16_t inner_mode = (uint16_t)((group % 4u) + 1u);
        uint16_t hue = (uint16_t)(group * 30u);
        uint16_t sat = 200u;
        uint16_t val = (uint16_t)(180u + group);
        uint16_t inner_param = (uint16_t)(80u + group);

        write_request[base + 0u] = (uint8_t)(inner_mode >> 8u);
        write_request[base + 1u] = (uint8_t)(inner_mode & 0xFFu);
        write_request[base + 2u] = (uint8_t)(hue >> 8u);
        write_request[base + 3u] = (uint8_t)(hue & 0xFFu);
        write_request[base + 4u] = (uint8_t)(sat >> 8u);
        write_request[base + 5u] = (uint8_t)(sat & 0xFFu);
        write_request[base + 6u] = (uint8_t)(val >> 8u);
        write_request[base + 7u] = (uint8_t)(val & 0xFFu);
        write_request[base + 8u] = (uint8_t)(inner_param >> 8u);
        write_request[base + 9u] = (uint8_t)(inner_param & 0xFFu);
    }
    append_crc(write_request, 77u);
    assert(modbus_server_handle_request(write_request,
                                        sizeof(write_request),
                                        response,
                                        sizeof(response),
                                        &response_length) ==
           MODBUS_SERVER_OK);
    assert(response_length == 8u);
    assert(response[1] == 0x10u);
    assert(response[2] == 0x00u && response[3] == 0x20u);
    assert(response[4] == 0x00u && response[5] == 0x23u);
}

static void test_group_block_write_is_atomic(void)
{
    uint16_t values[LUMIA_GROUP_COUNT * LUMIA_REG_GROUP_STRIDE];
    const RuntimeState *before;
    PersistentConfig snapshot;

    runtime_state_init();
    register_map_init();
    before = runtime_state_get();
    snapshot = before->cfg;

    for (uint16_t group = 0u; group < LUMIA_GROUP_COUNT; ++group) {
        uint16_t base = (uint16_t)(group * LUMIA_REG_GROUP_STRIDE);
        values[base + 0u] = 2u;
        values[base + 1u] = (uint16_t)(group * 30u);
        values[base + 2u] = 200u;
        values[base + 3u] = 180u;
        values[base + 4u] = 90u;
    }
    values[LUMIA_GROUP_COUNT * LUMIA_REG_GROUP_STRIDE - 4u] = 360u;

    assert(register_map_write_multiple(LUMIA_REG_GROUP_BASE,
                                       LUMIA_GROUP_COUNT * LUMIA_REG_GROUP_STRIDE,
                                       values) == REGISTER_MAP_ILLEGAL_VALUE);
    assert(memcmp(&runtime_state_get()->cfg, &snapshot, sizeof(snapshot)) == 0);
}

static void test_ble_transport_frame_budget(void)
{
    uint8_t pixel_frame_prefix[] = {1u, 0x41u, 135u};
    uint16_t expected_len = 0u;

    assert(modbus_frame_expected_request_length(
               pixel_frame_prefix, sizeof(pixel_frame_prefix),
               &expected_len) == MODBUS_FRAME_INCOMPLETE);
    assert(expected_len == 140u);
    assert(BLE_TRANSPORT_MAX_FRAME_LEN >= expected_len);
    assert(BLE_TRANSPORT_RX_BUFFER_CAP >= BLE_TRANSPORT_MAX_FRAME_LEN);
}

int main(void)
{
    test_register_map();
    test_diagnostics_and_telemetry();
    test_device_address_transition();
    test_group_block_modbus_access();
    test_group_block_write_is_atomic();
    test_ble_transport_frame_budget();
    puts("protocol/runtime host tests passed");
    return 0;
}
