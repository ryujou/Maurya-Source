#include "effect_inner_mode_fade.h"

static uint32_t map_fade_half_cycle_ms(uint8_t speed)
{
    return 300u + ((uint32_t)(255u - speed) * 950u) / 255u;
}

static uint8_t fade_wave(uint16_t phase)
{
    return phase < 256u ? (uint8_t)phase : (uint8_t)(511u - phase);
}

void lumia_effect_inner_mode_fade_advance(LumiaInnerState *state,
                                          uint8_t speed,
                                          uint32_t elapsed_ms)
{
    uint32_t half_cycle = map_fade_half_cycle_ms(speed);
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

LumiaRgb lumia_effect_inner_mode_fade_render(const LumiaInnerState *state,
                                             const LumiaGroupEffectConfig *config)
{
    uint8_t wave = fade_wave(state->phase);
    uint8_t value = (uint8_t)(((uint16_t)config->value * wave) / 255u);

    return lumia_effect_hsv_to_rgb(config->hue, config->saturation, value);
}
