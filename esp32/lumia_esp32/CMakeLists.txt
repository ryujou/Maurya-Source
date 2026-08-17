cmake_minimum_required(VERSION 3.16)

if(NOT DEFINED PROJECT_VER)
    set(PROJECT_VER "1.8.2")
endif()
set(MAURYA_SECURE_VERSION "182" CACHE STRING
    "Monotonic Maurya OTA release number (does not burn eFuse)")

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(lumia_esp32)

# Populate esp_app_desc.secure_version without enabling eFuse anti-rollback.
# Maurya compares this monotonically in the signed OTA service, while keeping
# USB recovery possible and avoiding any irreversible fuse write.
target_compile_definitions(__idf_esp_app_format PRIVATE
    CONFIG_BOOTLOADER_APP_SECURE_VERSION=${MAURYA_SECURE_VERSION})

set(MAURYA_GENERATED_DIR "${CMAKE_BINARY_DIR}/maurya_generated"
    CACHE INTERNAL "Maurya generated resource directory")
set(MAURYA_ASSETS_DIR "${MAURYA_GENERATED_DIR}/assetsfs"
    CACHE INTERNAL "Maurya generated asset filesystem directory")
file(MAKE_DIRECTORY "${MAURYA_ASSETS_DIR}")
file(GLOB_RECURSE MAURYA_WEB_INPUTS CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/web/*")
execute_process(
    COMMAND
        "${PYTHON}" "${CMAKE_SOURCE_DIR}/tools/build_resource_packs.py"
        --web-root "${CMAKE_SOURCE_DIR}/web"
        --assets-pack "${MAURYA_ASSETS_DIR}/assets.pack"
        --core-pack "${MAURYA_GENERATED_DIR}/web_core.pack"
    RESULT_VARIABLE MAURYA_PACK_RESULT
)
if(NOT MAURYA_PACK_RESULT EQUAL 0)
    message(FATAL_ERROR "Maurya resource pack generation failed")
endif()

spiffs_create_partition_image(assetsfs "${MAURYA_ASSETS_DIR}" FLASH_IN_PROJECT)
