#include "effect_session.h"

#include <string.h>

static bool groups_valid(
    const LumiaGroupEffectConfig groups[LUMIA_EFFECT_GROUP_COUNT])
{
    if (groups == NULL) {
        return false;
    }
    for (uint8_t i = 0u; i < LUMIA_EFFECT_GROUP_COUNT; ++i) {
        /*
         * Frames carry all seven groups. Blocks only select steady/strobe,
         * but untouched groups may legitimately retain persisted
         * breath/fade modes.
         */
        if (groups[i].inner_mode < LUMIA_INNER_MODE_STEADY ||
            groups[i].inner_mode > LUMIA_INNER_MODE_FADE ||
            groups[i].hue > 359u) {
            return false;
        }
    }
    return true;
}

void lumia_effect_session_init(LumiaEffectSession *session)
{
    if (session != NULL) {
        memset(session, 0, sizeof(*session));
    }
}

LumiaEffectSessionStatus lumia_effect_session_begin(
    LumiaEffectSession *session,
    uint32_t session_id,
    uint32_t now_ms,
    const LumiaEffectConfig *persistent_config)
{
    if (session == NULL || persistent_config == NULL || session_id == 0u) {
        return LUMIA_EFFECT_SESSION_INVALID_ARGUMENT;
    }
    session->config = *persistent_config;
    session->config.scene_mode = LUMIA_SCENE_MODE_STATIC;
    session->config.scene_param = 0u;
    session->active = true;
    session->session_id = session_id;
    session->last_activity_ms = now_ms;
    session->last_sequence = 0u;
    session->has_sequence = false;
    session->mode = LUMIA_EFFECT_SESSION_MODE_NONE;
    memset(session->pixels, 0, sizeof(session->pixels));
    return LUMIA_EFFECT_SESSION_OK;
}

static LumiaEffectSessionStatus validate_frame_header(
    LumiaEffectSession *session,
    uint32_t session_id,
    uint16_t sequence,
    LumiaEffectSessionMode requested_mode)
{
    if (session == NULL || requested_mode == LUMIA_EFFECT_SESSION_MODE_NONE) {
        return LUMIA_EFFECT_SESSION_INVALID_ARGUMENT;
    }
    if (!session->active) {
        return LUMIA_EFFECT_SESSION_NOT_ACTIVE;
    }
    if (session->session_id != session_id) {
        return LUMIA_EFFECT_SESSION_WRONG_ID;
    }
    if (session->mode != LUMIA_EFFECT_SESSION_MODE_NONE &&
        session->mode != requested_mode) {
        return LUMIA_EFFECT_SESSION_MODE_MISMATCH;
    }
    if (session->has_sequence &&
        (int16_t)(sequence - session->last_sequence) <= 0) {
        return LUMIA_EFFECT_SESSION_STALE_FRAME;
    }
    return LUMIA_EFFECT_SESSION_OK;
}

LumiaEffectSessionStatus lumia_effect_session_frame(
    LumiaEffectSession *session,
    uint32_t session_id,
    uint16_t sequence,
    uint32_t now_ms,
    const LumiaGroupEffectConfig groups[LUMIA_EFFECT_GROUP_COUNT])
{
    LumiaEffectSessionStatus status;
    if (session == NULL || !groups_valid(groups)) {
        return LUMIA_EFFECT_SESSION_INVALID_ARGUMENT;
    }
    status = validate_frame_header(session, session_id, sequence,
                                   LUMIA_EFFECT_SESSION_MODE_GROUP);
    if (status != LUMIA_EFFECT_SESSION_OK) {
        return status;
    }
    memcpy(session->config.groups, groups, sizeof(session->config.groups));
    session->mode = LUMIA_EFFECT_SESSION_MODE_GROUP;
    session->last_sequence = sequence;
    session->has_sequence = true;
    session->last_activity_ms = now_ms;
    return LUMIA_EFFECT_SESSION_OK;
}

LumiaEffectSessionStatus lumia_effect_session_pixel_frame(
    LumiaEffectSession *session,
    uint32_t session_id,
    uint16_t sequence,
    uint32_t now_ms,
    const LumiaRgb pixels[LUMIA_EFFECT_LED_COUNT])
{
    LumiaEffectSessionStatus status;
    if (session == NULL || pixels == NULL) {
        return LUMIA_EFFECT_SESSION_INVALID_ARGUMENT;
    }
    status = validate_frame_header(session, session_id, sequence,
                                   LUMIA_EFFECT_SESSION_MODE_PIXEL);
    if (status != LUMIA_EFFECT_SESSION_OK) {
        return status;
    }
    memcpy(session->pixels, pixels, sizeof(session->pixels));
    session->mode = LUMIA_EFFECT_SESSION_MODE_PIXEL;
    session->last_sequence = sequence;
    session->has_sequence = true;
    session->last_activity_ms = now_ms;
    return LUMIA_EFFECT_SESSION_OK;
}

LumiaEffectSessionStatus lumia_effect_session_heartbeat(
    LumiaEffectSession *session,
    uint32_t session_id,
    uint32_t now_ms)
{
    if (session == NULL) {
        return LUMIA_EFFECT_SESSION_INVALID_ARGUMENT;
    }
    if (!session->active) {
        return LUMIA_EFFECT_SESSION_NOT_ACTIVE;
    }
    if (session->session_id != session_id) {
        return LUMIA_EFFECT_SESSION_WRONG_ID;
    }
    session->last_activity_ms = now_ms;
    return LUMIA_EFFECT_SESSION_OK;
}

LumiaEffectSessionStatus lumia_effect_session_end(
    LumiaEffectSession *session,
    uint32_t session_id)
{
    if (session == NULL) {
        return LUMIA_EFFECT_SESSION_INVALID_ARGUMENT;
    }
    if (!session->active) {
        return LUMIA_EFFECT_SESSION_NOT_ACTIVE;
    }
    if (session->session_id != session_id) {
        return LUMIA_EFFECT_SESSION_WRONG_ID;
    }
    lumia_effect_session_cancel(session);
    return LUMIA_EFFECT_SESSION_OK;
}

void lumia_effect_session_cancel(LumiaEffectSession *session)
{
    if (session != NULL) {
        session->active = false;
        session->session_id = 0u;
        session->has_sequence = false;
        session->mode = LUMIA_EFFECT_SESSION_MODE_NONE;
    }
}

bool lumia_effect_session_service_timeout(
    LumiaEffectSession *session,
    uint32_t now_ms)
{
    if (session == NULL || !session->active ||
        (uint32_t)(now_ms - session->last_activity_ms) <
            LUMIA_EFFECT_SESSION_TIMEOUT_MS) {
        return false;
    }
    lumia_effect_session_cancel(session);
    return true;
}

const LumiaEffectConfig *lumia_effect_session_config(
    const LumiaEffectSession *session)
{
    return session != NULL && session->active &&
                   session->mode != LUMIA_EFFECT_SESSION_MODE_PIXEL
               ? &session->config
               : NULL;
}

const LumiaEffectConfig *lumia_effect_session_base_config(
    const LumiaEffectSession *session)
{
    return session != NULL && session->active ? &session->config : NULL;
}

const LumiaRgb *lumia_effect_session_pixels(
    const LumiaEffectSession *session)
{
    return session != NULL && session->active &&
                   session->mode == LUMIA_EFFECT_SESSION_MODE_PIXEL
               ? session->pixels
               : NULL;
}

LumiaEffectSessionMode lumia_effect_session_mode(
    const LumiaEffectSession *session)
{
    return session != NULL && session->active
               ? session->mode
               : LUMIA_EFFECT_SESSION_MODE_NONE;
}
