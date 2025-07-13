/*
OBS Syphon Server Plugin - Main Server Implementation  
Uses the main view approach to capture the main output texture
*/

#include "syphon_common.hpp"
#include <plugin-support.h>

// Check if we have the new API (OBS 29.1.0+)
#if LIBOBS_API_VER >= MAKE_SEMANTIC_VERSION(29, 1, 0)
#define USE_RENDERED_CALLBACK
#endif

struct syphon_main_server {
    struct sy_server srv;
    bool             rendered;
    gs_texture_t    *cached_texture;
    bool             active;
};

static struct syphon_main_server *g_main_server = NULL;

static void syphon_main_rendered_callback(void *data)
{
    struct syphon_main_server *server = (struct syphon_main_server *)data;
    
    if (!server || !server->active) {
        return;
    }
    
    // Prevent multiple calls per frame
    if (server->rendered) {
        return;
    }
    
    // Get the main texture from OBS
    gs_texture_t *tex = obs_get_main_texture();
    if (!tex) {
        return;
    }
    
    server->rendered = true;
    
    // Cache the texture
    uint32_t width = gs_texture_get_width(tex);
    uint32_t height = gs_texture_get_height(tex);
    enum gs_color_format format = gs_texture_get_color_format(tex);
    
    gs_texture_t *dst_tex = server->cached_texture;
    
    if (!dst_tex || gs_texture_get_width(dst_tex) != width || 
        gs_texture_get_height(dst_tex) != height ||
        gs_texture_get_color_format(dst_tex) != format) {
        gs_texture_destroy(dst_tex);
        dst_tex = server->cached_texture = 
            gs_texture_create(width, height, format, 1, NULL, GS_RENDER_TARGET);
    }
    
    if (dst_tex) {
        gs_copy_texture(dst_tex, tex);
        
        // Publish to Syphon
        sy_server_publish_frame(&server->srv, dst_tex, width, height);
    }
}

static void syphon_main_reset_rendering(void *data, float seconds)
{
    UNUSED_PARAMETER(seconds);
    struct syphon_main_server *server = (struct syphon_main_server *)data;
    
    if (server) {
        server->rendered = false;
    }
}

extern "C" {

void syphon_main_server_start(void)
{
    if (g_main_server) {
        return; // Already running
    }

    // Use the new output pipeline approach instead of the old main texture approach
    sy_start_main_server("OBS-Main");
    
    // Mark as active for compatibility
    g_main_server = (struct syphon_main_server *)bzalloc(sizeof(struct syphon_main_server));
    g_main_server->active = true;
    
    obs_log(LOG_INFO, "[syphon] Main server started using output pipeline");
}

void syphon_main_server_stop(void)
{
    if (!g_main_server) {
        return;
    }
    
    // Stop the output pipeline
    sy_stop_main_server();
    
    // Cleanup our placeholder structure
    g_main_server->active = false;
    bfree(g_main_server);
    g_main_server = NULL;
    
    obs_log(LOG_INFO, "[syphon] Main server stopped");
}

bool syphon_main_server_is_running(void)
{
    return g_main_server != NULL && g_main_server->active;
}

} // extern "C"
