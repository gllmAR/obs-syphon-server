/*
OBS Syphon Server Plugin - Common Implementation
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

#import "syphon_common.hpp"
#import <plugin-support.h>
#import <CoreVideo/CoreVideo.h>

// GL_SILENCE_DEPRECATION is now defined in CMakeLists.txt
#import <OpenGL/gl.h>

// Use the local Syphon headers, not the system ones
#import "SyphonOpenGLServer.h"

// Global server for main output
static struct sy_server *g_main_server = NULL;
static obs_output_t *g_main_output = NULL;
static bool g_output_active = false;

// Output callbacks
static void main_output_raw_video(void *data, struct video_data *frame)
{
    UNUSED_PARAMETER(data);

    if (!g_main_server || !g_main_server->server || !frame || !g_output_active) {
        return;
    }

    if (!g_main_output) {
        return;
    }

    // Get output dimensions
    uint32_t width = obs_output_get_width(g_main_output);
    uint32_t height = obs_output_get_height(g_main_output);

    if (width == 0 || height == 0 || !frame->data[0]) {
        return;
    }

    // Log for debugging
    static int frame_counter = 0;
    frame_counter++;

    if (frame_counter % 300 == 0) {  // Log every 5 seconds at 60fps
        obs_log(LOG_INFO, "[syphon] RAW VIDEO: Frame #%d, %dx%d, linesize=%d", frame_counter, width, height,
                frame->linesize[0]);

        // Check if frame data has content
        uint8_t *pixels = (uint8_t *) frame->data[0];
        bool hasContent = false;
        for (int i = 0; i < 12 && i < frame->linesize[0]; i++) {
            if (pixels[i] > 10) {
                hasContent = true;
                break;
            }
        }
        obs_log(LOG_INFO, "[syphon] Frame content: %s", hasContent ? "HAS CONTENT" : "APPEARS BLACK");
    }

    // Send raw frame data to Syphon - follow Spout pattern
    sy_server_publish_raw_frame(g_main_server, (uint8_t *) frame->data[0], width, height, frame->linesize[0]);
}

static bool main_output_start(obs_output_t *output)
{
    UNUSED_PARAMETER(output);

    if (!obs_output_can_begin_data_capture(output, 0)) {
        obs_log(LOG_ERROR, "[syphon] Unable to begin data capture for main output");
        return false;
    }

    // Set video format to BGRA for better compatibility with Syphon
    video_scale_info info {};
    info.format = VIDEO_FORMAT_BGRA;
    info.width = obs_output_get_width(output);
    info.height = obs_output_get_height(output);

    obs_output_set_video_conversion(output, &info);

    bool started = obs_output_begin_data_capture(output, 0);

    if (started) {
        g_output_active = true;
        obs_log(LOG_INFO, "[syphon] Main output data capture started: %dx%d", info.width, info.height);
    } else {
        obs_log(LOG_ERROR, "[syphon] Failed to start main output data capture");
    }

    return started;
}

static void main_output_stop(obs_output_t *output, uint64_t ts)
{
    UNUSED_PARAMETER(ts);

    if (g_output_active) {
        obs_output_end_data_capture(output);
        g_output_active = false;
        obs_log(LOG_INFO, "[syphon] Main output data capture stopped");
    }
}

void sy_server_init(struct sy_server *srv, const char *name)
{
    if (!srv || !name) {
        return;
    }

    memset(srv, 0, sizeof(struct sy_server));
    srv->name = bstrdup(name);
    srv->is_metal = false;

    NSString *serverName = [NSString stringWithUTF8String:name];

    // Use OBS's OpenGL context
    obs_enter_graphics();
    CGLContextObj context = CGLGetCurrentContext();

    if (context) {
        // Create Syphon server with minimal options - only use available options
        NSDictionary *options = @{SyphonServerOptionIsPrivate: @NO};

        srv->server = [[SyphonOpenGLServer alloc] initWithName:serverName context:context options:options];

        if (srv->server) {
            obs_log(LOG_INFO, "[syphon] Created OpenGL server '%s' with OBS context %p", name, context);

            // Log server description for debugging
            NSDictionary *serverDescription = [srv->server serverDescription];
            obs_log(LOG_INFO, "[syphon] Server description: %s", [[serverDescription description] UTF8String]);
        } else {
            obs_log(LOG_ERROR, "[syphon] Failed to create OpenGL server: %s", name);
        }
    } else {
        obs_log(LOG_ERROR, "[syphon] No OpenGL context available for server: %s", name);
    }

    obs_leave_graphics();
}

void sy_server_destroy(struct sy_server *srv)
{
    if (!srv) {
        return;
    }

    if (srv->server) {
        [srv->server stop];
        srv->server = nil;
    }

    if (srv->name) {
        bfree(srv->name);
        srv->name = NULL;
    }

    obs_log(LOG_INFO, "[syphon] Server destroyed");
}

void sy_server_publish_frame(struct sy_server *srv, gs_texture_t *tex, uint32_t width, uint32_t height)
{
    if (!srv || !tex || width == 0 || height == 0) {
        obs_log(LOG_WARNING, "[syphon] Invalid parameters for publish_frame: srv=%p, tex=%p, %dx%d", srv, tex, width,
                height);
        return;
    }

    if (!srv->server) {
        obs_log(LOG_WARNING, "[syphon] No Syphon server available for '%s'", srv->name);
        return;
    }

    // Get the OpenGL texture ID
    GLuint textureID = (GLuint) (uintptr_t) gs_texture_get_obj(tex);

    if (textureID == 0) {
        obs_log(LOG_WARNING, "[syphon] Invalid texture ID (0) for server '%s'", srv->name);
        return;
    }

    NSRect imageRegion = NSMakeRect(0, 0, width, height);
    NSSize textureDimensions = NSMakeSize(width, height);

    // Publish the frame - try both flipped and non-flipped to see which works
    [srv->server publishFrameTexture:textureID textureTarget:GL_TEXTURE_2D imageRegion:imageRegion
                   textureDimensions:textureDimensions
                             flipped:YES];

    // Log publishing status less frequently
    static int log_counter = 0;

    if (log_counter % 300 == 0) {  // Log every 5 seconds at 60fps
        obs_log(LOG_INFO, "[syphon] Server '%s': Publishing %dx%d (texture ID %u)", srv->name, width, height,
                textureID);

        // Check if server has clients
        if ([srv->server hasClients]) {
            obs_log(LOG_INFO, "[syphon] Server '%s' has active clients", srv->name);
        } else {
            obs_log(LOG_INFO, "[syphon] Server '%s' has no clients (but still publishing for discovery)", srv->name);
        }
    }
    log_counter++;
}

void sy_server_publish_raw_frame(struct sy_server *srv, uint8_t *data, uint32_t width, uint32_t height,
                                 uint32_t linesize)
{
    if (!srv || !data || width == 0 || height == 0) {
        obs_log(LOG_WARNING, "[syphon] Invalid parameters for publish_raw_frame: srv=%p, data=%p, %dx%d", srv, data,
                width, height);
        return;
    }

    if (!srv->server) {
        obs_log(LOG_WARNING, "[syphon] No Syphon server available for '%s'", srv->name);
        return;
    }

    obs_enter_graphics();

    // Create an OpenGL texture from the raw data
    // The data comes from OBS as BGRA format (since we set VIDEO_FORMAT_BGRA)
    GLuint textureID;
    glGenTextures(1, &textureID);
    glBindTexture(GL_TEXTURE_2D, textureID);

    // Set texture parameters
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    // Upload the frame data to the texture
    // Note: OBS gives us data with a linesize that might be different from width
    if (linesize == width * 4) {
        // Data is packed, can upload directly
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_BGRA, GL_UNSIGNED_BYTE, data);
    } else {
        // Data has padding, need to upload row by row
        glPixelStorei(GL_UNPACK_ROW_LENGTH, linesize / 4);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_BGRA, GL_UNSIGNED_BYTE, data);
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    }

    if (textureID != 0) {
        NSRect imageRegion = NSMakeRect(0, 0, width, height);
        NSSize textureDimensions = NSMakeSize(width, height);

        // Publish the frame to Syphon
        [srv->server publishFrameTexture:textureID textureTarget:GL_TEXTURE_2D imageRegion:imageRegion
                       textureDimensions:textureDimensions
                                 flipped:YES];

        // Log publishing status less frequently
        static int log_counter = 0;

        if (log_counter % 300 == 0) {  // Log every 5 seconds at 60fps
            obs_log(LOG_INFO, "[syphon] Server '%s': Publishing raw frame %dx%d (texture ID %u, linesize %d)",
                    srv->name, width, height, textureID, linesize);

            // Check if server has clients
            if ([srv->server hasClients]) {
                obs_log(LOG_INFO, "[syphon] Server '%s' has active clients", srv->name);
            } else {
                obs_log(LOG_INFO, "[syphon] Server '%s' has no clients (but still publishing for discovery)",
                        srv->name);
            }
        }
        log_counter++;
    }

    // Clean up the texture
    glDeleteTextures(1, &textureID);

    obs_leave_graphics();
}

// Output callback functions for OBS output registration
static const char *syphon_main_output_get_name(void *unused)
{
    UNUSED_PARAMETER(unused);
    return "Syphon Main Output";
}

static void *syphon_main_output_create(obs_data_t *settings, obs_output_t *output)
{
    UNUSED_PARAMETER(settings);
    UNUSED_PARAMETER(output);
    return (void *) 1;  // Just return non-null
}

static void syphon_main_output_destroy(void *data)
{
    UNUSED_PARAMETER(data);
}

static bool syphon_main_output_start(void *data)
{
    UNUSED_PARAMETER(data);
    return main_output_start(g_main_output);
}

static void syphon_main_output_stop(void *data, uint64_t ts)
{
    UNUSED_PARAMETER(data);
    main_output_stop(g_main_output, ts);
}

static void syphon_main_output_raw_video(void *data, struct video_data *frame)
{
    UNUSED_PARAMETER(data);
    main_output_raw_video(data, frame);
}

// Main server management functions
void sy_start_main_server(const char *name)
{
    if (g_main_server) {
        obs_log(LOG_WARNING, "[syphon] Main server already running");
        return;
    }

    g_main_server = (struct sy_server *) bzalloc(sizeof(struct sy_server));
    sy_server_init(g_main_server, name ? name : "OBS-Main");

    if (!g_main_server->server) {
        obs_log(LOG_ERROR, "[syphon] Failed to create Syphon server");
        bfree(g_main_server);
        g_main_server = NULL;
        return;
    }

    // Create output info structure similar to Spout plugin
    struct obs_output_info output_info = {};
    output_info.id = "syphon_main_output";
    output_info.flags = OBS_OUTPUT_VIDEO;
    output_info.get_name = syphon_main_output_get_name;
    output_info.create = syphon_main_output_create;
    output_info.destroy = syphon_main_output_destroy;
    output_info.start = syphon_main_output_start;
    output_info.stop = syphon_main_output_stop;
    output_info.raw_video = syphon_main_output_raw_video;

    // Register the output type
    obs_register_output(&output_info);

    // Create the output
    obs_data_t *settings = obs_data_create();
    g_main_output = obs_output_create("syphon_main_output", "Syphon Main Output", settings, NULL);
    obs_data_release(settings);

    if (!g_main_output) {
        obs_log(LOG_ERROR, "[syphon] Failed to create main output");
        sy_server_destroy(g_main_server);
        bfree(g_main_server);
        g_main_server = NULL;
        return;
    }

    // Set up video output - connect to main video
    video_t *video = obs_get_video();
    if (!video) {
        obs_log(LOG_ERROR, "[syphon] No video available");
        obs_output_release(g_main_output);
        g_main_output = NULL;
        sy_server_destroy(g_main_server);
        bfree(g_main_server);
        g_main_server = NULL;
        return;
    }

    obs_output_set_media(g_main_output, video, obs_get_audio());

    // Start the output
    if (!obs_output_start(g_main_output)) {
        obs_log(LOG_ERROR, "[syphon] Failed to start main output");
        obs_output_release(g_main_output);
        g_main_output = NULL;
        sy_server_destroy(g_main_server);
        bfree(g_main_server);
        g_main_server = NULL;
        return;
    }

    obs_log(LOG_INFO, "[syphon] Main server started with output pipeline");
}

void sy_stop_main_server(void)
{
    if (g_main_output) {
        obs_output_stop(g_main_output);
        obs_output_release(g_main_output);
        g_main_output = NULL;
        obs_log(LOG_INFO, "[syphon] Main output stopped");
    }

    if (g_main_server) {
        sy_server_destroy(g_main_server);
        bfree(g_main_server);
        g_main_server = NULL;
        obs_log(LOG_INFO, "[syphon] Main server stopped");
    }
}

bool sy_main_server_running(void)
{
    return g_main_server != NULL && g_main_server->server != nil && g_main_output != NULL;
}
