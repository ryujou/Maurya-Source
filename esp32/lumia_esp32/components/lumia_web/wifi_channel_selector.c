#include "wifi_channel_selector.h"

#include <limits.h>
#include <stdbool.h>

static const uint8_t CANDIDATE_CHANNELS[] = {1u, 6u, 11u};

static uint8_t normalized_fallback(uint8_t channel)
{
    for (size_t index = 0u;
         index < sizeof(CANDIDATE_CHANNELS) / sizeof(CANDIDATE_CHANNELS[0]);
         ++index) {
        if (CANDIDATE_CHANNELS[index] == channel) {
            return channel;
        }
    }
    return CANDIDATE_CHANNELS[0];
}

static uint32_t overlap_weight(uint8_t candidate, uint8_t observed)
{
    uint8_t delta = candidate > observed ? candidate - observed : observed - candidate;
    return delta <= 4u ? (uint32_t)(5u - delta) : 0u;
}

uint8_t lumia_wifi_select_channel(
    const LumiaWifiChannelObservation *observations,
    size_t observation_count,
    uint8_t fallback_channel)
{
    const uint8_t fallback = normalized_fallback(fallback_channel);
    uint64_t scores[3] = {0u, 0u, 0u};
    uint64_t lowest_score = UINT64_MAX;
    bool fallback_tied = false;

    if (observations == NULL || observation_count == 0u) {
        return fallback;
    }

    for (size_t observation_index = 0u;
         observation_index < observation_count;
         ++observation_index) {
        const uint8_t observed_channel = observations[observation_index].primary_channel;
        int32_t rssi = observations[observation_index].rssi;

        if (observed_channel < 1u || observed_channel > 14u) {
            continue;
        }
        if (rssi < -100) {
            rssi = -100;
        } else if (rssi > -30) {
            rssi = -30;
        }
        const uint32_t strength = (uint32_t)(rssi + 101);
        for (size_t candidate_index = 0u;
             candidate_index < sizeof(CANDIDATE_CHANNELS) / sizeof(CANDIDATE_CHANNELS[0]);
             ++candidate_index) {
            const uint32_t weight = overlap_weight(CANDIDATE_CHANNELS[candidate_index],
                                                   observed_channel);
            scores[candidate_index] += (uint64_t)strength * strength * weight;
        }
    }

    for (size_t index = 0u; index < 3u; ++index) {
        if (scores[index] < lowest_score) {
            lowest_score = scores[index];
        }
    }
    for (size_t index = 0u; index < 3u; ++index) {
        if (CANDIDATE_CHANNELS[index] == fallback && scores[index] == lowest_score) {
            fallback_tied = true;
        }
    }
    if (fallback_tied) {
        return fallback;
    }
    for (size_t index = 0u; index < 3u; ++index) {
        if (scores[index] == lowest_score) {
            return CANDIDATE_CHANNELS[index];
        }
    }
    return fallback;
}

