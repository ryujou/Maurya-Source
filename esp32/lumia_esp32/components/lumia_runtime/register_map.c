#include "register_map.h"

#include <string.h>

#include "runtime_state.h"

#define CONFIG_REG_END_EXCLUSIVE  0x0016u
#define GROUP_REG_END_EXCLUSIVE   LUMIA_REG_GROUP_END

static bool is_group_register(uint16_t reg)
{
    return reg >= LUMIA_REG_GROUP_BASE && reg < GROUP_REG_END_EXCLUSIVE;
}

static bool decode_group_register(uint16_t reg,
                                  uint8_t *group_index,
                                  uint8_t *field_index)
{
    uint16_t offset;

    if (!is_group_register(reg)) {
        return false;
    }

    offset = (uint16_t)(reg - LUMIA_REG_GROUP_BASE);
    if ((offset % LUMIA_REG_GROUP_STRIDE) >= 5u) {
        return false;
    }

    *group_index = (uint8_t)(offset / LUMIA_REG_GROUP_STRIDE);
    *field_index = (uint8_t)(offset % LUMIA_REG_GROUP_STRIDE);
    return *group_index < LUMIA_GROUP_COUNT;
}

static bool is_range_in_region(uint16_t start_reg,
                               uint16_t count,
                               uint16_t region_start,
                               uint16_t region_end_exclusive)
{
    uint32_t end_reg;

    if (count == 0u) {
        return false;
    }

    end_reg = (uint32_t)start_reg + count;
    return start_reg >= region_start && end_reg <= region_end_exclusive;
}

static bool is_read_only_reg(uint16_t reg)
{
    switch (reg) {
        case LUMIA_REG_CFG_SAVE_STATE:
        case LUMIA_REG_UART_RX_COUNT:
        case LUMIA_REG_UART_RX_OVERFLOW:
        case LUMIA_REG_UART_TX_DROP:
        case LUMIA_REG_TEMP_C_X100:
        case LUMIA_REG_VDDA_MV:
            return true;
        default:
            return false;
    }
}

static RegisterMapStatus validate_value(uint16_t reg, uint16_t value)
{
    uint8_t group_index;
    uint8_t field_index;

    if (decode_group_register(reg, &group_index, &field_index)) {
        switch (field_index) {
            case 0u:
                return (value >= 1u && value <= 4u)
                           ? REGISTER_MAP_OK
                           : REGISTER_MAP_ILLEGAL_VALUE;
            case 1u:
                return value <= 359u ? REGISTER_MAP_OK
                                     : REGISTER_MAP_ILLEGAL_VALUE;
            case 2u:
            case 3u:
            case 4u:
                return value <= 255u ? REGISTER_MAP_OK
                                     : REGISTER_MAP_ILLEGAL_VALUE;
            default:
                return REGISTER_MAP_ILLEGAL_ADDR;
        }
    }

    switch (reg) {
        case LUMIA_REG_SCENE_MODE:
            return (value >= 1u && value <= 4u)
                       ? REGISTER_MAP_OK
                       : REGISTER_MAP_ILLEGAL_VALUE;
        case LUMIA_REG_SCENE_PARAM:
        case LUMIA_REG_LED_GLOBAL_BRI:
        case LUMIA_REG_LED_GAIN_R:
        case LUMIA_REG_LED_GAIN_G:
        case LUMIA_REG_LED_GAIN_B:
            return value <= 255u ? REGISTER_MAP_OK : REGISTER_MAP_ILLEGAL_VALUE;
        case LUMIA_REG_RESERVED_0009:
            return value <= 255u ? REGISTER_MAP_OK : REGISTER_MAP_ILLEGAL_VALUE;
        case LUMIA_REG_DEVICE_ADDR:
            return (value >= 1u && value <= 247u) ? REGISTER_MAP_OK : REGISTER_MAP_ILLEGAL_VALUE;
        case LUMIA_REG_UART_PARSE_ERROR:
            return value == LUMIA_DIAG_CLEAR_KEY ? REGISTER_MAP_OK : REGISTER_MAP_ILLEGAL_VALUE;
        default:
            return REGISTER_MAP_ILLEGAL_ADDR;
    }
}

