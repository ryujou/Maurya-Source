#include <assert.h>
#include <stdio.h>

#include "wifi_channel_selector.h"

static void test_empty_and_fallback(void)
{
    assert(lumia_wifi_select_channel(NULL, 0u, 6u) == 6u);
    assert(lumia_wifi_select_channel(NULL, 0u, 3u) == 1u);
}

static void test_congestion_and_overlap(void)
{
    const LumiaWifiChannelObservation crowded_one[] = {
        {1u, -35}, {1u, -45}, {2u, -55},
    };
    const LumiaWifiChannelObservation crowded_six[] = {
        {5u, -42}, {6u, -38}, {7u, -48},
    };
    assert(lumia_wifi_select_channel(crowded_one, 3u, 1u) == 11u);
    assert(lumia_wifi_select_channel(crowded_six, 3u, 1u) == 11u);
}

static void test_signal_strength_and_upper_channels(void)
{
    const LumiaWifiChannelObservation signals[] = {
        {1u, -31}, {11u, -90}, {11u, -90}, {11u, -90},
    };
    const LumiaWifiChannelObservation upper[] = {
        {12u, -35}, {13u, -45},
    };
    assert(lumia_wifi_select_channel(signals, 4u, 6u) == 6u);
    assert(lumia_wifi_select_channel(upper, 2u, 1u) == 1u);
}

static void test_invalid_and_ties(void)
{
    const LumiaWifiChannelObservation invalid[] = {
        {0u, -30}, {15u, -30},
    };
    const LumiaWifiChannelObservation symmetric[] = {
        {1u, -50}, {11u, -50},
    };
    assert(lumia_wifi_select_channel(invalid, 2u, 6u) == 6u);
    assert(lumia_wifi_select_channel(symmetric, 2u, 6u) == 6u);
    assert(lumia_wifi_select_channel(symmetric, 2u, 3u) == 6u);
}

int main(void)
{
    test_empty_and_fallback();
    test_congestion_and_overlap();
    test_signal_strength_and_upper_channels();
    test_invalid_and_ties();
    puts("wifi channel selector tests passed");
    return 0;
}
