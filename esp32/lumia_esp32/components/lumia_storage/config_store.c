#include "config_store.h"

#include <string.h>

#include "storage_backend.h"

#define CONFIG_SLOT_COUNT           2u
#define CONFIG_RECORD_MAGIC         0x494D554Cu
#define CONFIG_COMMIT_MAGIC         0x54494D43u
#define CONFIG_RECORD_VERSION       2u
#define CONFIG_HEADER_SIZE          32u
#define CONFIG_COMMIT_SIZE          16u
#define CONFIG_STATE_WRITING        0xFFFFFFFEu
#define CONFIG_STATE_VALID          0xFFFFFFFCu

#define HDR_MAGIC_OFFSET            0u
#define HDR_VERSION_OFFSET          4u
#define HDR_HEADER_LEN_OFFSET       6u
#define HDR_PAYLOAD_LEN_OFFSET      8u
#define HDR_RECORD_LEN_OFFSET       10u
#define HDR_SEQUENCE_OFFSET         12u
#define HDR_PAYLOAD_CRC_OFFSET      16u
#define HDR_HEADER_CRC_OFFSET       20u
#define HDR_STATE_OFFSET            24u
#define HDR_RESERVED_OFFSET         28u
#define PAYLOAD_OFFSET              CONFIG_HEADER_SIZE
#define COMMIT_OFFSET               (CONFIG_HEADER_SIZE + CONFIG_STORE_PAYLOAD_SIZE)

typedef struct {
    bool valid;
    uint32_t sequence;
    PersistentConfig config;
} SlotInfo;

static int s_active_slot = -1;
static uint32_t s_active_sequence;
static bool s_initialized;

static uint16_t get_u16_le(const uint8_t *data)
{
    return (uint16_t)((uint16_t)data[0] | ((uint16_t)data[1] << 8u));
}

static uint32_t get_u32_le(const uint8_t *data)
{
    return (uint32_t)data[0] |
           ((uint32_t)data[1] << 8u) |
           ((uint32_t)data[2] << 16u) |
           ((uint32_t)data[3] << 24u);
}

static void put_u16_le(uint8_t *data, uint16_t value)
{
    data[0] = (uint8_t)value;
    data[1] = (uint8_t)(value >> 8u);
}

static void put_u32_le(uint8_t *data, uint32_t value)
{
    data[0] = (uint8_t)value;
    data[1] = (uint8_t)(value >> 8u);
    data[2] = (uint8_t)(value >> 16u);
    data[3] = (uint8_t)(value >> 24u);
}

static uint32_t crc32_update(uint32_t crc, const uint8_t *data, size_t length)
{
    size_t index;

    for (index = 0u; index < length; ++index) {
        uint8_t bit;
        crc ^= data[index];
        for (bit = 0u; bit < 8u; ++bit) {
            uint32_t mask = (uint32_t)(-(int32_t)(crc & 1u));
            crc = (crc >> 1u) ^ (0xEDB88320u & mask);
        }
    }
    return crc;
}

static uint32_t crc32_bytes(const uint8_t *data, size_t length)
{
    return ~crc32_update(0xFFFFFFFFu, data, length);
}

static uint32_t header_crc(const uint8_t record[CONFIG_STORE_RECORD_SIZE])
{
    uint32_t crc = crc32_update(0xFFFFFFFFu, record, HDR_HEADER_CRC_OFFSET);
    crc = crc32_update(crc,
                       record + HDR_RESERVED_OFFSET,
                       CONFIG_HEADER_SIZE - HDR_RESERVED_OFFSET);
    return ~crc;
}

static bool config_is_valid(const PersistentConfig *config)
{
    uint8_t group;

    if (config->scene_mode < 1u || config->scene_mode > 4u ||
        config->device_addr < 1u || config->device_addr > 247u) {
        return false;
    }

    for (group = 0u; group < LUMIA_GROUP_COUNT; ++group) {
        const LumiaGroupInnerConfig *inner = &config->groups[group];
        if (inner->inner_mode < 1u || inner->inner_mode > 4u ||
            inner->hue > 359u) {
            return false;
        }
    }
    return true;
}

static void encode_payload(const PersistentConfig *config, uint8_t *payload)
{
    uint8_t group;

    memset(payload, 0, CONFIG_STORE_PAYLOAD_SIZE);
    payload[0] = config->scene_mode;
    payload[1] = config->scene_param;
    payload[2] = config->device_addr;
    payload[3] = config->led_global_bri;
    payload[4] = config->led_gain_r;
    payload[5] = config->led_gain_g;
    payload[6] = config->led_gain_b;
    for (group = 0u; group < LUMIA_GROUP_COUNT; ++group) {
        uint16_t base = (uint16_t)(8u + group * 6u);
        const LumiaGroupInnerConfig *inner = &config->groups[group];

        payload[base + 0u] = inner->inner_mode;
        put_u16_le(payload + base + 1u, inner->hue);
        payload[base + 3u] = inner->sat;
        payload[base + 4u] = inner->val;
        payload[base + 5u] = inner->inner_param;
    }
}

