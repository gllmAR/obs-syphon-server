/*
 * obs-syphon-server — per-source Syphon publisher (filter)
 *
 * Pipeline (one render pass, one CPU staging copy):
 *   1. Render the parent source into a Y-flipped texrender (GS_BGRA).
 *   2. gs_stage_texture(stage, texrender) → gs_stagesurface_map →
 *      sy_server_publish_bgra (single memcpy into Syphon IOSurface).
 *   3. Draw the texrender back to OBS un-flipped (GS_FLIP_V) so the
 *      filter is transparent in OBS.
 *
 * Why not gs_copy_texture(iosurface_tex, texrender)?
 *   On macOS, OBS wraps IOSurfaces as GL_TEXTURE_RECTANGLE_ARB while
 *   texrenders are GL_TEXTURE_2D. glCopyImageSubData (the default copy
 *   path) silently rejects mismatched targets → black frames.
 *
 * On Apple Silicon, gs_stage_texture is essentially zero-copy GPU→CPU
 * (unified memory), and the memcpy into the IOSurface is one shared-
 * memory copy.
 */

#include "syphon-server.h"
#include "plugin-support.h"

#include <obs-module.h>

#import <Foundation/Foundation.h>

#define S_SERVER_NAME "server_name"
#define DEFAULT_NAME  "OBS Source"

struct sy_filter {
    obs_source_t   *source;
    sy_server_t    *server;
    gs_texrender_t *texrender;
    gs_stagesurf_t *stage;
    uint32_t        width;
    uint32_t        height;
    char           *name;
};

static const char *sy_filter_get_name(void *unused)
{
    (void) unused;
    return obs_module_text("SyphonFilter.Name");
}

static void sy_filter_get_defaults(obs_data_t *settings)
{
    obs_data_set_default_string(settings, S_SERVER_NAME, DEFAULT_NAME);
}

static obs_properties_t *sy_filter_get_properties(void *data)
{
    (void) data;
    obs_properties_t *p = obs_properties_create();
    obs_properties_add_text(p, S_SERVER_NAME, obs_module_text("SyphonFilter.ServerName"), OBS_TEXT_DEFAULT);
    return p;
}

static void sy_filter_update(void *data, obs_data_t *settings)
{
    auto *f = static_cast<sy_filter *>(data);
    const char *new_name = obs_data_get_string(settings, S_SERVER_NAME);
    if (!new_name || !*new_name)
        new_name = DEFAULT_NAME;
    if (f->name && strcmp(f->name, new_name) == 0)
        return;
    bfree(f->name);
    f->name = bstrdup(new_name);
    if (f->server)
        sy_server_set_name(f->server, f->name);
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

    return f;
}

static void sy_filter_destroy(void *data)
{
    auto *f = static_cast<sy_filter *>(data);
    if (!f)
        return;

    obs_enter_graphics();
    if (f->server)
        sy_server_release_gs(f->server);
    if (f->stage) {
        gs_stagesurface_destroy(f->stage);
        f->stage = nullptr;
    }
    if (f->texrender) {
        gs_texrender_destroy(f->texrender);
        f->texrender = nullptr;
    }
    obs_leave_graphics();

    if (f->server) {
        sy_server_destroy(f->server);
        f->server = nullptr;
    }
    bfree(f->name);
    bfree(f);
}

static void sy_filter_video_render(void *data, gs_effect_t *unused)
{
    (void) unused;
    auto *f = static_cast<sy_filter *>(data);

    obs_source_t *target = obs_filter_get_target(f->source);
    obs_source_t *parent = obs_filter_get_parent(f->source);
    if (!target || !parent) {
        obs_source_skip_video_filter(f->source);
        return;
    }

    uint32_t w = obs_source_get_base_width(target);
    uint32_t h = obs_source_get_base_height(target);
    if (w == 0 || h == 0) {
        obs_source_skip_video_filter(f->source);
        return;
    }

    /* Render the source into our texrender (one GPU pass, Y-flipped for
     * Syphon convention). */
    gs_texrender_reset(f->texrender);
    if (!gs_texrender_begin(f->texrender, w, h)) {
        obs_source_skip_video_filter(f->source);
        return;
    }

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

    /* GPU → CPU staging readback (zero-copy on Apple Silicon), then
     * single memcpy into the Syphon IOSurface. */
    if (f->server) {
        if (!f->stage || f->width != w || f->height != h) {
            if (f->stage)
                gs_stagesurface_destroy(f->stage);
            f->stage = gs_stagesurface_create(w, h, GS_BGRA);
            f->width = w;
            f->height = h;
        }
        if (f->stage) {
            gs_stage_texture(f->stage, tex);
            uint8_t *data = nullptr;
            uint32_t linesize = 0;
            if (gs_stagesurface_map(f->stage, &data, &linesize) && data) {
                /* texrender is already Y-flipped via the ortho above, so
                 * copy direct (no flip). */
                sy_server_publish_bgra(f->server, data, linesize, w, h, /*flip_y=*/false);
                gs_stagesurface_unmap(f->stage);
            }
        }
    }

    /* Draw the captured texture back as the filter's own output, un-flipped
     * (GS_FLIP_V) so OBS sees the source orientation. */
    gs_effect_t *eff = obs_get_base_effect(OBS_EFFECT_DEFAULT);
    gs_eparam_t *image = gs_effect_get_param_by_name(eff, "image");
    gs_effect_set_texture(image, tex);
    while (gs_effect_loop(eff, "Draw"))
        gs_draw_sprite(tex, GS_FLIP_V, w, h);
}

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
