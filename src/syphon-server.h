/*
 * obs-syphon-server — Syphon server bridge (C-callable).
 *
 * One publish path: lock the server's IOSurface, memcpy BGRA8 rows
 * (optionally Y-flipped), unlock, [publish]. Safe from any thread.
 *
 * The IOSurface is reused across frames; only re-allocated when the
 * frame size changes.
 */
#pragma once

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct sy_server sy_server_t;

sy_server_t *sy_server_create(const char *name);
void         sy_server_destroy(sy_server_t *srv);

void         sy_server_set_name(sy_server_t *srv, const char *name);
bool         sy_server_has_clients(const sy_server_t *srv);

/* Publish a BGRA8 frame.
 *   data     : top-left of source frame, BGRA8
 *   linesize : source stride in bytes
 *   flip_y   : if true, source rows are written in reverse order */
void sy_server_publish_bgra(sy_server_t *srv,
                            const uint8_t *data, uint32_t linesize,
                            uint32_t width, uint32_t height,
                            bool flip_y);

#ifdef __cplusplus
}
#endif
