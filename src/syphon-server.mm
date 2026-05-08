/*
 * obs-syphon-server — Syphon server bridge.
 *
 * SyphonOBSServer is a SyphonServerBase subclass (no GL/Metal —
 * backend-agnostic on macOS).
 *
 * Two publish paths are exposed:
 *
 *   GPU path (sy_server_publish_texture)
 *     gs_copy_texture(iosurface_tex, src) → [publish].
 *     Caller must hold the OBS graphics context. Single GPU blit.
 *     Requires src to be plain BGRA8 in the same format as the
 *     IOSurface — otherwise the blit silently no-ops.
 *
 *   CPU path (sy_server_publish_bgra)
 *     Lock the IOSurface, memcpy BGRA rows (optionally Y-flipped),
 *     unlock, [publish]. Safe from any thread. Used by the obs_output
 *     raw_video pipeline, where OBS guarantees a plain BGRA8 frame.
 */

#include "syphon-server.h"
#include "plugin-support.h"

#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#import "SyphonServerBase.h"
#import "SyphonSubclassing.h"

@interface SyphonOBSServer : SyphonServerBase {
@public
    /* GPU path */
    gs_texture_t *gs_tex;
    uint32_t      gpu_width;
    uint32_t      gpu_height;

    /* CPU path */
    IOSurfaceRef  cpu_surface;
    uint32_t      cpu_width;
    uint32_t      cpu_height;
}
@end

@implementation SyphonOBSServer
@end

struct sy_server {
    SyphonOBSServer *server;
    NSString *name;
};

sy_server_t *sy_server_create(const char *name)
{
    @autoreleasepool {
        NSString *nsname = [NSString stringWithUTF8String:(name && *name) ? name : "OBS"];
        SyphonOBSServer *server = [[SyphonOBSServer alloc] initWithName:nsname options:nil];
        if (!server) {
            obs_log(LOG_ERROR, "sy_server_create('%s'): SyphonServerBase init failed", [nsname UTF8String]);
            return nullptr;
        }
        sy_server_t *srv = (sy_server_t *) bzalloc(sizeof(sy_server_t));
        srv->server = server;
        srv->name = nsname;
        obs_log(LOG_INFO, "sy_server_create: published '%s'", [nsname UTF8String]);
        return srv;
    }
}

void sy_server_release_gs(sy_server_t *srv)
{
    if (!srv || !srv->server)
        return;
    if (srv->server->gs_tex) {
        gs_texture_destroy(srv->server->gs_tex);
        srv->server->gs_tex = nullptr;
    }
    srv->server->gpu_width = 0;
    srv->server->gpu_height = 0;
}

static void sy_release_cpu(SyphonOBSServer *s)
{
    if (s->cpu_surface) {
        CFRelease(s->cpu_surface);
        s->cpu_surface = nullptr;
    }
    s->cpu_width = 0;
    s->cpu_height = 0;
}

void sy_server_destroy(sy_server_t *srv)
{
    if (!srv)
        return;
    @autoreleasepool {
        if (srv->server) {
            sy_server_release_gs(srv);
            sy_release_cpu(srv->server);
            [srv->server stop];
            srv->server = nil;
        }
        srv->name = nil;
    }
    bfree(srv);
}

void sy_server_set_name(sy_server_t *srv, const char *name)
{
    if (!srv || !srv->server || !name)
        return;
    @autoreleasepool {
        NSString *nsname = [NSString stringWithUTF8String:name];
        if ([nsname isEqualToString:srv->name])
            return;
        srv->name = nsname;
        srv->server.name = nsname;
    }
}

const char *sy_server_get_name(const sy_server_t *srv)
{
    return (srv && srv->name) ? [srv->name UTF8String] : "";
}

bool sy_server_has_clients(const sy_server_t *srv)
{
    return (srv && srv->server) ? (bool) srv->server.hasClients : false;
}

