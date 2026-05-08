/*
 * obs-syphon-server — per-source Syphon publisher (filter).
 *
 * Default mode (passive):
 *   video_render() runs only when the parent source is being drawn.
 *   We render it into a Y-flipped texrender (GS_BGRA), publish via
 *   gs_stage_texture → map → memcpy → IOSurface, then draw the
 *   texrender back un-flipped (GS_FLIP_V) so OBS sees the source's
 *   normal orientation.
 *
 * Force-active mode (toggle "Always publish"):
 *   We register a main render callback so the parent is rendered and
 *   published every frame regardless of scene visibility, and call
 *   obs_source_inc_showing(parent) so async sources keep decoding.
 *   In this mode video_render() skips the publish path (the callback
 *   owns publishing) and just passes the source through.
 *
 * Why we copy via gs_stagesurface and not gs_copy_texture:
 *   On macOS, OBS wraps IOSurfaces as GL_TEXTURE_RECTANGLE_ARB while
 *   texrenders are GL_TEXTURE_2D. glCopyImageSubData silently rejects
 *   mismatched targets → black frames. The staging path is reliable
 *   and on Apple Silicon is essentially zero-copy GPU→CPU (unified
 *   memory) plus one shared-memory memcpy.
 */

#include "syphon-server.h"
#include "plugin-support.h"

#include <obs-module.h>

#define S_SERVER_NAME    "server_name"
#define S_FORCE_ACTIVE   "force_active"
#define DEFAULT_NAME     "OBS Source"

struct sy_filter {
    obs_source_t   *source;
    sy_server_t    *server;
    gs_texrender_t *texrender;
    gs_stagesurf_t *stage;
    uint32_t        width;
    uint32_t        height;
    char           *name;
    bool            force_active;
    bool            cb_registered;
    bool            showing_held;
};

static void render_and_publish(sy_filter *f, obs_source_t *target, uint32_t w, uint32_t h);
static void on_main_render(void *param, uint32_t cx, uint32_t cy);

/* ─── name / defaults / properties ────────────────────────────────────── */

static const char *sy_filter_get_name(void *unused)
{
    (void) unused;
    return obs_module_text("SyphonFilter.Name");
}

static void sy_filter_get_defaults(obs_data_t *settings)
{
    obs_data_set_default_string(settings, S_SERVER_NAME, DEFAULT_NAME);
    obs_data_set_default_bool(settings, S_FORCE_ACTIVE, false);
}

static obs_properties_t *sy_filter_get_properties(void *data)
{
    (void) data;
    obs_properties_t *p = obs_properties_create();
    obs_properties_add_text(p, S_SERVER_NAME, obs_module_text("SyphonFilter.ServerName"), OBS_TEXT_DEFAULT);
    obs_properties_add_bool(p, S_FORCE_ACTIVE, obs_module_text("SyphonFilter.ForceActive"));
    return p;
}

/* ─── force-active wiring ─────────────────────────────────────────────── */

static void enable_force_active(sy_filter *f)
{
    if (f->cb_registered)
        return;
    obs_source_t *parent = obs_filter_get_parent(f->source);
    if (parent && !f->showing_held) {
        obs_source_inc_showing(parent);
        f->showing_held = true;
    }
    obs_add_main_render_callback(on_main_render, f);
    f->cb_registered = true;
}

static void disable_force_active(sy_filter *f)
{
    if (f->cb_registered) {
        obs_remove_main_render_callback(on_main_render, f);
        f->cb_registered = false;
    }
    if (f->showing_held) {
        obs_source_t *parent = obs_filter_get_parent(f->source);
        if (parent)
            obs_source_dec_showing(parent);
        f->showing_held = false;
    }
}

/* ─── update / create / destroy ───────────────────────────────────────── */

static void sy_filter_update(void *data, obs_data_t *settings)
{
    auto *f = static_cast<sy_filter *>(data);

    const char *new_name = obs_data_get_string(settings, S_SERVER_NAME);
    if (!new_name || !*new_name)
        new_name = DEFAULT_NAME;
    if (!f->name || strcmp(f->name, new_name) != 0) {
        bfree(f->name);
        f->name = bstrdup(new_name);
        if (f->server)
            sy_server_set_name(f->server, f->name);
    }

    bool want_force = obs_data_get_bool(settings, S_FORCE_ACTIVE);
    if (want_force != f->force_active) {
        f->force_active = want_force;
        if (want_force) enable_force_active(f);
        else            disable_force_active(f);
    }
}

static void *sy_filter_create(obs_data_t *settings, obs_source_t *source)
{
    auto *f = static_cast<sy_filter *>(bzalloc(sizeof(sy_filter)));
    f->source = source;

    const char *initial = obs_data_get_string(settings, S_SERVER_NAME);
    if (!initial || !*initial)
        initial = DEFAULT_NAME;
    f->name = bstrdup(initial);

    obs_enter_graphics();
    f->texrender = gs_texrender_create(GS_BGRA, GS_ZS_NONE);
    obs_leave_graphics();

    f->server = sy_server_create(f->name);
    if (!f->server)
        obs_log(LOG_WARNING, "syphon filter: server '%s' could not be created", f->name);

    if (obs_data_get_bool(settings, S_FORCE_ACTIVE)) {
        f->force_active = true;
        enable_force_active(f);
    }

    return f;
}

