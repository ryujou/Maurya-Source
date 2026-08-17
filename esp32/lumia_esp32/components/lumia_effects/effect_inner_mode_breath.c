#include "effect_inner_mode_breath.h"

static uint32_t map_breath_half_cycle_ms(uint8_t speed)
{
    return 400u + ((uint32_t)(255u - speed) * 1100u) / 255u;
}

static uint8_t breath_wave(uint16_t phase)
{
    uint16_t triangle = phase < 256u ? phase : (uint16_t)(511u - phase);
    uint32_t shaped = ((uint32_t)triangle * (uint32_t)triangle + 255u) / 255u;

    return shaped > 255u ? 255u : (uint8_t)shaped;
}

void lumia_effect_inner_mode_breath_advance(LumiaInnerState *state,
                                            uint8_t speed,
                                            uint32_t elapsed_ms)
{
    uint32_t half_cycle = map_breath_half_cycle_ms(speed);
    uint64_t total_ms;
    uint32_t step;

    if (elapsed_ms == 0u) {
        return;
    }

    total_ms = (uint64_t)state->accumulator_ms + elapsed_ms;
    step = (uint32_t)((total_ms * 256u) / half_cycle);
    state->accumulator_ms = (uint32_t)(total_ms % half_cycle);
    state->phase = (uint16_t)((state->phase + step) % 512u);
}

LumiaRgb lumia_effect_inner_mode_breath_render(const LumiaInnerState *state,
                                               const LumiaGroupEffectConfig *config)
{
    uint8_t wave = breath_wave(state->phase);
    uint8_t value = (uint8_t)(((uint16_t)config->value * wave) / 255u);

    return lumia_effect_hsv_to_rgb(config->hue, config->saturation, value);
}
