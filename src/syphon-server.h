/*
 * obs-syphon-server — Syphon server bridge (C-callable)
 *
 * Backend-agnostic: works with OBS's Metal renderer (Apple Silicon) and
 * the legacy OpenGL renderer. The server allocates an IOSurface, wraps it
 * as a gs_texture_t, and uses gs_copy_texture() to do the actual data move
 * — one GPU blit, no CPU touch.
 */
#pragma once

#include <obs-module.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct sy_server sy_server_t;

/* Create. Safe to call from any thread. */
sy_server_t *sy_server_create(const char *name);

/* Destroy. Calls sy_server_release_gs() automatically — but you should
 * still call sy_server_release_gs() yourself from the graphics thread
 * before this if you've used the GPU publish path. */
void sy_server_destroy(sy_server_t *srv);

/* Publish an OBS texture (pure GPU path).
 *
 * Performs a single GPU blit (gs_copy_texture) from `src` into a Syphon-
 * owned IOSurface-backed texture, then [publish]. Caller is responsible
 * for ensuring `src` already has the desired orientation and is a plain
 * BGRA8 texture (use a gs_texrender_t to normalise format/orientation).
 *
 * MUST be called on the OBS graphics thread (render callback or between
 * obs_enter_graphics/obs_leave_graphics). */
void sy_server_publish_texture(sy_server_t *srv, gs_texture_t *src, uint32_t width, uint32_t height);

/* Render-direct path (avoids any GPU copy).
 *
 * sy_server_get_render_target() returns an IOSurface-backed gs_texture_t
 * sized to (w, h). The first call (or after a size change) allocates it.
 * Bind it via gs_set_render_target(...), draw your content, restore the
 * previous render target, then call sy_server_publish() to flush the
 * IOSurface to attached Syphon clients.
 *
 * MUST be called on the OBS graphics thread. */
gs_texture_t *sy_server_get_render_target(sy_server_t *srv, uint32_t width, uint32_t height);
void sy_server_publish(sy_server_t *srv);

/* Publish raw BGRA pixel data (CPU path).
 * Safe to call from any thread (no OBS graphics context required).
 * `linesize` is the source stride in bytes. If `flip_y` is true, rows
 * are written in reverse order (use this to convert OBS's top-down
 * raw_video frames into Syphon's bottom-up convention). */
void sy_server_publish_bgra(sy_server_t *srv, const uint8_t *data, uint32_t linesize, uint32_t width, uint32_t height, bool flip_y);

/* Release any gs_texture_t the server is holding. Must be called from the
 * graphics thread. Idempotent. */
void sy_server_release_gs(sy_server_t *srv);

void sy_server_set_name(sy_server_t *srv, const char *name);
const char *sy_server_get_name(const sy_server_t *srv);
bool sy_server_has_clients(const sy_server_t *srv);

#ifdef __cplusplus
}
#endif
