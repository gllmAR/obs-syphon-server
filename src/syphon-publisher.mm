/*
 * obs-syphon-server — Program / Preview publishers.
 *
 * Strategy: hook into OBS's main render via obs_add_main_rendered_callback,
 * gs_stage_texture() the already-rendered canvas into a staging surface,
 * map it, and memcpy a single time into the Syphon IOSurface.
 *
 * Why this beats the obs_output_t/raw_video CPU path:
 *   - Skips OBS's NV12→BGRA color-conversion pipeline (the dominant cost
 *     when we forced VIDEO_FORMAT_BGRA on raw_video — that's the source
 *     of the ~20% CPU at 1080p30 vs ~0% for mac-virtualcam, which uses
 *     the native NV12 format that OBS already produces for encoders).
 *   - Skips OBS's intermediate ring-buffer copy into raw_video frames.
 *   - On Apple Silicon (unified memory), gs_stage_texture is a near
 *     zero-copy GPU→CPU readback, then memcpy(staging→IOSurface) is a
 *     single shared-memory copy.
 *
 * Preview (studio mode): in this minimal cut, the Preview publisher
 * also taps the program canvas. A future revision can use obs_view +
 * obs_view_render to capture the preview scene independently.
 */

#include "syphon-publisher.h"
#include "syphon-server.h"
#include "plugin-support.h"

#include <obs-module.h>
#include <obs.h>
#include <obs-frontend-api.h>

#import <Foundation/Foundation.h>

struct pub_state {
    sy_server_t          *server;
    gs_stagesurf_t       *stage;
    uint32_t              width;
    uint32_t              height;
    enum gs_color_format  format;
    bool                  enabled;
    bool                  registered;
    const char           *server_name;
    const char           *label;
};

static struct pub_state g_prog = {.enabled = true,  .server_name = "OBS",         .label = "Program"};
static struct pub_state g_preview = {.enabled = false, .server_name = "OBS Preview", .label = "Preview"};

static void on_main_rendered(void *param)
{
    auto *s = static_cast<struct pub_state *>(param);
    if (!s || !s->enabled || !s->server)
        return;

    gs_texture_t *src = obs_get_main_texture();
    if (!src)
        return;

    uint32_t w = gs_texture_get_width(src);
    uint32_t h = gs_texture_get_height(src);
    enum gs_color_format fmt = gs_texture_get_color_format(src);
    if (w == 0 || h == 0)
        return;

    if (!s->stage || s->width != w || s->height != h || s->format != fmt) {
        if (s->stage) {
            gs_stagesurface_destroy(s->stage);
            s->stage = nullptr;
        }
        s->stage = gs_stagesurface_create(w, h, fmt);
        if (!s->stage) {
            obs_log(LOG_ERROR, "syphon-publisher (%s): gs_stagesurface_create %ux%u failed", s->label, w, h);
            return;
        }
        s->width = w;
        s->height = h;
        s->format = fmt;
    }

    /* GPU → CPU. ~zero-copy on Apple Silicon (shared memory). */
    gs_stage_texture(s->stage, src);

    uint8_t *data = nullptr;
    uint32_t linesize = 0;
    if (!gs_stagesurface_map(s->stage, &data, &linesize) || !data)
        return;

    /* Single memcpy into the Syphon IOSurface. OBS canvas is top-down;
     * Syphon clients expect bottom-up. */
    sy_server_publish_bgra(s->server, data, linesize, w, h, /*flip_y=*/true);

    gs_stagesurface_unmap(s->stage);
}

static void start(struct pub_state *s)
{
    if (s->server)
        return;
    s->server = sy_server_create(s->server_name);
    if (!s->server) {
        obs_log(LOG_ERROR, "syphon-publisher (%s): sy_server_create failed", s->label);
        return;
    }
    if (!s->registered) {
        obs_add_main_rendered_callback(on_main_rendered, s);
        s->registered = true;
    }
    obs_log(LOG_INFO, "syphon-publisher (%s): started → '%s'", s->label, s->server_name);
}

static void stop(struct pub_state *s)
{
    if (s->registered) {
        obs_remove_main_rendered_callback(on_main_rendered, s);
        s->registered = false;
    }
    if (s->stage) {
        obs_enter_graphics();
        gs_stagesurface_destroy(s->stage);
        obs_leave_graphics();
        s->stage = nullptr;
    }
    s->width = s->height = 0;
    if (s->server) {
        sy_server_destroy(s->server);
        s->server = nullptr;
        obs_log(LOG_INFO, "syphon-publisher (%s): stopped", s->label);
    }
}

extern "C" void syphon_publisher_init(void)
{
    if (g_prog.enabled)
        start(&g_prog);
    if (g_preview.enabled)
        start(&g_preview);
}

extern "C" void syphon_publisher_shutdown(void)
{
    stop(&g_prog);
    stop(&g_preview);
}

extern "C" bool syphon_publisher_is_enabled(sy_output_kind k)
{
    if (k == SY_OUT_PROGRAM)
        return g_prog.enabled;
    if (k == SY_OUT_PREVIEW)
        return g_preview.enabled;
    return false;
}

extern "C" void syphon_publisher_set_enabled(sy_output_kind k, bool enabled)
{
    struct pub_state *s = nullptr;
    if (k == SY_OUT_PROGRAM)
        s = &g_prog;
    else if (k == SY_OUT_PREVIEW)
        s = &g_preview;
    if (!s || s->enabled == enabled)
        return;
    s->enabled = enabled;
    if (enabled)
        start(s);
    else
        stop(s);
}

extern "C" const char *syphon_publisher_name(sy_output_kind k)
{
    if (k == SY_OUT_PROGRAM)
        return g_prog.server_name;
    if (k == SY_OUT_PREVIEW)
        return g_preview.server_name;
    return "";
}

extern "C" const char *syphon_publisher_label(sy_output_kind k)
{
    if (k == SY_OUT_PROGRAM)
        return g_prog.label;
    if (k == SY_OUT_PREVIEW)
        return g_preview.label;
    return "";
}
