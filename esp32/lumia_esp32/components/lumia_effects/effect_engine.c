#include "effect_engine.h"

#include <limits.h>
#include <stddef.h>
#include <string.h>

#include "effect_inner.h"
#include "effect_scene.h"

static uint8_t scale_u8(uint8_t value, uint8_t scale)
{
    return (uint8_t)((((uint16_t)value * (uint16_t)scale) + 127u) / 255u);
}

static void clear_frame(RgbFrame *frame)
{
    uint8_t index;

    if (frame == NULL) {
        return;
    }

    for (index = 0u; index < LUMIA_EFFECT_LED_COUNT; ++index) {
        frame->pixels[index].r = 0u;
        frame->pixels[index].g = 0u;
        frame->pixels[index].b = 0u;
    }
}

static void reset_effect_state(LumiaEffectEngine *engine)
{
    memset(engine->inner, 0, sizeof(engine->inner));
    memset(&engine->scene, 0, sizeof(engine->scene));
    engine->scene.direction = 1;
}

void lumia_effect_config_default(LumiaEffectConfig *config)
{
    if (config == NULL) {
        return;
    }

    config->scene_mode = LUMIA_SCENE_MODE_STATIC;
    config->scene_param = 80u;
    config->global_brightness = 255u;
    config->white_balance_r = 255u;
    config->white_balance_g = 255u;
    config->white_balance_b = 255u;
    for (uint8_t group = 0u; group < LUMIA_EFFECT_GROUP_COUNT; ++group) {
        config->groups[group].inner_mode = LUMIA_INNER_MODE_STEADY;
        config->groups[group].hue = 30u;
        config->groups[group].saturation = 255u;
        config->groups[group].value = 255u;
        config->groups[group].inner_param = 255u;
    }
}

bool lumia_effect_inner_mode_is_valid(uint8_t mode)
{
    return lumia_effect_inner_mode_is_valid_impl(mode);
}

bool lumia_effect_scene_mode_is_valid(uint8_t mode)
{
    return lumia_effect_scene_mode_is_valid_impl(mode);
}

void lumia_effect_engine_reset(LumiaEffectEngine *engine)
{
    if (engine == NULL) {
        return;
    }

    engine->now_ms = 0u;
    engine->pending_ms = 0u;
    reset_effect_state(engine);
}

void lumia_effect_engine_init(LumiaEffectEngine *engine)
{
    lumia_effect_engine_reset(engine);
}

void lumia_effect_engine_tick_1ms(LumiaEffectEngine *engine)
{
    if (engine == NULL) {
        return;
    }

    if (engine->now_ms < UINT32_MAX) {
        engine->now_ms++;
    }
    if (engine->pending_ms < UINT32_MAX) {
        engine->pending_ms++;
    }
}

LumiaRgb lumia_effect_hsv_to_rgb(uint16_t hue, uint8_t saturation, uint8_t value)
{
    LumiaRgb color;
    uint16_t region;
    uint16_t remainder;
    uint16_t p;
    uint16_t q;
    uint16_t t;

    hue %= 360u;
    if (saturation == 0u) {
        color.r = value;
        color.g = value;
        color.b = value;
        return color;
    }

    region = hue / 60u;
    remainder = hue % 60u;
    p = (uint16_t)value * (255u - saturation) / 255u;
    q = (uint16_t)value *
        (255u - ((uint16_t)saturation * remainder) / 60u) / 255u;
    t = (uint16_t)value *
        (255u - ((uint16_t)saturation * (60u - remainder)) / 60u) / 255u;

    switch (region) {
        case 0u:
            color.r = value;
            color.g = (uint8_t)t;
            color.b = (uint8_t)p;
            break;
        case 1u:
            color.r = (uint8_t)q;
            color.g = value;
            color.b = (uint8_t)p;
            break;
        case 2u:
            color.r = (uint8_t)p;
            color.g = value;
            color.b = (uint8_t)t;
            break;
        case 3u:
            color.r = (uint8_t)p;
            color.g = (uint8_t)q;
            color.b = value;
            break;
        case 4u:
            color.r = (uint8_t)t;
            color.g = (uint8_t)p;
            color.b = value;
            break;
        default:
            color.r = value;
            color.g = (uint8_t)p;
            color.b = (uint8_t)q;
            break;
    }

    return color;
}

LumiaRgb lumia_effect_apply_color_correction(
    LumiaRgb color,
    const LumiaEffectConfig *config)
{
    if (config == NULL) {
        color.r = 0u;
        color.g = 0u;
        color.b = 0u;
        return color;
    }

    color.r = scale_u8(color.r, config->white_balance_r);
    color.g = scale_u8(color.g, config->white_balance_g);
    color.b = scale_u8(color.b, config->white_balance_b);

    color.r = scale_u8(color.r, config->global_brightness);
    color.g = scale_u8(color.g, config->global_brightness);
    color.b = scale_u8(color.b, config->global_brightness);
    return color;
}

bool lumia_effect_engine_tick_frame(
    LumiaEffectEngine *engine,
    const LumiaEffectConfig *config,
    RgbFrame *out_frame)
{
    uint32_t elapsed_ms;
    uint8_t group;
    uint8_t group_gain[LUMIA_EFFECT_GROUP_COUNT];

    if (out_frame == NULL) {
        return false;
    }
    clear_frame(out_frame);
    if (engine == NULL || config == NULL) {
        return false;
    }

    elapsed_ms = engine->pending_ms;
    engine->pending_ms = 0u;
    if (!lumia_effect_scene_mode_is_valid(config->scene_mode)) {
        return false;
    }

    if (engine->scene.active_mode != config->scene_mode) {
        lumia_effect_scene_enter(engine, config->scene_mode);
    }
    lumia_effect_scene_advance(engine,
                               config->scene_mode,
                               config->scene_param,
                               elapsed_ms);
    lumia_effect_scene_render_gains(engine, config->scene_mode, group_gain);

    for (group = 0u; group < LUMIA_EFFECT_GROUP_COUNT; ++group) {
        const LumiaGroupEffectConfig *group_cfg = &config->groups[group];
        uint8_t led;
        LumiaRgb base_color;
        LumiaRgb corrected;
        uint8_t linear_index_base =
            (uint8_t)(group * LUMIA_EFFECT_GROUP_LED_COUNT);

        if (!lumia_effect_inner_mode_is_valid(group_cfg->inner_mode)) {
            return false;
        }

        if (engine->inner[group].active_mode != group_cfg->inner_mode) {
            lumia_effect_inner_enter(engine, group, group_cfg->inner_mode);
        }
        lumia_effect_inner_advance(engine, group_cfg, group, elapsed_ms);
        base_color = lumia_effect_inner_render_color(engine, group_cfg, group);
        base_color.r = scale_u8(base_color.r, group_gain[group]);
        base_color.g = scale_u8(base_color.g, group_gain[group]);
        base_color.b = scale_u8(base_color.b, group_gain[group]);
        corrected = lumia_effect_apply_color_correction(base_color, config);

        for (led = 0u; led < LUMIA_EFFECT_GROUP_LED_COUNT; ++led) {
            out_frame->pixels[linear_index_base + led] = corrected;
        }
    }

    return true;
}
