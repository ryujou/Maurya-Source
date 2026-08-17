idf_component_register(
    SRCS
        "ota_session.c"
        "ota_service.c"
    INCLUDE_DIRS "include"
    REQUIRES
        app_update
        esp_app_format
        esp_http_server
        esp_partition
        esp_timer
        freertos
        mbedtls
        nvs_flash
)

# OTA runs only during maintenance and should not carry verbose log strings in
# the signed application image. Warnings and errors remain available on USB.
target_compile_options(${COMPONENT_LIB} PRIVATE
    "-ULOG_LOCAL_LEVEL"
    "-DLOG_LOCAL_LEVEL=ESP_LOG_WARN")
