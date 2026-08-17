#include "mode_button_logic.h"

#include <stddef.h>

static bool time_reached(uint32_t now_ms, uint32_t deadline_ms)
{
    return (int32_t)(now_ms - deadline_ms) >= 0;
}

void lumia_mode_button_logic_init(LumiaModeButtonLogic *logic,
                                  bool initially_pressed,
                                  uint32_t now_ms)
{
    if (logic == NULL) {
        return;
    }

    logic->sampled_pressed = initially_pressed;
    logic->debounced_pressed = initially_pressed;
    logic->ignore_until_release = initially_pressed;
    logic->last_change_ms = now_ms;
    logic->press_started_ms = now_ms;
}

LumiaModeButtonEvent lumia_mode_button_logic_update(
    LumiaModeButtonLogic *logic,
    bool sampled_pressed,
    uint32_t now_ms,
    uint32_t debounce_ms,
    uint32_t long_press_ms)
{
    if (logic == NULL || long_press_ms == 0u) {
        return LUMIA_MODE_BUTTON_EVENT_NONE;
    }

    if (sampled_pressed != logic->sampled_pressed) {
        logic->sampled_pressed = sampled_pressed;
        logic->last_change_ms = now_ms;
        return LUMIA_MODE_BUTTON_EVENT_NONE;
    }

    if (sampled_pressed == logic->debounced_pressed ||
        !time_reached(now_ms, logic->last_change_ms + debounce_ms)) {
        return LUMIA_MODE_BUTTON_EVENT_NONE;
    }

    logic->debounced_pressed = sampled_pressed;
    if (sampled_pressed) {
        if (!logic->ignore_until_release) {
            logic->press_started_ms = now_ms;
        }
        return LUMIA_MODE_BUTTON_EVENT_NONE;
    }

    if (logic->ignore_until_release) {
        logic->ignore_until_release = false;
        return LUMIA_MODE_BUTTON_EVENT_NONE;
    }

    return (uint32_t)(now_ms - logic->press_started_ms) >= long_press_ms
               ? LUMIA_MODE_BUTTON_EVENT_LONG_PRESS
               : LUMIA_MODE_BUTTON_EVENT_SHORT_PRESS;
}
