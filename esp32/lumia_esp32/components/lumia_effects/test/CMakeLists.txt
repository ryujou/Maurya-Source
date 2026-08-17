cmake_minimum_required(VERSION 3.16)
project(lumia_effects_test C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_executable(
    lumia_effects_test
    "test_effect_engine.c"
    "../effect_engine.c"
    "../effect_inner.c"
    "../effect_inner_mode_steady.c"
    "../effect_inner_mode_breath.c"
    "../effect_inner_mode_strobe.c"
    "../effect_inner_mode_fade.c"
    "../effect_scene.c"
    "../effect_scene_mode_static.c"
    "../effect_scene_mode_chase_lr.c"
    "../effect_scene_mode_chase_rl.c"
    "../effect_scene_mode_pingpong.c"
)

target_include_directories(lumia_effects_test PRIVATE "../include" "..")