static uint16_t read_register(uint16_t reg, const RuntimeState *state)
{
    uint8_t group_index;
    uint8_t field_index;

    if (decode_group_register(reg, &group_index, &field_index)) {
        const LumiaGroupInnerConfig *group = &state->cfg.groups[group_index];

        switch (field_index) {
            case 0u:
                return group->inner_mode;
            case 1u:
                return group->hue;
            case 2u:
                return group->sat;
            case 3u:
                return group->val;
            case 4u:
                return group->inner_param;
            default:
                return 0u;
        }
    }

    switch (reg) {
        case LUMIA_REG_SCENE_MODE:
            return state->cfg.scene_mode;
        case LUMIA_REG_SCENE_PARAM:
            return state->cfg.scene_param;
        case 0x0006u:
        case 0x0007u:
        case 0x0008u:
            return 0u;
        case LUMIA_REG_RESERVED_0009:
            return 0u;
        case LUMIA_REG_CFG_SAVE_STATE:
            return state->save_state;
        case LUMIA_REG_DEVICE_ADDR:
            return state->cfg.device_addr;
        case LUMIA_REG_UART_RX_COUNT:
            return (uint16_t)state->rx_request_count;
        case LUMIA_REG_UART_RX_OVERFLOW:
            return (uint16_t)state->rx_overflow_count;
        case LUMIA_REG_UART_TX_DROP:
            return (uint16_t)state->tx_drop_count;
        case LUMIA_REG_UART_PARSE_ERROR:
            return (uint16_t)state->parse_error_count;
        case LUMIA_REG_TEMP_C_X100:
            return (uint16_t)state->temp_c_x100;
        case LUMIA_REG_VDDA_MV:
            return state->vdda_mv;
        case LUMIA_REG_LED_GLOBAL_BRI:
            return state->cfg.led_global_bri;
        case LUMIA_REG_LED_GAIN_R:
            return state->cfg.led_gain_r;
        case LUMIA_REG_LED_GAIN_G:
            return state->cfg.led_gain_g;
        case LUMIA_REG_LED_GAIN_B:
            return state->cfg.led_gain_b;
        default:
            return 0u;
    }
}

