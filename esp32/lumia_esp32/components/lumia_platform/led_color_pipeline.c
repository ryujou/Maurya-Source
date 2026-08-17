#include "led_color_pipeline.h"

#define LUMIA_LED_MIN_VISIBLE_LEVEL 3u

static uint8_t s_dither_phase;

/* Gamma 2.6 lookup in Q8.4, closer to common NeoPixel defaults. */
static const uint16_t s_gamma_q4[256] = {
       0,    0,    0,    0,    0,    0,    0,    0,    1,    1,    1,    1,    1,    2,    2,    3,
       3,    4,    4,    5,    5,    6,    7,    8,    9,   10,   11,   12,   13,   14,   16,   17,
      18,   20,   22,   23,   25,   27,   29,   31,   33,   35,   38,   40,   42,   45,   48,   50,
      53,   56,   59,   62,   65,   69,   72,   76,   79,   83,   87,   91,   95,   99,  103,  108,
     112,  117,  121,  126,  131,  136,  142,  147,  152,  158,  164,  169,  175,  181,  188,  194,
     200,  207,  214,  220,  227,  235,  242,  249,  257,  264,  272,  280,  288,  296,  305,  313,
     322,  331,  340,  349,  358,  367,  377,  386,  396,  406,  416,  427,  437,  448,  458,  469,
     480,  492,  503,  515,  526,  538,  550,  562,  575,  587,  600,  613,  626,  639,  653,  666,
     680,  694,  708,  722,  736,  751,  766,  781,  796,  811,  827,  842,  858,  874,  890,  907,
     923,  940,  957,  974,  992, 1009, 1027, 1045, 1063, 1081, 1100, 1118, 1137, 1156, 1175, 1195,
    1214, 1234, 1254, 1275, 1295, 1316, 1336, 1357, 1379, 1400, 1422, 1444, 1466, 1488, 1510, 1533,
    1556, 1579, 1602, 1626, 1650, 1673, 1698, 1722, 1747, 1771, 1796, 1822, 1847, 1873, 1899, 1925,
    1951, 1977, 2004, 2031, 2058, 2086, 2113, 2141, 2169, 2198, 2226, 2255, 2284, 2313, 2343, 2372,
    2402, 2432, 2463, 2493, 2524, 2555, 2587, 2618, 2650, 2682, 2714, 2747, 2779, 2812, 2846, 2879,
    2913, 2947, 2981, 3015, 3050, 3085, 3120, 3155, 3191, 3227, 3263, 3299, 3336, 3373, 3410, 3447,
    3485, 3523, 3561, 3599, 3638, 3677, 3716, 3756, 3795, 3835, 3875, 3916, 3956, 3997, 4039, 4080,
};

static uint8_t gamma_dither(uint8_t input,
                            uint16_t pixel_index,
                            uint8_t channel_phase)
{
    uint16_t q4 = s_gamma_q4[input];
    uint8_t output = (uint8_t)(q4 >> 4u);
    uint8_t fraction = (uint8_t)(q4 & 0x0Fu);
    uint8_t phase = (uint8_t)(
        (s_dither_phase + (uint8_t)pixel_index + channel_phase) & 0x0Fu);

    if (fraction != 0u && output < 255u && phase < fraction) {
        output++;
    }
    return output;
}

static void preserve_low_chroma(uint8_t *red, uint8_t *green, uint8_t *blue)
{
    uint8_t maximum = *red > *green ? *red : *green;
    maximum = maximum > *blue ? maximum : *blue;
    if (maximum == 0u || maximum >= LUMIA_LED_MIN_VISIBLE_LEVEL) {
        return;
    }

    uint16_t scale =
        (uint16_t)(LUMIA_LED_MIN_VISIBLE_LEVEL * 255u / maximum);
    uint32_t value = ((uint32_t)*red * scale + 127u) / 255u;
    *red = value > 255u ? 255u : (uint8_t)value;
    value = ((uint32_t)*green * scale + 127u) / 255u;
    *green = value > 255u ? 255u : (uint8_t)value;
    value = ((uint32_t)*blue * scale + 127u) / 255u;
    *blue = value > 255u ? 255u : (uint8_t)value;
}

void lumia_led_color_pipeline_prepare(const LumiaRgb *input,
                                      uint8_t (*output_grb)[3],
                                      size_t led_count)
{
    size_t index;

    if (input == NULL || output_grb == NULL) {
        return;
    }

    s_dither_phase = (uint8_t)((s_dither_phase + 1u) & 0x0Fu);
    for (index = 0u; index < led_count; ++index) {
        uint8_t red = gamma_dither(input[index].r, (uint16_t)index, 0u);
        uint8_t green = gamma_dither(input[index].g, (uint16_t)index, 5u);
        uint8_t blue = gamma_dither(input[index].b, (uint16_t)index, 10u);

        preserve_low_chroma(&red, &green, &blue);
        output_grb[index][0] = green;
        output_grb[index][1] = red;
        output_grb[index][2] = blue;
    }
}
