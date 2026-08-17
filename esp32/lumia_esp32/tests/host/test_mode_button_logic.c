#include <assert.h>
#include <stdint.h>
#include <stdio.h>

#include "mode_button_logic.h"

static void settle(LumiaModeButtonLogic *logic,
                   bool pressed,
                   uint32_t changed_ms,
                   uint32_t settled_ms,
                   LumiaModeButtonEvent expected)
{
    assert(lumia_mode_button_logic_update(logic,
                                          pressed,
                                          changed_ms,
                                          30u,
                                          2000u) ==
           LUMIA_MODE_BUTTON_EVENT_NONE);
    assert(lumia_mode_button_logic_update(logic,
                                          pressed,
                                          settled_ms,
                                          30u,
                                          2000u) == expected);
}

static void test_short_and_long_press(void)
{
    LumiaModeButtonLogic logic;

    lumia_mode_button_logic_init(&logic, false, 0u);
    settle(&logic, true, 10u, 40u, LUMIA_MODE_BUTTON_EVENT_NONE);
    settle(&logic, false, 100u, 130u, LUMIA_MODE_BUTTON_EVENT_SHORT_PRESS);

    settle(&logic, true, 200u, 230u, LUMIA_MODE_BUTTON_EVENT_NONE);
    settle(&logic, false, 2229u, 2259u, LUMIA_MODE_BUTTON_EVENT_LONG_PRESS);
}

static void test_boundary(void)
{
    LumiaModeButtonLogic logic;

    lumia_mode_button_logic_init(&logic, false, 0u);
    settle(&logic, true, 1u, 31u, LUMIA_MODE_BUTTON_EVENT_NONE);
    settle(&logic, false, 2000u, 2030u, LUMIA_MODE_BUTTON_EVENT_SHORT_PRESS);

    settle(&logic, true, 3000u, 3030u, LUMIA_MODE_BUTTON_EVENT_NONE);
    settle(&logic, false, 5000u, 5030u, LUMIA_MODE_BUTTON_EVENT_LONG_PRESS);
}

static void test_initially_pressed_is_ignored(void)
{
    LumiaModeButtonLogic logic;

    lumia_mode_button_logic_init(&logic, true, 100u);
    settle(&logic, false, 5000u, 5030u, LUMIA_MODE_BUTTON_EVENT_NONE);
    settle(&logic, true, 5100u, 5130u, LUMIA_MODE_BUTTON_EVENT_NONE);
    settle(&logic, false, 5200u, 5230u, LUMIA_MODE_BUTTON_EVENT_SHORT_PRESS);
}

static void test_bounce_is_debounced(void)
{
    LumiaModeButtonLogic logic;

    lumia_mode_button_logic_init(&logic, false, 0u);
    assert(lumia_mode_button_logic_update(&logic, true, 10u, 30u, 2000u) ==
           LUMIA_MODE_BUTTON_EVENT_NONE);
    assert(lumia_mode_button_logic_update(&logic, false, 20u, 30u, 2000u) ==
           LUMIA_MODE_BUTTON_EVENT_NONE);
    assert(lumia_mode_button_logic_update(&logic, true, 25u, 30u, 2000u) ==
           LUMIA_MODE_BUTTON_EVENT_NONE);
    assert(lumia_mode_button_logic_update(&logic, true, 54u, 30u, 2000u) ==
           LUMIA_MODE_BUTTON_EVENT_NONE);
    assert(lumia_mode_button_logic_update(&logic, true, 55u, 30u, 2000u) ==
           LUMIA_MODE_BUTTON_EVENT_NONE);
    settle(&logic, false, 100u, 130u, LUMIA_MODE_BUTTON_EVENT_SHORT_PRESS);
}

static void test_time_wrap(void)
{
    LumiaModeButtonLogic logic;
    uint32_t press_change = UINT32_MAX - 50u;
    uint32_t press_settle = UINT32_MAX - 20u;

    lumia_mode_button_logic_init(&logic, false, UINT32_MAX - 100u);
    settle(&logic,
           true,
           press_change,
           press_settle,
           LUMIA_MODE_BUTTON_EVENT_NONE);
    settle(&logic, false, 1980u, 2010u, LUMIA_MODE_BUTTON_EVENT_LONG_PRESS);
}

int main(void)
{
    test_short_and_long_press();
    test_boundary();
    test_initially_pressed_is_ignored();
    test_bounce_is_debounced();
    test_time_wrap();
    puts("mode button logic host tests passed");
    return 0;
}
