/*
 * obs-syphon-server — Program / Preview publishers.
 *
 * Hooks obs_add_main_rendered_callback. Per frame, when at least one
 * Syphon client is attached:
 *   gs_stage_texture(obs_get_main_texture()) → map → memcpy into Syphon
 *   IOSurface (Y-flipped, since OBS canvas is top-down).
 * When no client is attached the entire readback is skipped.
 *
 * Preview (studio mode): currently mirrors the program canvas. A future
 * revision can use obs_view + obs_view_render to capture the preview
 * scene independently.
 */

#include "syphon-publisher.h"
#include "syphon-server.h"
#include "plugin-support.h"

#include <obs-module.h>
#include <obs.h>
#include <obs-frontend-api.h>
#include <util/config-file.h>

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

static struct pub_state g_prog    = {.enabled = true,  .server_name = "OBS",         .label = "Program"};
static struct pub_state g_preview = {.enabled = false, .server_name = "OBS Preview", .label = "Preview"};

static void on_main_rendered(void *param)
{
    auto *s = static_cast<struct pub_state *>(param);
    if (!s || !s->enabled || !s->server)
        return;

    /* Skip the readback entirely when no client is connected. */
    if (!sy_server_has_clients(s->server))
        return;

    gs_texture_t *src = obs_get_main_texture();
    if (!src)
        return;

    const uint32_t w = gs_texture_get_width(src);
    const uint32_t h = gs_texture_get_height(src);
    const enum gs_color_format fmt = gs_texture_get_color_format(src);
    if (w == 0 || h == 0)
        return;

    if (!s->stage || s->width != w || s->height != h || s->format != fmt) {
        if (s->stage)
            gs_stagesurface_destroy(s->stage);
        s->stage = gs_stagesurface_create(w, h, fmt);
        if (!s->stage) {
            obs_log(LOG_ERROR, "syphon-publisher (%s): gs_stagesurface_create %ux%u failed", s->label, w, h);
            return;
        }
        s->width = w;
        s->height = h;
        s->format = fmt;
    }

    gs_stage_texture(s->stage, src);

    uint8_t *data = nullptr;
    uint32_t linesize = 0;
    if (!gs_stagesurface_map(s->stage, &data, &linesize) || !data)
        return;

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

#define SY_CONFIG_SECTION "SyphonServer"
#define SY_CONFIG_KEY_PROG "ProgramEnabled"
#define SY_CONFIG_KEY_PREV "PreviewEnabled"

static bool load_state(const char *key, bool default_val)
{
    config_t *cfg = obs_frontend_get_user_config();
    if (!cfg)
        return default_val;
    config_set_default_bool(cfg, SY_CONFIG_SECTION, key, (int)default_val);
    return (bool)config_get_bool(cfg, SY_CONFIG_SECTION, key);
}

static void save_state(const char *key, bool enabled)
{
    config_t *cfg = obs_frontend_get_user_config();
    if (!cfg)
        return;
    config_set_bool(cfg, SY_CONFIG_SECTION, key, (int)enabled);
    config_save(cfg);
}

extern "C" void syphon_publisher_init(void)
{
    g_prog.enabled    = load_state(SY_CONFIG_KEY_PROG, true);
    g_preview.enabled = load_state(SY_CONFIG_KEY_PREV, false);
    if (g_prog.enabled)    start(&g_prog);
    if (g_preview.enabled) start(&g_preview);
}

extern "C" void syphon_publisher_shutdown(void)
{
    stop(&g_prog);
    stop(&g_preview);
}

static struct pub_state *state_for(sy_output_kind k)
{
    if (k == SY_OUT_PROGRAM) return &g_prog;
    if (k == SY_OUT_PREVIEW) return &g_preview;
    return nullptr;
}

extern "C" bool syphon_publisher_is_enabled(sy_output_kind k)
{
    struct pub_state *s = state_for(k);
    return s ? s->enabled : false;
}

extern "C" void syphon_publisher_set_enabled(sy_output_kind k, bool enabled)
{
    struct pub_state *s = state_for(k);
    if (!s || s->enabled == enabled)
        return;
    s->enabled = enabled;
    if (enabled) start(s);
    else         stop(s);
    const char *key = (k == SY_OUT_PROGRAM) ? SY_CONFIG_KEY_PROG : SY_CONFIG_KEY_PREV;
    save_state(key, enabled);
}

extern "C" const char *syphon_publisher_name(sy_output_kind k)
{
    struct pub_state *s = state_for(k);
    return s ? s->server_name : "";
}
