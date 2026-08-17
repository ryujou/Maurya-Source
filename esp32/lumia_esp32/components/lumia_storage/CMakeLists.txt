idf_component_register(
    SRCS
        "storage_backend.c"
        "config_store.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_partition lumia_runtime
)
