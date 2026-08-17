idf_component_register(
    SRCS
        "resource_pack.c"
        "web_server.c"
        "wifi_channel_selector.c"
    INCLUDE_DIRS "include"
    REQUIRES
        esp_event
        esp_http_server
        esp_netif
        esp_wifi
        cjson
        lwip
        lumia_ota
        lumia_runtime
        spiffs
)

target_add_binary_data(
    ${COMPONENT_LIB}
    "${CMAKE_BINARY_DIR}/maurya_generated/web_core.pack"
    BINARY
)

target_compile_options(${COMPONENT_LIB} PRIVATE
    "-ULOG_LOCAL_LEVEL"
    "-DLOG_LOCAL_LEVEL=ESP_LOG_INFO")
