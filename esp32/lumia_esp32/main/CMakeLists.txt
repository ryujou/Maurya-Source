idf_component_register(
    SRCS "app_main.c"
    REQUIRES
        esp_timer
        esp_partition
        spi_flash
        lumia_effects
        lumia_effect_session
        lumia_monitor
        lumia_platform
        lumia_protocol
        lumia_runtime
        lumia_storage
        lumia_ota
        lumia_web
)

# USB Modbus remains available for diagnostics; keep the release image's
# per-module logging to warnings/errors so the signed OTA slot has headroom.
target_compile_options(${COMPONENT_LIB} PRIVATE
    "-ULOG_LOCAL_LEVEL"
    "-DLOG_LOCAL_LEVEL=ESP_LOG_WARN")
