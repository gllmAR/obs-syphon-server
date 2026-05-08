/*
 * obs-syphon-server — output publishers (Program / Preview)
 *
 * A "publisher" is a Syphon server bound to one of OBS's outputs:
 *   - SY_OUT_PROGRAM : main canvas (obs_get_main_texture)
 *   - SY_OUT_PREVIEW : current preview scene in studio mode
 *                      (falls back to program canvas when studio mode is off)
 *
 * Each publisher can be enabled/disabled independently and at runtime.
 * The publishing path is fully GPU-side: no CPU readback or upload.
 */
#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    SY_OUT_PROGRAM = 0,
    SY_OUT_PREVIEW = 1,
    SY_OUT_COUNT
} sy_output_kind;

void syphon_publisher_init(void);    /* call once at module load   */
void syphon_publisher_shutdown(void); /* call once at module unload */

bool syphon_publisher_is_enabled(sy_output_kind kind);
void syphon_publisher_set_enabled(sy_output_kind kind, bool enabled);

const char *syphon_publisher_name(sy_output_kind kind);
const char *syphon_publisher_label(sy_output_kind kind); /* "Program" / "Preview" */

#ifdef __cplusplus
}
#endif
