/*
OBS Syphon Server Plugin
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

#pragma once

#ifdef __OBJC__
// Use local headers to avoid framework path issues
#include "SyphonOpenGLServer.h"
#import <Metal/Metal.h>
#import <OpenGL/OpenGL.h>
#import <Cocoa/Cocoa.h>
#endif

#include <obs-module.h>
#include <graphics/graphics.h>
#include <graphics/matrix4.h>
#include <util/platform.h>

#ifdef __cplusplus
extern "C" {
#endif

// Forward declarations for Objective-C types when not in Objective-C context
#ifndef __OBJC__
typedef void* SyphonOpenGLServer;
typedef void* SyphonMetalServer;
#endif

// Common server structure
struct sy_server {
#ifdef __OBJC__
    SyphonOpenGLServer *server;
    void (^publish)(gs_texture_t *tex, uint32_t width, uint32_t height);
#else
    void *server;
    void *publish;
#endif
    bool is_metal;
    char *name;
};

// Function declarations
void sy_server_init(struct sy_server *srv, const char *name);
void sy_server_destroy(struct sy_server *srv);
void sy_server_publish_frame(struct sy_server *srv, gs_texture_t *tex, uint32_t width, uint32_t height);
void sy_server_publish_raw_frame(struct sy_server *srv, uint8_t *data, uint32_t width, uint32_t height, uint32_t linesize);

// Main server functions for automatic capture
void syphon_main_server_start(void);
void syphon_main_server_stop(void);
bool syphon_main_server_is_running(void);

// Main server management functions
void sy_start_main_server(const char *name);
void sy_stop_main_server(void);
bool sy_main_server_running(void);

#ifdef __cplusplus
}
#endif
