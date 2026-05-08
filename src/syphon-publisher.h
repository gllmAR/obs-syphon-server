/*
 * obs-syphon-server — output publishers (Program / Preview).
 *
 * A publisher is a Syphon server bound to one of OBS's outputs:
 *   - SY_OUT_PROGRAM : main canvas (obs_get_main_texture)
 *   - SY_OUT_PREVIEW : preview scene (currently mirrors program canvas)
 *
 * Each publisher can be enabled/disabled independently and at runtime.
 */
#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    SY_OUT_PROGRAM = 0,
    SY_OUT_PREVIEW = 1,
} sy_output_kind;

void syphon_publisher_init(void);
void syphon_publisher_shutdown(void);

bool        syphon_publisher_is_enabled(sy_output_kind kind);
void        syphon_publisher_set_enabled(sy_output_kind kind, bool enabled);
const char *syphon_publisher_name(sy_output_kind kind);

#ifdef __cplusplus
}
#endif