static bool decode_payload(const uint8_t *payload, PersistentConfig *config)
{
    uint8_t group;

    memset(config, 0, sizeof(*config));
    config->scene_mode = payload[0];
    config->scene_param = payload[1];
    config->device_addr = payload[2];
    config->led_global_bri = payload[3];
    config->led_gain_r = payload[4];
    config->led_gain_g = payload[5];
    config->led_gain_b = payload[6];
    for (group = 0u; group < LUMIA_GROUP_COUNT; ++group) {
        uint16_t base = (uint16_t)(8u + group * 6u);
        LumiaGroupInnerConfig *inner = &config->groups[group];

        inner->inner_mode = payload[base + 0u];
        inner->hue = get_u16_le(payload + base + 1u);
        inner->sat = payload[base + 3u];
        inner->val = payload[base + 4u];
        inner->inner_param = payload[base + 5u];
    }
    return config_is_valid(config);
}

static bool record_is_valid(const uint8_t record[CONFIG_STORE_RECORD_SIZE],
                            SlotInfo *slot)
{
    const uint8_t *payload = record + PAYLOAD_OFFSET;
    const uint8_t *commit = record + COMMIT_OFFSET;
    uint32_t sequence = get_u32_le(record + HDR_SEQUENCE_OFFSET);
    uint32_t payload_crc = get_u32_le(record + HDR_PAYLOAD_CRC_OFFSET);

    if (get_u32_le(record + HDR_MAGIC_OFFSET) != CONFIG_RECORD_MAGIC ||
        get_u16_le(record + HDR_VERSION_OFFSET) != CONFIG_RECORD_VERSION ||
        get_u16_le(record + HDR_HEADER_LEN_OFFSET) != CONFIG_HEADER_SIZE ||
        get_u16_le(record + HDR_PAYLOAD_LEN_OFFSET) != CONFIG_STORE_PAYLOAD_SIZE ||
        get_u16_le(record + HDR_RECORD_LEN_OFFSET) != CONFIG_STORE_RECORD_SIZE ||
        get_u32_le(record + HDR_STATE_OFFSET) != CONFIG_STATE_VALID ||
        get_u32_le(record + HDR_HEADER_CRC_OFFSET) != header_crc(record) ||
        payload_crc != crc32_bytes(payload, CONFIG_STORE_PAYLOAD_SIZE) ||
        get_u32_le(commit) != CONFIG_COMMIT_MAGIC ||
        get_u32_le(commit + 4u) != sequence ||
        get_u32_le(commit + 8u) != ~sequence ||
        get_u32_le(commit + 12u) != payload_crc) {
        return false;
    }

    slot->valid = decode_payload(payload, &slot->config);
    slot->sequence = sequence;
    return slot->valid;
}

static esp_err_t read_slot(uint32_t slot_index, SlotInfo *slot)
{
    uint8_t record[CONFIG_STORE_RECORD_SIZE];
    esp_err_t err = storage_backend_read(
        slot_index * CONFIG_STORE_SLOT_SIZE,
        record,
        sizeof(record));

    if (err != ESP_OK) {
        return err;
    }
    memset(slot, 0, sizeof(*slot));
    record_is_valid(record, slot);
    return ESP_OK;
}

static bool sequence_is_newer(uint32_t left, uint32_t right)
{
    return (int32_t)(left - right) > 0;
}

esp_err_t config_store_init(void)
{
    SlotInfo slots[CONFIG_SLOT_COUNT];
    uint32_t index;
    esp_err_t err = storage_backend_init();

    if (err != ESP_OK) {
        return err;
    }
    if (storage_backend_size() < CONFIG_SLOT_COUNT * CONFIG_STORE_SLOT_SIZE) {
        return ESP_ERR_INVALID_SIZE;
    }

    for (index = 0u; index < CONFIG_SLOT_COUNT; ++index) {
        err = read_slot(index, &slots[index]);
        if (err != ESP_OK) {
            return err;
        }
    }

    s_active_slot = -1;
    s_active_sequence = 0u;
    if (slots[0].valid) {
        s_active_slot = 0;
        s_active_sequence = slots[0].sequence;
    }
    if (slots[1].valid &&
        (s_active_slot < 0 ||
         sequence_is_newer(slots[1].sequence, s_active_sequence))) {
        s_active_slot = 1;
        s_active_sequence = slots[1].sequence;
    }
    s_initialized = true;
    return ESP_OK;
}

