/*
OBS Syphon Server Plugin - Output Implementation
Copyright (C) 2025 OBS Syphon Team
*/

#include "syphon_common.hpp"
#include <plugin-support.h>

struct sy_output_data {
    obs_output_t   *output;
    struct sy_server srv;
    bool            running;
    
    // Video conversion format
    uint32_t       width;
    uint32_t       height;
};

static const char *sy_output_get_name(void *data)
{
    UNUSED_PARAMETER(data);
    return obs_module_text("SyphonOutput.Name");
}

static void sy_output_update(void *data, obs_data_t *settings)
{
    struct sy_output_data *output_data = (struct sy_output_data *)data;
    const char *name = obs_data_get_string(settings, "syphon_server_name");
    
    if (!name || !*name) {
        name = "OBS Syphon Output";
    }
    
    // Update server name if changed
    if (!output_data->srv.name || strcmp(output_data->srv.name, name) != 0) {
        if (output_data->srv.name) {
            bfree(output_data->srv.name);
        }
        output_data->srv.name = bstrdup(name);
    }
}

static void *sy_output_create(obs_data_t *settings, obs_output_t *output)
{
    struct sy_output_data *data = (struct sy_output_data *)bzalloc(sizeof(struct sy_output_data));
    
    data->output = output;
    data->running = false;
    data->width = 0;
    data->height = 0;
    
    // Initialize Syphon server with default name
    const char *server_name = obs_data_get_string(settings, "syphon_server_name");
    if (!server_name || !*server_name) {
        server_name = "OBS-Output";
    }
    
    sy_server_init(&data->srv, server_name);
    sy_output_update(data, settings);
    
    obs_log(LOG_INFO, "[syphon] Output created: %s", server_name);
    
    return data;
}

static void sy_output_destroy(void *data)
{
    struct sy_output_data *output_data = (struct sy_output_data *)data;
    
    if (!output_data) {
        return;
    }
    
    sy_server_destroy(&output_data->srv);
    
    obs_log(LOG_INFO, "[syphon] Output destroyed");
    
    bfree(output_data);
}

static bool sy_output_start(void *data)
{
    struct sy_output_data *output_data = (struct sy_output_data *)data;
    
    if (!output_data->output) {
        obs_log(LOG_ERROR, "[syphon] Trying to start with no output!");
        return false;
    }
    
    output_data->width = (uint32_t)obs_output_get_width(output_data->output);
    output_data->height = (uint32_t)obs_output_get_height(output_data->output);
    
    video_t *video = obs_output_video(output_data->output);
    if (!video) {
        obs_log(LOG_ERROR, "[syphon] Trying to start with no video!");
        return false;
    }
    
    if (!obs_output_can_begin_data_capture(output_data->output, 0)) {
        obs_log(LOG_ERROR, "[syphon] Unable to begin data capture!");
        return false;
    }
    
    // Set up video conversion - use BGRA format which works well with Syphon
    video_scale_info info = {};
    info.format = VIDEO_FORMAT_BGRA;
    info.width = output_data->width;
    info.height = output_data->height;
    
    obs_output_set_video_conversion(output_data->output, &info);
    
    bool started = obs_output_begin_data_capture(output_data->output, 0);
    
    output_data->running = started;
    
    if (!started) {
        obs_log(LOG_ERROR, "[syphon] Unable to start capture!");
    } else {
        obs_log(LOG_INFO, "[syphon] Started capture: %s, %dx%d", 
                output_data->srv.name, output_data->width, output_data->height);
    }
    
    return started;
}

static void sy_output_stop(void *data, uint64_t ts)
{
    UNUSED_PARAMETER(ts);
    
    struct sy_output_data *output_data = (struct sy_output_data *)data;
    
    if (output_data->running) {
        obs_output_end_data_capture(output_data->output);
        output_data->running = false;
        
        obs_log(LOG_INFO, "[syphon] Stopped capture: %s", output_data->srv.name);
    }
}

// This is the key function that receives actual video frames!
static void sy_output_raw_video(void *data, struct video_data *frame)
{
    struct sy_output_data *output_data = (struct sy_output_data *)data;
    
    if (!output_data->running || !frame || !frame->data[0]) {
        return;
    }
    
    // Create a texture from the raw video data
    obs_enter_graphics();
    
    // Create texture with the frame data
    gs_texture_t *tex = gs_texture_create(output_data->width, output_data->height, 
                                         GS_BGRA, 1, (const uint8_t**)&frame->data[0], 
                                         GS_DYNAMIC);
    
    if (tex) {
        // Publish the texture to Syphon
        sy_server_publish_frame(&output_data->srv, tex, output_data->width, output_data->height);
        
        // Clean up the texture
        gs_texture_destroy(tex);
        
        // Log every 5 seconds (300 frames at 60fps)
        static int frame_counter = 0;
        frame_counter++;
        if (frame_counter % 300 == 0) {
            obs_log(LOG_INFO, "[syphon] Output processed frame #%d (%dx%d)", 
                    frame_counter, output_data->width, output_data->height);
        }
    } else {
        obs_log(LOG_WARNING, "[syphon] Failed to create texture from frame data");
    }
    
    obs_leave_graphics();
}

static obs_properties_t *sy_output_get_properties(void *data)
{
    UNUSED_PARAMETER(data);
    
    obs_properties_t *props = obs_properties_create();
    obs_properties_set_flags(props, OBS_PROPERTIES_DEFER_UPDATE);
    
    obs_properties_add_text(props, "syphon_server_name", 
                           obs_module_text("SyphonOutput.ServerName"), 
                           OBS_TEXT_DEFAULT);
    
    return props;
}

extern "C" {
void register_syphon_output()
{
    struct obs_output_info output_info = {};
    
    output_info.id           = "syphon_output";
    output_info.flags        = OBS_OUTPUT_VIDEO;
    output_info.get_name     = sy_output_get_name;
    output_info.create       = sy_output_create;
    output_info.destroy      = sy_output_destroy;
    output_info.start        = sy_output_start;
    output_info.stop         = sy_output_stop;
    output_info.update       = sy_output_update;
    output_info.raw_video    = sy_output_raw_video;  // This is the key callback!
    output_info.get_properties = sy_output_get_properties;
    
    obs_register_output(&output_info);
    
    obs_log(LOG_INFO, "[syphon] Registered Syphon server output");
}
}
