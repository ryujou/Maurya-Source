#include "effect_inner_mode_strobe.h"

static uint32_t map_strobe_half_period_ms(uint8_t speed)
{
    return 40u + ((uint32_t)(255u - speed) * 260u) / 255u;
}

void lumia_effect_inner_mode_strobe_advance(LumiaInnerState *state,
                                            uint8_t speed,
                                            uint32_t elapsed_ms)
{
    uint32_t half_period = map_strobe_half_period_ms(speed);

    if (elapsed_ms == 0u) {
        return;
    }

    state->accumulator_ms += elapsed_ms;
    while (state->accumulator_ms >= half_period) {
        state->accumulator_ms -= half_period;
        state->phase = (uint16_t)(state->phase + 1u);
    }
}

LumiaRgb lumia_effect_inner_mode_strobe_render(const LumiaInnerState *state,
                                               const LumiaGroupEffectConfig *config)
{
    if ((state->phase & 1u) == 0u) {
        return (LumiaRgb){0u, 0u, 0u};
    }

    return lumia_effect_hsv_to_rgb(config->hue,
                                   config->saturation,
                                   config->value);
}
