idf_component_register(
    SRCS "modbus_crc.c" "modbus_frame.c" "modbus_server.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common lumia_runtime
)
