#pragma once

#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint8_t primary_channel;
    int8_t rssi;
} LumiaWifiChannelObservation;

uint8_t lumia_wifi_select_channel(
    const LumiaWifiChannelObservation *observations,
    size_t observation_count,
    uint8_t fallback_channel);

