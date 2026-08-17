#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#include "effect_engine.h"

static void tick_ms(LumiaEffectEngine *engine, uint32_t milliseconds)
{
    uint32_t index;

    for (index = 0u; index < milliseconds; ++index) {
        lumia_effect_engine_tick_1ms(engine);
    }
}

static bool rgb_equal(LumiaRgb left, LumiaRgb right)
{
    return left.r == right.r && left.g == right.g && left.b == right.b;
}

static void test_hsv(void)
{
    assert(rgb_equal(lumia_effect_hsv_to_rgb(0u, 255u, 255u),
                     (LumiaRgb){255u, 0u, 0u}));
    assert(rgb_equal(lumia_effect_hsv_to_rgb(120u, 255u, 255u),
                     (LumiaRgb){0u, 255u, 0u}));
    assert(rgb_equal(lumia_effect_hsv_to_rgb(240u, 255u, 255u),
                     (LumiaRgb){0u, 0u, 255u}));
}

static void test_static_steady_and_correction(void)
{
    LumiaEffectEngine engine;
    LumiaEffectConfig config;
    RgbFrame frame;
    uint8_t index;

    lumia_effect_engine_init(&engine);
    lumia_effect_config_default(&config);
    config.scene_mode = LUMIA_SCENE_MODE_STATIC;
    config.groups[0].inner_mode = LUMIA_INNER_MODE_STEADY;
    config.groups[0].hue = 0u;
    config.global_brightness = 128u;

    tick_ms(&engine, 2u);
    assert(lumia_effect_engine_tick_frame(&engine, &config, &frame));
    for (index = 0u; index < LUMIA_EFFECT_GROUP_LED_COUNT; ++index) {
        assert(rgb_equal(frame.pixels[index], (LumiaRgb){128u, 0u, 0u}));
    }
}

static void test_scene_chase_lr(void)
{
    LumiaEffectEngine engine;
    LumiaEffectConfig config;
    RgbFrame frame;
    LumiaRgb orange = lumia_effect_hsv_to_rgb(30u, 255u, 255u);
    uint8_t led;
    uint8_t group;

    lumia_effect_engine_init(&engine);
    lumia_effect_config_default(&config);
    config.scene_mode = LUMIA_SCENE_MODE_CHASE_LR;
    config.scene_param = 80u;

    tick_ms(&engine, 2u);
    assert(lumia_effect_engine_tick_frame(&engine, &config, &frame));
    for (led = 0u; led < LUMIA_EFFECT_GROUP_LED_COUNT; ++led) {
        assert(rgb_equal(frame.pixels[led], orange));
    }
    for (group = 1u; group < LUMIA_EFFECT_GROUP_COUNT; ++group) {
        for (led = 0u; led < LUMIA_EFFECT_GROUP_LED_COUNT; ++led) {
            uint8_t index = (uint8_t)(group * LUMIA_EFFECT_GROUP_LED_COUNT + led);
            assert(rgb_equal(frame.pixels[index], (LumiaRgb){0u, 0u, 0u}));
        }
    }

    tick_ms(&engine, 260u);
    assert(lumia_effect_engine_tick_frame(&engine, &config, &frame));
    for (led = 0u; led < LUMIA_EFFECT_GROUP_LED_COUNT; ++led) {
        assert(rgb_equal(frame.pixels[LUMIA_EFFECT_GROUP_LED_COUNT + led], orange));
        assert(rgb_equal(frame.pixels[led], (LumiaRgb){0u, 0u, 0u}));
    }
}

static void test_breath_strobe_fade(void)
{
    LumiaEffectEngine engine;
    LumiaEffectConfig config;
    RgbFrame frame;
    uint8_t breath_start;
    uint8_t breath_after_100ms;
    uint8_t fade_start;
    uint8_t strobe_first;
    uint8_t strobe_second;

    lumia_effect_engine_init(&engine);
    lumia_effect_config_default(&config);

    config.groups[0].inner_mode = LUMIA_INNER_MODE_BREATH;
    config.groups[0].inner_param = 255u;
    tick_ms(&engine, 2u);
    assert(lumia_effect_engine_tick_frame(&engine, &config, &frame));
    breath_start = frame.pixels[0].r;
    tick_ms(&engine, 100u);
    assert(lumia_effect_engine_tick_frame(&engine, &config, &frame));
    breath_after_100ms = frame.pixels[0].r;
    assert(breath_after_100ms > breath_start);

    config.groups[0].inner_mode = LUMIA_INNER_MODE_STROBE;
    config.groups[0].inner_param = 255u;
    tick_ms(&engine, 2u);
    assert(lumia_effect_engine_tick_frame(&engine, &config, &frame));
    strobe_first = frame.pixels[0].r;
    tick_ms(&engine, 40u);
    assert(lumia_effect_engine_tick_frame(&engine, &config, &frame));
    strobe_second = frame.pixels[0].r;
    assert(strobe_first != strobe_second);

    config.groups[0].inner_mode = LUMIA_INNER_MODE_FADE;
    config.groups[0].inner_param = 255u;
    tick_ms(&engine, 2u);
    assert(lumia_effect_engine_tick_frame(&engine, &config, &frame));
    fade_start = frame.pixels[0].r;
    tick_ms(&engine, 80u);
    assert(lumia_effect_engine_tick_frame(&engine, &config, &frame));
    assert(frame.pixels[0].r > fade_start);
}

static void test_pingpong_and_invalid(void)
{
    LumiaEffectEngine engine;
    LumiaEffectConfig config;
    RgbFrame frame;
    uint8_t last_group_index =
        (uint8_t)((LUMIA_EFFECT_GROUP_COUNT - 1u) * LUMIA_EFFECT_GROUP_LED_COUNT);

    lumia_effect_engine_init(&engine);
    lumia_effect_config_default(&config);
    config.scene_mode = LUMIA_SCENE_MODE_PINGPONG;
    config.scene_param = 255u;
    tick_ms(&engine, 6u * 40u);
    assert(lumia_effect_engine_tick_frame(&engine, &config, &frame));
    assert(frame.pixels[last_group_index].r == 255u);

    lumia_effect_engine_reset(&engine);
    tick_ms(&engine, 241u);
    assert(lumia_effect_engine_tick_frame(&engine, &config, &frame));
    assert(frame.pixels[last_group_index].r == 255u);

    tick_ms(&engine, 10u);
    assert(lumia_effect_engine_tick_frame(&engine, &config, &frame));
    assert(frame.pixels[last_group_index].r == 255u);

    config.scene_mode = 0u;
    assert(!lumia_effect_engine_tick_frame(&engine, &config, &frame));
    config.scene_mode = LUMIA_SCENE_MODE_STATIC;
    config.groups[0].inner_mode = 0u;
    assert(!lumia_effect_engine_tick_frame(&engine, &config, &frame));
}

int main(void)
{
    test_hsv();
    test_static_steady_and_correction();
    test_scene_chase_lr();
    test_breath_strobe_fade();
    test_pingpong_and_invalid();
    puts("lumia_effects tests passed");
    return 0;
}
