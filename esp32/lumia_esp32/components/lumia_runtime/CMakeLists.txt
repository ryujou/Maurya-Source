idf_component_register(
    SRCS "runtime_state.c" "register_map.c"
    INCLUDE_DIRS "include"
    REQUIRES freertos
)
