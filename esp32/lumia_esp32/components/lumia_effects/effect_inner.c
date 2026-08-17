#include "effect_inner.h"

#include <string.h>

#include "effect_inner_mode_breath.h"
#include "effect_inner_mode_fade.h"
#include "effect_inner_mode_steady.h"
#include "effect_inner_mode_strobe.h"

bool lumia_effect_inner_mode_is_valid_impl(uint8_t mode)
{
    return mode >= LUMIA_INNER_MODE_STEADY &&
           mode <= LUMIA_INNER_MODE_FADE;
}

void lumia_effect_inner_enter(LumiaEffectEngine *engine,
                              uint8_t group_index,
                              uint8_t mode)
{
    LumiaInnerState *state = &engine->inner[group_index];

    memset(state, 0, sizeof(*state));
    state->active_mode = mode;
}

void lumia_effect_inner_advance(LumiaEffectEngine *engine,
                                const LumiaGroupEffectConfig *config,
                                uint8_t group_index,
                                uint32_t elapsed_ms)
{
    LumiaInnerState *state = &engine->inner[group_index];

    if (elapsed_ms == 0u) {
        return;
    }

    switch (config->inner_mode) {
        case LUMIA_INNER_MODE_BREATH:
            lumia_effect_inner_mode_breath_advance(state,
                                                   config->inner_param,
                                                   elapsed_ms);
            break;
        case LUMIA_INNER_MODE_STROBE:
            lumia_effect_inner_mode_strobe_advance(state,
                                                   config->inner_param,
                                                   elapsed_ms);
            break;
        case LUMIA_INNER_MODE_FADE:
            lumia_effect_inner_mode_fade_advance(state,
                                                 config->inner_param,
                                                 elapsed_ms);
            break;
        case LUMIA_INNER_MODE_STEADY:
        default:
            break;
    }
}

LumiaRgb lumia_effect_inner_render_color(const LumiaEffectEngine *engine,
                                         const LumiaGroupEffectConfig *config,
                                         uint8_t group_index)
{
    const LumiaInnerState *state = &engine->inner[group_index];

    switch (config->inner_mode) {
        case LUMIA_INNER_MODE_STEADY:
            return lumia_effect_inner_mode_steady_render(config);
        case LUMIA_INNER_MODE_BREATH:
            return lumia_effect_inner_mode_breath_render(state, config);
        case LUMIA_INNER_MODE_STROBE:
            return lumia_effect_inner_mode_strobe_render(state, config);
        case LUMIA_INNER_MODE_FADE:
            return lumia_effect_inner_mode_fade_render(state, config);
        default:
            return (LumiaRgb){0u, 0u, 0u};
    }
}
