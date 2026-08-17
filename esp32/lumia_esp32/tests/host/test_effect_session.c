#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "effect_session.h"

static LumiaEffectConfig persistent_config(void)
{
    LumiaEffectConfig config = {
        .scene_mode = LUMIA_SCENE_MODE_CHASE_LR,
        .scene_param = 80u,
        .global_brightness = 200u,
        .white_balance_r = 255u,
        .white_balance_g = 231u,
        .white_balance_b = 240u,
    };
    for (uint8_t i = 0u; i < LUMIA_EFFECT_GROUP_COUNT; ++i) {
        config.groups[i].inner_mode = LUMIA_INNER_MODE_STEADY;
        config.groups[i].hue = (uint16_t)(i * 30u);
        config.groups[i].saturation = 255u;
        config.groups[i].value = 180u;
        config.groups[i].inner_param = 10u;
    }
    return config;
}

int main(void)
{
    LumiaEffectSession session;
    LumiaEffectConfig persisted = persistent_config();
    LumiaGroupEffectConfig groups[LUMIA_EFFECT_GROUP_COUNT];
    memcpy(groups, persisted.groups, sizeof(groups));
    groups[0].hue = 359u;
    groups[1].inner_mode = LUMIA_INNER_MODE_STROBE;

    lumia_effect_session_init(&session);
    assert(lumia_effect_session_begin(&session, 0x12345678u, UINT32_MAX - 2u,
                                      &persisted) ==
           LUMIA_EFFECT_SESSION_OK);
    assert(session.config.scene_mode == LUMIA_SCENE_MODE_STATIC);
    assert(session.config.global_brightness == persisted.global_brightness);
    assert(lumia_effect_session_frame(&session, 0x12345678u, 65535u, 1u,
                                      groups) == LUMIA_EFFECT_SESSION_OK);
    assert(session.config.groups[0].hue == 359u);
    assert(lumia_effect_session_frame(&session, 0x12345678u, 0u, 2u,
                                      groups) == LUMIA_EFFECT_SESSION_OK);
    groups[2].inner_mode = LUMIA_INNER_MODE_BREATH;
    groups[3].inner_mode = LUMIA_INNER_MODE_FADE;
    assert(lumia_effect_session_frame(&session, 0x12345678u, 1u, 2u,
                                      groups) == LUMIA_EFFECT_SESSION_OK);
    assert(lumia_effect_session_frame(&session, 0x12345678u, 0u, 3u,
                                      groups) ==
           LUMIA_EFFECT_SESSION_STALE_FRAME);
    assert(lumia_effect_session_heartbeat(&session, 0xDEADBEEFu, 4u) ==
           LUMIA_EFFECT_SESSION_WRONG_ID);
    assert(!lumia_effect_session_service_timeout(&session, 5001u));
    assert(lumia_effect_session_service_timeout(&session, 5002u));
    assert(lumia_effect_session_config(&session) == NULL);
    LumiaEffectConfig original = persistent_config();
    assert(memcmp(&persisted, &original, sizeof(persisted)) == 0);

    LumiaRgb pixels[LUMIA_EFFECT_LED_COUNT];
    for (uint8_t i = 0u; i < LUMIA_EFFECT_LED_COUNT; ++i) {
        pixels[i] = (LumiaRgb){i, (uint8_t)(i + 1u), (uint8_t)(i + 2u)};
    }
    assert(lumia_effect_session_begin(&session, 0x87654321u, 10u,
                                      &persisted) ==
           LUMIA_EFFECT_SESSION_OK);
    assert(lumia_effect_session_mode(&session) ==
           LUMIA_EFFECT_SESSION_MODE_NONE);
    assert(lumia_effect_session_pixel_frame(&session, 0x87654321u, 7u, 11u,
                                            pixels) ==
           LUMIA_EFFECT_SESSION_OK);
    assert(lumia_effect_session_mode(&session) ==
           LUMIA_EFFECT_SESSION_MODE_PIXEL);
    assert(lumia_effect_session_config(&session) == NULL);
    assert(lumia_effect_session_base_config(&session)->global_brightness ==
           persisted.global_brightness);
    assert(memcmp(lumia_effect_session_pixels(&session), pixels,
                  sizeof(pixels)) == 0);
    assert(lumia_effect_session_frame(&session, 0x87654321u, 8u, 12u,
                                      groups) ==
           LUMIA_EFFECT_SESSION_MODE_MISMATCH);
    pixels[0].r = 0xAAu;
    assert(lumia_effect_session_pixel_frame(&session, 0x87654321u, 8u, 13u,
                                            pixels) ==
           LUMIA_EFFECT_SESSION_OK);
    assert(lumia_effect_session_pixels(&session)[0].r == 0xAAu);
    assert(lumia_effect_session_pixel_frame(&session, 0x87654321u, 8u, 14u,
                                            pixels) ==
           LUMIA_EFFECT_SESSION_STALE_FRAME);
    lumia_effect_session_cancel(&session);
    assert(lumia_effect_session_pixels(&session) == NULL);

    assert(lumia_effect_session_begin(&session, 0xABCDEF01u, 20u,
                                      &persisted) ==
           LUMIA_EFFECT_SESSION_OK);
    assert(lumia_effect_session_pixel_frame(&session, 0xABCDEF01u, 0xFFFFu,
                                            21u, pixels) ==
           LUMIA_EFFECT_SESSION_OK);
    pixels[0].g = 0x5Au;
    assert(lumia_effect_session_pixel_frame(&session, 0xABCDEF01u, 0x0000u,
                                            22u, pixels) ==
           LUMIA_EFFECT_SESSION_OK);
    assert(lumia_effect_session_pixels(&session)[0].g == 0x5Au);

    puts("effect session tests passed");
    return 0;
}
