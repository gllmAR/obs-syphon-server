/*
 * obs-syphon-server — Syphon server bridge.
 *
 * Wraps a SyphonServerBase subclass that owns a single reusable
 * IOSurface. Frames are published via memcpy into the surface.
 */

#include "syphon-server.h"
#include "plugin-support.h"

#include <obs-module.h>

#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#import "SyphonServerBase.h"
#import "SyphonSubclassing.h"

@interface SyphonOBSServer : SyphonServerBase {
@public
    IOSurfaceRef surface;
    uint32_t     surface_width;
    uint32_t     surface_height;
}
@end

@implementation SyphonOBSServer
@end

struct sy_server {
    SyphonOBSServer *server;
    NSString        *name;
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

static void release_surface(SyphonOBSServer *s)
{
    if (s->surface) {
        CFRelease(s->surface);
        s->surface = nullptr;
    }
    s->surface_width = 0;
    s->surface_height = 0;
}

void sy_server_destroy(sy_server_t *srv)
{
    if (!srv)
        return;
    @autoreleasepool {
        if (srv->server) {
            release_surface(srv->server);
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

bool sy_server_has_clients(const sy_server_t *srv)
{
    return (srv && srv->server) ? (bool) srv->server.hasClients : false;
}

void sy_server_publish_bgra(sy_server_t *srv,
                            const uint8_t *data, uint32_t linesize,
                            uint32_t w, uint32_t h, bool flip_y)
{
    if (!srv || !srv->server || !data || w == 0 || h == 0)
        return;

    SyphonOBSServer *s = srv->server;

    if (!s->surface || s->surface_width != w || s->surface_height != h) {
        release_surface(s);
        s->surface = [s newSurfaceForWidth:w height:h options:nil];
        if (!s->surface) {
            obs_log(LOG_ERROR, "sy_server_publish_bgra: newSurface failed (%ux%u)", w, h);
            return;
        }
        s->surface_width = w;
        s->surface_height = h;
    }

    IOSurfaceLock(s->surface, 0, NULL);
    uint8_t *dst = (uint8_t *) IOSurfaceGetBaseAddress(s->surface);
    const size_t dst_stride = IOSurfaceGetBytesPerRow(s->surface);
    const size_t row_bytes = (size_t) w * 4;

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
    IOSurfaceUnlock(s->surface, 0, NULL);

    [s publish];
}