static void sy_filter_destroy(void *data)
{
    auto *f = static_cast<sy_filter *>(data);
    if (!f)
        return;

    disable_force_active(f);

    obs_enter_graphics();
    if (f->stage)
        gs_stagesurface_destroy(f->stage);
    if (f->texrender)
        gs_texrender_destroy(f->texrender);
    obs_leave_graphics();

    if (f->server)
        sy_server_destroy(f->server);
    bfree(f->name);
    bfree(f);
}

/* ─── publish path (shared by both modes) ─────────────────────────────── */

static void render_and_publish(sy_filter *f, obs_source_t *target, uint32_t w, uint32_t h)
{
    if (!f->server || !sy_server_has_clients(f->server))
        return;

    gs_texrender_reset(f->texrender);
    if (!gs_texrender_begin(f->texrender, w, h))
        return;

    struct vec4 clear;
    vec4_zero(&clear);
    gs_clear(GS_CLEAR_COLOR, &clear, 0.0f, 0);
    gs_ortho(0.0f, (float) w, (float) h, 0.0f, -100.0f, 100.0f);

    gs_blend_state_push();
    gs_blend_function(GS_BLEND_ONE, GS_BLEND_ZERO);
    obs_source_video_render(target);
    gs_blend_state_pop();

    gs_texrender_end(f->texrender);

    gs_texture_t *tex = gs_texrender_get_texture(f->texrender);
    if (!tex)
        return;

    if (!f->stage || f->width != w || f->height != h) {
        if (f->stage)
            gs_stagesurface_destroy(f->stage);
        f->stage = gs_stagesurface_create(w, h, GS_BGRA);
        f->width = w;
        f->height = h;
    }
    if (!f->stage)
        return;

    gs_stage_texture(f->stage, tex);
    uint8_t *bgra = nullptr;
    uint32_t linesize = 0;
    if (gs_stagesurface_map(f->stage, &bgra, &linesize) && bgra) {
        sy_server_publish_bgra(f->server, bgra, linesize, w, h, /*flip_y=*/false);
        gs_stagesurface_unmap(f->stage);
    }
}

/* ─── main render callback (force-active mode) ────────────────────────── */

static void on_main_render(void *param, uint32_t cx, uint32_t cy)
{
    (void) cx; (void) cy;
    auto *f = static_cast<sy_filter *>(param);
    if (!f || !f->force_active)
        return;

    obs_source_t *target = obs_filter_get_target(f->source);
    if (!target)
        return;

    const uint32_t w = obs_source_get_base_width(target);
    const uint32_t h = obs_source_get_base_height(target);
    if (w == 0 || h == 0)
        return;

    render_and_publish(f, target, w, h);
}

/* ─── per-source video_render (passive mode) ──────────────────────────── */

static void sy_filter_video_render(void *data, gs_effect_t *unused)
{
    (void) unused;
    auto *f = static_cast<sy_filter *>(data);

    /* Force-active mode publishes from the render callback; here we
     * just pass the source through unchanged. */
    if (f->force_active) {
        obs_source_skip_video_filter(f->source);
        return;
    }

    obs_source_t *target = obs_filter_get_target(f->source);
    if (!target || !obs_filter_get_parent(f->source)) {
        obs_source_skip_video_filter(f->source);
        return;
    }

    const uint32_t w = obs_source_get_base_width(target);
    const uint32_t h = obs_source_get_base_height(target);
    if (w == 0 || h == 0) {
        obs_source_skip_video_filter(f->source);
        return;
    }

    render_and_publish(f, target, w, h);

    gs_texture_t *tex = gs_texrender_get_texture(f->texrender);
    if (tex) {
        gs_effect_t *eff = obs_get_base_effect(OBS_EFFECT_DEFAULT);
        gs_eparam_t *image = gs_effect_get_param_by_name(eff, "image");
        gs_effect_set_texture(image, tex);
        while (gs_effect_loop(eff, "Draw"))
            gs_draw_sprite(tex, GS_FLIP_V, w, h);
    } else {
        obs_source_skip_video_filter(f->source);
    }
}

/* ─── source size proxies ─────────────────────────────────────────────── */

static uint32_t sy_filter_get_width(void *data)
{
    auto *f = static_cast<sy_filter *>(data);
    obs_source_t *t = obs_filter_get_target(f->source);
    return t ? obs_source_get_base_width(t) : 0;
}

static uint32_t sy_filter_get_height(void *data)
{
    auto *f = static_cast<sy_filter *>(data);
    obs_source_t *t = obs_filter_get_target(f->source);
    return t ? obs_source_get_base_height(t) : 0;
}

extern "C" struct obs_source_info syphon_filter_info;
struct obs_source_info syphon_filter_info = {
    .id = "syphon_server_filter",
    .type = OBS_SOURCE_TYPE_FILTER,
    .output_flags = OBS_SOURCE_VIDEO,
    .get_name = sy_filter_get_name,
    .create = sy_filter_create,
    .destroy = sy_filter_destroy,
    .get_width = sy_filter_get_width,
    .get_height = sy_filter_get_height,
    .get_defaults = sy_filter_get_defaults,
    .get_properties = sy_filter_get_properties,
    .update = sy_filter_update,
    .video_render = sy_filter_video_render,
};
