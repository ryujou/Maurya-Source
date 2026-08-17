#pragma once

#include <stdint.h>

#define LUMIA_EFFECT_GROUP_COUNT      7u
#define LUMIA_EFFECT_GROUP_LED_COUNT  6u
#define LUMIA_EFFECT_LED_COUNT        \
    (LUMIA_EFFECT_GROUP_COUNT * LUMIA_EFFECT_GROUP_LED_COUNT)

typedef enum {
    LUMIA_INNER_MODE_STEADY = 1,
    LUMIA_INNER_MODE_BREATH = 2,
    LUMIA_INNER_MODE_STROBE = 3,
    LUMIA_INNER_MODE_FADE = 4,
} LumiaInnerMode;

typedef enum {
    LUMIA_SCENE_MODE_STATIC = 1,
    LUMIA_SCENE_MODE_CHASE_LR = 2,
    LUMIA_SCENE_MODE_CHASE_RL = 3,
    LUMIA_SCENE_MODE_PINGPONG = 4,
} LumiaSceneMode;

typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
} LumiaRgb;

typedef struct {
    uint8_t inner_mode;
    uint16_t hue;
    uint8_t saturation;
    uint8_t value;
    uint8_t inner_param;
} LumiaGroupEffectConfig;

typedef struct {
    LumiaRgb pixels[LUMIA_EFFECT_LED_COUNT];
} RgbFrame;

typedef struct {
    uint8_t scene_mode;
    uint8_t scene_param;
    uint8_t global_brightness;
    uint8_t white_balance_r;
    uint8_t white_balance_g;
    uint8_t white_balance_b;
    LumiaGroupEffectConfig groups[LUMIA_EFFECT_GROUP_COUNT];
} LumiaEffectConfig;

/*
 * Statically allocated engine state. Applications should initialize it with
 * lumia_effect_engine_init() and otherwise treat the fields as read-only.
 */
typedef struct {
    uint16_t phase;
    uint32_t accumulator_ms;
    uint8_t active_mode;
} LumiaInnerState;

typedef struct {
    uint16_t position_q8;
    int8_t direction;
    uint8_t active_mode;
} LumiaSceneState;

typedef struct LumiaEffectEngine {
    uint32_t now_ms;
    uint32_t pending_ms;
    LumiaInnerState inner[LUMIA_EFFECT_GROUP_COUNT];
    LumiaSceneState scene;
} LumiaEffectEngine;
