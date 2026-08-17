#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef enum {
    LUMIA_MODE_BUTTON_EVENT_NONE = 0,
    LUMIA_MODE_BUTTON_EVENT_SHORT_PRESS,
    LUMIA_MODE_BUTTON_EVENT_LONG_PRESS,
} LumiaModeButtonEvent;

typedef struct {
    bool sampled_pressed;
    bool debounced_pressed;
    bool ignore_until_release;
    uint32_t last_change_ms;
    uint32_t press_started_ms;
} LumiaModeButtonLogic;

void lumia_mode_button_logic_init(LumiaModeButtonLogic *logic,
                                  bool initially_pressed,
                                  uint32_t now_ms);
LumiaModeButtonEvent lumia_mode_button_logic_update(
    LumiaModeButtonLogic *logic,
    bool sampled_pressed,
    uint32_t now_ms,
    uint32_t debounce_ms,
    uint32_t long_press_ms);
