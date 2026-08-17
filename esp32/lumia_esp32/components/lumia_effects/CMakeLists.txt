idf_component_register(
    SRCS
        "effect_engine.c"
        "effect_inner.c"
        "effect_inner_mode_steady.c"
        "effect_inner_mode_breath.c"
        "effect_inner_mode_strobe.c"
        "effect_inner_mode_fade.c"
        "effect_scene.c"
        "effect_scene_mode_static.c"
        "effect_scene_mode_chase_lr.c"
        "effect_scene_mode_chase_rl.c"
        "effect_scene_mode_pingpong.c"
    INCLUDE_DIRS "include"
)