esp_err_t config_store_load(PersistentConfig *config, bool *found)
{
    SlotInfo slot;
    esp_err_t err;

    if (!s_initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    if (config == NULL || found == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    *found = false;
    if (s_active_slot < 0) {
        return ESP_OK;
    }

    err = read_slot((uint32_t)s_active_slot, &slot);
    if (err != ESP_OK) {
        return err;
    }
    if (!slot.valid) {
        return ESP_ERR_INVALID_CRC;
    }
    *config = slot.config;
    *found = true;
    return ESP_OK;
}

esp_err_t config_store_save(const PersistentConfig *config)
{
    uint8_t record[CONFIG_STORE_RECORD_SIZE];
    uint8_t verify[CONFIG_STORE_RECORD_SIZE];
    uint32_t target_slot;
    uint32_t sequence;
    uint32_t payload_crc;
    esp_err_t err;

    if (!s_initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    if (config == NULL || !config_is_valid(config)) {
        return ESP_ERR_INVALID_ARG;
    }

    target_slot = s_active_slot == 0 ? 1u : 0u;
    sequence = s_active_slot < 0 ? 1u : s_active_sequence + 1u;
    memset(record, 0xFF, sizeof(record));
    put_u32_le(record + HDR_MAGIC_OFFSET, CONFIG_RECORD_MAGIC);
    put_u16_le(record + HDR_VERSION_OFFSET, CONFIG_RECORD_VERSION);
    put_u16_le(record + HDR_HEADER_LEN_OFFSET, CONFIG_HEADER_SIZE);
    put_u16_le(record + HDR_PAYLOAD_LEN_OFFSET, CONFIG_STORE_PAYLOAD_SIZE);
    put_u16_le(record + HDR_RECORD_LEN_OFFSET, CONFIG_STORE_RECORD_SIZE);
    put_u32_le(record + HDR_SEQUENCE_OFFSET, sequence);
    encode_payload(config, record + PAYLOAD_OFFSET);
    payload_crc = crc32_bytes(record + PAYLOAD_OFFSET, CONFIG_STORE_PAYLOAD_SIZE);
    put_u32_le(record + HDR_PAYLOAD_CRC_OFFSET, payload_crc);
    put_u32_le(record + HDR_RESERVED_OFFSET, 0u);
    put_u32_le(record + HDR_HEADER_CRC_OFFSET, header_crc(record));
    put_u32_le(record + HDR_STATE_OFFSET, CONFIG_STATE_WRITING);

    err = storage_backend_erase(target_slot * CONFIG_STORE_SLOT_SIZE,
                                CONFIG_STORE_SLOT_SIZE);
    if (err != ESP_OK) {
        return err;
    }
    err = storage_backend_write(target_slot * CONFIG_STORE_SLOT_SIZE,
                                record,
                                COMMIT_OFFSET);
    if (err != ESP_OK) {
        return err;
    }
    err = storage_backend_read(target_slot * CONFIG_STORE_SLOT_SIZE,
                               verify,
                               COMMIT_OFFSET);
    if (err != ESP_OK || memcmp(record, verify, COMMIT_OFFSET) != 0) {
        return err != ESP_OK ? err : ESP_ERR_INVALID_RESPONSE;
    }

    put_u32_le(record + HDR_STATE_OFFSET, CONFIG_STATE_VALID);
    err = storage_backend_write(target_slot * CONFIG_STORE_SLOT_SIZE +
                                    HDR_STATE_OFFSET,
                                record + HDR_STATE_OFFSET,
                                sizeof(uint32_t));
    if (err != ESP_OK) {
        return err;
    }

    put_u32_le(record + COMMIT_OFFSET, CONFIG_COMMIT_MAGIC);
    put_u32_le(record + COMMIT_OFFSET + 4u, sequence);
    put_u32_le(record + COMMIT_OFFSET + 8u, ~sequence);
    put_u32_le(record + COMMIT_OFFSET + 12u, payload_crc);
    err = storage_backend_write(target_slot * CONFIG_STORE_SLOT_SIZE +
                                    COMMIT_OFFSET,
                                record + COMMIT_OFFSET,
                                CONFIG_COMMIT_SIZE);
    if (err != ESP_OK) {
        return err;
    }

    err = storage_backend_read(target_slot * CONFIG_STORE_SLOT_SIZE,
                               verify,
                               sizeof(verify));
    SlotInfo saved_slot;
    if (err != ESP_OK || !record_is_valid(verify, &saved_slot) ||
        saved_slot.sequence != sequence) {
        return err != ESP_OK ? err : ESP_ERR_INVALID_CRC;
    }

    s_active_slot = (int)target_slot;
    s_active_sequence = sequence;
    return ESP_OK;
}

int config_store_active_slot(void)
{
    return s_active_slot;
}

uint32_t config_store_active_sequence(void)
{
    return s_active_sequence;
}
