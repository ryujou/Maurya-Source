#include "effect_inner_mode_steady.h"

LumiaRgb lumia_effect_inner_mode_steady_render(
    const LumiaGroupEffectConfig *config)
{
    return lumia_effect_hsv_to_rgb(config->hue,
                                   config->saturation,
                                   config->value);
}
