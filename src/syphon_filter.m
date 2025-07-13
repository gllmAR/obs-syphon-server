/*
OBS Syphon Server Plugin - Filter Implementation
Copyright (C) 2025 OBS Syphon Team

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program. If not, see <https://www.gnu.org/licenses/>
*/

#include "syphon_wrapper.h"
#include <plugin-support.h>
#include <obs-module.h>
#include <stdint.h>

struct sy_filter_data {
    obs_source_t *source;
    SyphonServerRef syphon_server;
    gs_texrender_t *texrender;
};

static const char *sy_filter_get_name(void *data)
{
    UNUSED_PARAMETER(data);
    return obs_module_text("SyphonFilter.Name");
}

static void *sy_filter_create(obs_data_t *settings, obs_source_t *source)
{
    struct sy_filter_data *data = (struct sy_filter_data *)bzalloc(sizeof(struct sy_filter_data));
    
    data->source = source;
    data->texrender = gs_texrender_create(GS_RGBA, GS_ZS_NONE);
    
    // Get server name from settings
    const char *server_name = obs_data_get_string(settings, "server_name");
    if (!server_name || !*server_name) {
        server_name = "OBS-Filter";
    }
    
    // Get OpenGL context
    obs_enter_graphics();
    void* gl_context = gs_get_context();
    obs_leave_graphics();
    
    // Create Syphon server using dynamic wrapper
    data->syphon_server = syphon_wrapper_create_server(server_name, gl_context);
    
    obs_log(LOG_INFO, "[syphon] Filter created with server name: %s", server_name);
    
    return data;
}

static void sy_filter_destroy(void *data)
{
    struct sy_filter_data *filter = (struct sy_filter_data *)data;
    
    if (filter) {
        if (filter->syphon_server) {
            syphon_wrapper_destroy_server(filter->syphon_server);
        }
        
        if (filter->texrender) {
            gs_texrender_destroy(filter->texrender);
        }
        
        obs_log(LOG_INFO, "[syphon] Filter destroyed");
        bfree(filter);
    }
}

static void sy_filter_update(void *data, obs_data_t *settings)
{
    struct sy_filter_data *filter = (struct sy_filter_data *)data;
    
    if (!filter) {
        return;
    }
    
    // Update server name if changed
    const char *server_name = obs_data_get_string(settings, "server_name");
    if (server_name && *server_name) {
        // Destroy existing server
        if (filter->syphon_server) {
            syphon_wrapper_destroy_server(filter->syphon_server);
        }
        
        // Create new server with updated name
        obs_enter_graphics();
        void* gl_context = gs_get_context();
        obs_leave_graphics();
        filter->syphon_server = syphon_wrapper_create_server(server_name, gl_context);
        obs_log(LOG_INFO, "[syphon] Filter server name updated to: %s", server_name);
    }
}

static void sy_filter_render(void *data, gs_effect_t *effect)
{
    UNUSED_PARAMETER(effect);
    struct sy_filter_data *filter = (struct sy_filter_data *)data;
    
    if (!filter || !filter->source) {
        return;
    }
    
    // Get the target source (the source this filter is applied to)
    obs_source_t *target = obs_filter_get_target(filter->source);
    if (!target) {
        return;
    }
    
    uint32_t width = obs_source_get_width(target);
    uint32_t height = obs_source_get_height(target);
    
    if (!width || !height) {
        obs_source_video_render(target);
        return;
    }
    
    // Render to our texture to capture the frame
    gs_texrender_reset(filter->texrender);
    if (gs_texrender_begin(filter->texrender, width, height)) {
        // Clear and set up viewport
        gs_clear(GS_CLEAR_COLOR, NULL, 0.0f, 0);
        gs_ortho(0.0f, (float)width, 0.0f, (float)height, -100.0f, 100.0f);
        
        // Render the child source
        obs_source_video_render(target);
        
        gs_texrender_end(filter->texrender);
        
        // Get the rendered texture and publish it to Syphon
        gs_texture_t *tex = gs_texrender_get_texture(filter->texrender);
        if (tex && filter->syphon_server) {
            // Get texture ID for Syphon (cast void* to uint32_t)
            uint32_t texture_id = (uint32_t)(uintptr_t)gs_texture_get_obj(tex);
            syphon_wrapper_publish_frame(filter->syphon_server, texture_id, width, height);
            
            // Log filter activity occasionally
            static int filter_log_counter = 0;
            if (filter_log_counter % 120 == 0) { // Every 2 seconds at 60fps
                obs_log(LOG_INFO, "[syphon] Filter publishing %dx%d frame from source '%s'", 
                        width, height, obs_source_get_name(filter->source));
            }
            filter_log_counter++;
        }
    }
    
    // Also render normally to the output
    obs_source_video_render(target);
}

static obs_properties_t *sy_filter_get_properties(void *data)
{
    UNUSED_PARAMETER(data);
    
    obs_properties_t *props = obs_properties_create();
    
    obs_properties_add_text(props, "server_name", 
                           obs_module_text("SyphonFilter.ServerName"), 
                           OBS_TEXT_DEFAULT);
    
    return props;
}

static void sy_filter_get_defaults(obs_data_t *settings)
{
    obs_data_set_default_string(settings, "server_name", "OBS-Filter");
}

static uint32_t sy_filter_get_width(void *data)
{
    struct sy_filter_data *filter = (struct sy_filter_data *)data;
    
    if (!filter || !filter->source) {
        return 0;
    }
    
    obs_source_t *target = obs_filter_get_target(filter->source);
    return target ? obs_source_get_width(target) : 0;
}

static uint32_t sy_filter_get_height(void *data)
{
    struct sy_filter_data *filter = (struct sy_filter_data *)data;
    
    if (!filter || !filter->source) {
        return 0;
    }
    
    obs_source_t *target = obs_filter_get_target(filter->source);
    return target ? obs_source_get_height(target) : 0;
}

struct obs_source_info sy_filter_info = {
    .id = "syphon_server_filter",
    .type = OBS_SOURCE_TYPE_FILTER,
    .output_flags = OBS_SOURCE_VIDEO,
    .get_name = sy_filter_get_name,
    .create = sy_filter_create,
    .destroy = sy_filter_destroy,
    .update = sy_filter_update,
    .video_render = sy_filter_render,
    .get_properties = sy_filter_get_properties,
    .get_defaults = sy_filter_get_defaults,
    .get_width = sy_filter_get_width,
    .get_height = sy_filter_get_height
};