void sy_server_publish_texture(sy_server_t *srv, gs_texture_t *src, uint32_t w, uint32_t h)
{
    if (!srv || !srv->server || !src || w == 0 || h == 0)
        return;

    SyphonOBSServer *s = srv->server;

    if (!s->gs_tex || s->gpu_width != w || s->gpu_height != h) {
        if (s->gs_tex) {
            gs_texture_destroy(s->gs_tex);
            s->gs_tex = nullptr;
        }
        IOSurfaceRef surface = [s newSurfaceForWidth:w height:h options:nil];
        if (!surface) {
            obs_log(LOG_ERROR, "sy_server_publish_texture: newSurfaceForWidth failed (%ux%u)", w, h);
            return;
        }
        s->gs_tex = gs_texture_create_from_iosurface(surface);
        CFRelease(surface);
        if (!s->gs_tex) {
            obs_log(LOG_ERROR, "sy_server_publish_texture: gs_texture_create_from_iosurface failed");
            return;
        }
        s->gpu_width = w;
        s->gpu_height = h;
    }

    gs_copy_texture(s->gs_tex, src);
    [s publish];
}

gs_texture_t *sy_server_get_render_target(sy_server_t *srv, uint32_t w, uint32_t h)
{
    if (!srv || !srv->server || w == 0 || h == 0)
        return nullptr;

    SyphonOBSServer *s = srv->server;

    if (!s->gs_tex || s->gpu_width != w || s->gpu_height != h) {
        if (s->gs_tex) {
            gs_texture_destroy(s->gs_tex);
            s->gs_tex = nullptr;
        }
        IOSurfaceRef surface = [s newSurfaceForWidth:w height:h options:nil];
        if (!surface) {
            obs_log(LOG_ERROR, "sy_server_get_render_target: newSurfaceForWidth failed (%ux%u)", w, h);
            return nullptr;
        }
        s->gs_tex = gs_texture_create_from_iosurface(surface);
        CFRelease(surface);
        if (!s->gs_tex) {
            obs_log(LOG_ERROR, "sy_server_get_render_target: gs_texture_create_from_iosurface failed");
            return nullptr;
        }
        s->gpu_width = w;
        s->gpu_height = h;
    }
    return s->gs_tex;
}

void sy_server_publish(sy_server_t *srv)
{
    if (!srv || !srv->server)
        return;
    [srv->server publish];
}

void sy_server_publish_bgra(sy_server_t *srv, const uint8_t *data, uint32_t linesize, uint32_t w, uint32_t h, bool flip_y)
{
    if (!srv || !srv->server || !data || w == 0 || h == 0)
        return;

    SyphonOBSServer *s = srv->server;

    if (!s->cpu_surface || s->cpu_width != w || s->cpu_height != h) {
        if (s->cpu_surface) {
            CFRelease(s->cpu_surface);
            s->cpu_surface = nullptr;
        }
        s->cpu_surface = [s newSurfaceForWidth:w height:h options:nil];
        if (!s->cpu_surface) {
            obs_log(LOG_ERROR, "sy_server_publish_bgra: newSurface failed (%ux%u)", w, h);
            return;
        }
        s->cpu_width = w;
        s->cpu_height = h;
    }

    IOSurfaceLock(s->cpu_surface, 0, NULL);
    uint8_t *dst = (uint8_t *) IOSurfaceGetBaseAddress(s->cpu_surface);
    size_t dst_stride = IOSurfaceGetBytesPerRow(s->cpu_surface);
    size_t row_bytes = (size_t) w * 4;

    if (flip_y) {
        for (uint32_t y = 0; y < h; y++) {
            const uint8_t *src_row = data + (size_t) (h - 1 - y) * linesize;
            memcpy(dst + (size_t) y * dst_stride, src_row, row_bytes);
        }
    } else if (linesize == dst_stride && linesize == row_bytes) {
        memcpy(dst, data, dst_stride * (size_t) h);
    } else {
        for (uint32_t y = 0; y < h; y++)
            memcpy(dst + (size_t) y * dst_stride, data + (size_t) y * linesize, row_bytes);
    }
    IOSurfaceUnlock(s->cpu_surface, 0, NULL);

    [s publish];
}