static RegisterMapStatus write_register(uint16_t reg, uint16_t value)
{
    RuntimeState *state = runtime_state_get();
    bool changed = false;
    uint8_t group_index;
    uint8_t field_index;

    if (decode_group_register(reg, &group_index, &field_index)) {
        LumiaGroupInnerConfig *group = &state->cfg.groups[group_index];

        switch (field_index) {
            case 0u:
                changed = group->inner_mode != (uint8_t)value;
                group->inner_mode = (uint8_t)value;
                break;
            case 1u:
                changed = group->hue != value;
                group->hue = value;
                break;
            case 2u:
                changed = group->sat != (uint8_t)value;
                group->sat = (uint8_t)value;
                break;
            case 3u:
                changed = group->val != (uint8_t)value;
                group->val = (uint8_t)value;
                break;
            case 4u:
                changed = group->inner_param != (uint8_t)value;
                group->inner_param = (uint8_t)value;
                break;
            default:
                return REGISTER_MAP_ILLEGAL_ADDR;
        }

        if (changed) {
            runtime_state_mark_config_changed();
        }
        return REGISTER_MAP_OK;
    }

    switch (reg) {
        case LUMIA_REG_SCENE_MODE:
            changed = state->cfg.scene_mode != (uint8_t)value;
            state->cfg.scene_mode = (uint8_t)value;
            break;
        case LUMIA_REG_SCENE_PARAM:
            changed = state->cfg.scene_param != (uint8_t)value;
            state->cfg.scene_param = (uint8_t)value;
            break;
        case 0x0006u:
        case 0x0007u:
        case 0x0008u:
        case LUMIA_REG_RESERVED_0009:
            return REGISTER_MAP_ILLEGAL_ADDR;
        case LUMIA_REG_DEVICE_ADDR:
            return runtime_state_set_device_addr((uint8_t)value)
                       ? REGISTER_MAP_OK
                       : REGISTER_MAP_ILLEGAL_VALUE;
        case LUMIA_REG_UART_PARSE_ERROR:
            runtime_state_clear_diag_counters();
            return REGISTER_MAP_OK;
        case LUMIA_REG_LED_GLOBAL_BRI:
            changed = state->cfg.led_global_bri != (uint8_t)value;
            state->cfg.led_global_bri = (uint8_t)value;
            break;
        case LUMIA_REG_LED_GAIN_R:
            changed = state->cfg.led_gain_r != (uint8_t)value;
            state->cfg.led_gain_r = (uint8_t)value;
            break;
        case LUMIA_REG_LED_GAIN_G:
            changed = state->cfg.led_gain_g != (uint8_t)value;
            state->cfg.led_gain_g = (uint8_t)value;
            break;
        case LUMIA_REG_LED_GAIN_B:
            changed = state->cfg.led_gain_b != (uint8_t)value;
            state->cfg.led_gain_b = (uint8_t)value;
            break;
        default:
            return REGISTER_MAP_ILLEGAL_ADDR;
    }

    if (changed) {
        runtime_state_mark_config_changed();
    }
    return REGISTER_MAP_OK;
}

void register_map_init(void)
{
}

bool register_map_is_range_supported(uint16_t start_reg, uint16_t count)
{
    return is_range_in_region(start_reg, count, 0x0000u, CONFIG_REG_END_EXCLUSIVE) ||
           is_range_in_region(start_reg, count, LUMIA_REG_GROUP_BASE, GROUP_REG_END_EXCLUSIVE);
}

RegisterMapStatus register_map_read_holding(uint16_t start_reg,
                                            uint16_t count,
                                            uint16_t *out_values)
{
    RuntimeState *state;
    uint16_t index;

    if (!register_map_is_range_supported(start_reg, count) || out_values == NULL) {
        return REGISTER_MAP_ILLEGAL_ADDR;
    }

    state = runtime_state_get();
    for (index = 0u; index < count; ++index) {
        out_values[index] = read_register((uint16_t)(start_reg + index), state);
    }
    return REGISTER_MAP_OK;
}

RegisterMapStatus register_map_write_single(uint16_t reg, uint16_t value)
{
    RegisterMapStatus status;

    if (!register_map_is_range_supported(reg, 1u) || is_read_only_reg(reg)) {
        return REGISTER_MAP_ILLEGAL_ADDR;
    }

    status = validate_value(reg, value);
    return status == REGISTER_MAP_OK ? write_register(reg, value) : status;
}

RegisterMapStatus register_map_write_multiple(uint16_t start_reg,
                                              uint16_t count,
                                              const uint16_t *values)
{
    uint16_t index;

    if (!register_map_is_range_supported(start_reg, count) || values == NULL) {
        return REGISTER_MAP_ILLEGAL_ADDR;
    }

    for (index = 0u; index < count; ++index) {
        uint16_t reg = (uint16_t)(start_reg + index);
        RegisterMapStatus status;

        if (is_read_only_reg(reg) || reg == LUMIA_REG_UART_PARSE_ERROR) {
            return REGISTER_MAP_ILLEGAL_ADDR;
        }
        status = validate_value(reg, values[index]);
        if (status != REGISTER_MAP_OK) {
            return status;
        }
    }

    for (index = 0u; index < count; ++index) {
        RegisterMapStatus status = write_register((uint16_t)(start_reg + index), values[index]);
        if (status != REGISTER_MAP_OK) {
            return status;
        }
    }
    return REGISTER_MAP_OK;
}
