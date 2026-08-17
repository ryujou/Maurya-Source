#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "effect_types.h"

#define LUMIA_EFFECT_SESSION_TIMEOUT_MS 5000u

typedef enum {
    LUMIA_EFFECT_SESSION_OK = 0,
    LUMIA_EFFECT_SESSION_INVALID_ARGUMENT,
    LUMIA_EFFECT_SESSION_NOT_ACTIVE,
    LUMIA_EFFECT_SESSION_WRONG_ID,
    LUMIA_EFFECT_SESSION_STALE_FRAME,
    LUMIA_EFFECT_SESSION_MODE_MISMATCH,
} LumiaEffectSessionStatus;

typedef enum {
    LUMIA_EFFECT_SESSION_MODE_NONE = 0,
    LUMIA_EFFECT_SESSION_MODE_GROUP,
    LUMIA_EFFECT_SESSION_MODE_PIXEL,
} LumiaEffectSessionMode;

typedef struct {
    bool active;
    uint32_t session_id;
    uint16_t last_sequence;
    bool has_sequence;
    uint32_t last_activity_ms;
    LumiaEffectSessionMode mode;
    LumiaEffectConfig config;
    LumiaRgb pixels[LUMIA_EFFECT_LED_COUNT];
} LumiaEffectSession;

void lumia_effect_session_init(LumiaEffectSession *session);
LumiaEffectSessionStatus lumia_effect_session_begin(
    LumiaEffectSession *session,
    uint32_t session_id,
    uint32_t now_ms,
    const LumiaEffectConfig *persistent_config);
LumiaEffectSessionStatus lumia_effect_session_frame(
    LumiaEffectSession *session,
    uint32_t session_id,
    uint16_t sequence,
    uint32_t now_ms,
    const LumiaGroupEffectConfig groups[LUMIA_EFFECT_GROUP_COUNT]);
LumiaEffectSessionStatus lumia_effect_session_pixel_frame(
    LumiaEffectSession *session,
    uint32_t session_id,
    uint16_t sequence,
    uint32_t now_ms,
    const LumiaRgb pixels[LUMIA_EFFECT_LED_COUNT]);
LumiaEffectSessionStatus lumia_effect_session_heartbeat(
    LumiaEffectSession *session,
    uint32_t session_id,
    uint32_t now_ms);
LumiaEffectSessionStatus lumia_effect_session_end(
    LumiaEffectSession *session,
    uint32_t session_id);
void lumia_effect_session_cancel(LumiaEffectSession *session);
bool lumia_effect_session_service_timeout(
    LumiaEffectSession *session,
    uint32_t now_ms);
const LumiaEffectConfig *lumia_effect_session_config(
    const LumiaEffectSession *session);
const LumiaEffectConfig *lumia_effect_session_base_config(
    const LumiaEffectSession *session);
const LumiaRgb *lumia_effect_session_pixels(
    const LumiaEffectSession *session);
LumiaEffectSessionMode lumia_effect_session_mode(
    const LumiaEffectSession *session);
