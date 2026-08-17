#include "effect_scene.h"

#include <string.h>

#include "effect_scene_mode_chase_lr.h"
#include "effect_scene_mode_chase_rl.h"
#include "effect_scene_mode_pingpong.h"
#include "effect_scene_mode_static.h"

#define SCENE_SPAN_Q8     (LUMIA_EFFECT_GROUP_COUNT * 256u)
#define SCENE_MAX_POS_Q8  ((LUMIA_EFFECT_GROUP_COUNT - 1u) * 256u)

static uint32_t map_scene_interval_ms(uint8_t speed)
{
    return 40u + ((uint32_t)(255u - speed) * 280u) / 255u;
}

static uint32_t scene_step_q8(uint8_t param, uint32_t elapsed_ms)
{
    uint32_t interval = map_scene_interval_ms(param);
    uint64_t numerator = (uint64_t)256u * elapsed_ms + interval / 2u;
    uint32_t step = (uint32_t)(numerator / interval);

    return step == 0u ? 1u : step;
}

bool lumia_effect_scene_mode_is_valid_impl(uint8_t mode)
{
    return mode >= LUMIA_SCENE_MODE_STATIC &&
           mode <= LUMIA_SCENE_MODE_PINGPONG;
}

void lumia_effect_scene_enter(LumiaEffectEngine *engine, uint8_t mode)
{
    LumiaSceneState *state = &engine->scene;

    memset(state, 0, sizeof(*state));
    state->active_mode = mode;
    state->direction = 1;
    if (mode == LUMIA_SCENE_MODE_CHASE_RL) {
        state->position_q8 = SCENE_MAX_POS_Q8;
    }
}

void lumia_effect_scene_advance(LumiaEffectEngine *engine,
                                uint8_t mode,
                                uint8_t param,
                                uint32_t elapsed_ms)
{
    LumiaSceneState *state = &engine->scene;
    uint32_t step;

    if (elapsed_ms == 0u || mode == LUMIA_SCENE_MODE_STATIC) {
        return;
    }

    step = scene_step_q8(param, elapsed_ms);
    switch (mode) {
        case LUMIA_SCENE_MODE_CHASE_LR:
            state->position_q8 = (uint16_t)((state->position_q8 + step) %
                                            SCENE_SPAN_Q8);
            break;
        case LUMIA_SCENE_MODE_CHASE_RL:
            state->position_q8 = (uint16_t)(
                (state->position_q8 + SCENE_SPAN_Q8 - (step % SCENE_SPAN_Q8)) %
                SCENE_SPAN_Q8);
            break;
        case LUMIA_SCENE_MODE_PINGPONG: {
            int32_t position = state->position_q8;
            int32_t max_pos = SCENE_MAX_POS_Q8;

            if (state->direction > 0) {
                if (position + (int32_t)step >= max_pos) {
                    position = max_pos;
                    state->direction = -1;
                } else {
                    position += (int32_t)step;
                }
            } else {
                if (position <= (int32_t)step) {
                    position = 0;
                    state->direction = 1;
                } else {
                    position -= (int32_t)step;
                }
            }
            state->position_q8 = (uint16_t)position;
            break;
        }
        default:
            break;
    }
}

void lumia_effect_scene_render_gains(const LumiaEffectEngine *engine,
                                     uint8_t mode,
                                     uint8_t gains[LUMIA_EFFECT_GROUP_COUNT])
{
    switch (mode) {
        case LUMIA_SCENE_MODE_STATIC:
            lumia_effect_scene_mode_static_render(gains);
            break;
        case LUMIA_SCENE_MODE_CHASE_LR:
            lumia_effect_scene_mode_chase_lr_render(&engine->scene, gains);
            break;
        case LUMIA_SCENE_MODE_CHASE_RL:
            lumia_effect_scene_mode_chase_rl_render(&engine->scene, gains);
            break;
        case LUMIA_SCENE_MODE_PINGPONG:
            lumia_effect_scene_mode_pingpong_render(&engine->scene, gains);
            break;
        default:
            memset(gains, 0, LUMIA_EFFECT_GROUP_COUNT);
            break;
    }
}
