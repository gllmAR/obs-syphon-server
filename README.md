# **obs‑syphon‑server** – Technical Design & Implementation Guide

---

## 0 Context & Naming

*Working title*: **obs‑syphon‑server**
We intentionally mirror the naming of **DistroAV** (formerly *OBS‑NDI*) because our functional map is almost 1‑to‑1 – replacing the NDI transport layer with **Syphon** on macOS.

*Plugin id strings*:

| Feature                              | C identifier           | UI label                    |
| ------------------------------------ | ---------------------- | --------------------------- |
| **Program feed publisher**           | `syphon_server_output` | *Syphon ‑ Main Output*      |
| **Dedicated source/scene publisher** | `syphon_server_filter` | *Syphon ‑ Dedicated Output* |

---

## 1 Project Goals & Milestones

| Phase  | Deliverable                                                                         | Reference implementation in **DistroAV**                                               |
| ------ | ----------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| **P1** | Working **Syphon server** that publishes the active *Program* framebuffer.          | `src/ndi-output/ndi-output.cpp` (`ndi_output_info` + `obs_output_update()` life‑cycle) |
| **P2** | **Filter** that can be attached to any scene/source to publish that single texture. | `src/ndi-filter/ndi-filter.cpp` (`obs_source_info` + `video_render`)                   |
| **P3** | Qt dock for start/stop & server‑name field, universal2 binary, codesigning.         | `tools/qt/ndi-settings.cpp`                                                            |
| **P4** | Metal path, colour‑space tags, multi‑feed support (Program+Preview).                | DistroAV ≥ 6.0 multi‑output branch                                                     |

We treat **P1** and **P2** as hard Requirements; everything else is “reach”.

---

## 2 Key External References

| Topic                      | Source                                                                                                                   | Why it matters                                                                                          |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| DistroAV output life‑cycle | [`DistroAV/src/ndi-output/ndi-output.cpp`](https://github.com/DistroAV/DistroAV/blob/main/src/ndi-output/ndi-output.cpp) | Shows a battle‑tested pattern for *obs\_output\_info* with proper `start`/`stop`/`raw_video` callbacks. |
| DistroAV filter pattern    | [`DistroAV/src/ndi-filter/ndi-filter.cpp`](https://github.com/DistroAV/DistroAV/blob/main/src/ndi-filter/ndi-filter.cpp) | Minimal filter that publishes its last rendered texture each frame.                                     |
| Graphics device helpers    | [`libobs/graphics/gs-*`](https://github.com/obsproject/obs-studio/tree/master/libobs/graphics)                           | `gs_get_device_type()`, `gs_texture_get_mtl_texture()`.                                                 |
| Syphon Metal path          | [`SyphonMetalServer.h`](https://github.com/Syphon/Syphon-Framework/blob/main/SyphonMetalServer.h)                        | How to publish `id<MTLTexture>` directly.                                                               |
| Syphon GL path             | [`SyphonServer.h`](https://github.com/Syphon/Syphon-Framework/blob/main/SyphonServer.h)                                  | Legacy GL publishing.                                                                                   |

---

## 3 Architecture (Phase 1 & 2)

```mermaid
graph TD
    subgraph OBS Core
        R[Render Thread]
        O[obs_output_info<br>"syphon_server_output"]
        F[obs_source_info<br>"syphon_server_filter"]
    end
    subgraph Transport Layer
        S[(SyphonServer /<br>SyphonMetalServer)]
    end
    R -->|framebuffer RGBA| O -->|publishFrameTexture| S
    R --> F --> S
```

*Program output* (`O`) mirrors DistroAV’s *NDI Output*, but we only need un‑encoded RGBA.
*Filter* (`F`) copies DistroAV’s *NDI Filter* verbatim – except the transport call.

---

## 4 Phase‑1 Implementation: **Program Publisher**

### 4.1 File: `syphon_output.mm`

```cpp
struct sy_output_data {
    obs_output_t   *context = nullptr;
    gs_texrender_t *tex     = nullptr;
    sy_server       srv;          // see common header
    bool            running = false;
};
```

| Callback    | DistroAV analogue      | Core logic                                                             |
| ----------- | ---------------------- | ---------------------------------------------------------------------- |
| `create`    | `ndi_output_create`    | `gs_texrender_create`; init Syphon server with name **"OBS‑Program"**. |
| `start`     | `ndi_output_start`     | `running=true;` return `true`.                                         |
| `stop`      | `ndi_output_stop`      | `_stop_server()`, `running=false`.                                     |
| `raw_video` | `ndi_output_raw_video` | Render Program scene ➜ `gs_texrender_end` ➜ `publishFrameTexture`.     |
| `destroy`   | same                   | Free texture; `[srv.server stop]`.                                     |

> **Tip:** Copy the log pattern from DistroAV (`blog(LOG_INFO, "[syphon] …")`) for easy grep.

### 4.2 Graphics Backend Switch

```cpp
bool metal = gs_get_device_type() == GS_DEVICE_TYPE_METAL;
if (metal) {
    id<MTLDevice> dev = gs_mtl_get_device();
    srv.server = [[SyphonMetalServer alloc] initWithName:name device:dev options:nil];
    srv.publish = ^(gs_texture_t *tex, uint32_t w, uint32_t h){
        [srv.server publishFrameTexture:gs_texture_get_mtl_texture(tex)
                            imageRegion:NSMakeRect(0,0,w,h)
                               frameTime:CVGetCurrentHostTime()];};
} else {
    CGLContextObj ctx = CGLGetCurrentContext();
    srv.server = [[SyphonServer alloc] initWithName:name context:ctx options:nil];
    srv.publish = ^(gs_texture_t *tex, uint32_t w, uint32_t h){
        GLuint id = gs_texture_get_ogl_name(tex);
        [srv.server publishFrameTexture:id textureTarget:GL_TEXTURE_2D imageRegion:NSMakeRect(0,0,w,h) frameTime:CVGetCurrentHostTime()];};
}
```

---

## 5 Phase‑2 Implementation: **Dedicated Output Filter**

### 5.1 File: `syphon_filter.mm`

*Clone* DistroAV’s filter skeleton (<20 LOC):

```cpp
struct sy_filter_data {
    sy_server srv;
};

static void sy_filter_render(void *data, gs_effect_t *)
{
    auto *d = static_cast<sy_filter_data *>(data);
    obs_source_t *target = obs_filter_get_target(filter);
    if (!target) return;

    // Draw child source
    obs_source_video_render(target);

    // Publish last texture
    gs_texture_t *tex = obs_filter_get_last_tex(filter);
    if (tex && d->srv.server) {
        d->srv.publish(tex, gs_texture_get_width(tex), gs_texture_get_height(tex));
    }
}
```

Other callbacks (`create`, `destroy`, `get_name`) are literal copies of `ndi_filter.cpp` with type names changed.

---

## 6 Build System

### 6.1 Compare to DistroAV

| Item               | DistroAV           | obs‑syphon‑server                    |
| ------------------ | ------------------ | ------------------------------------ |
| `ADD_SUBDIRECTORY` | `plugins/distroav` | `plugins/obs-syphon-server`          |
| Extra libs         | `libndi`           | none (Syphon is a framework)         |
| Frameworks         | none               | `Syphon`, `OpenGL`, `Metal`, `Cocoa` |
| Defines            | `HAVE_NDI`         | none                                 |

### 6.2 Minimal CMakeLists snippet

```cmake
find_library(SYPHON_FRAMEWORK Syphon REQUIRED)

add_library(obs-syphon-server MODULE
    plugin.cpp
    syphon_common.hpp
    syphon_output.mm
    syphon_filter.mm)

target_link_libraries(obs-syphon-server
    ${LIBOBS_LIB}
    ${SYPHON_FRAMEWORK}
    "-framework Metal" "-framework OpenGL" "-framework Cocoa")

set_target_properties(obs-syphon-server PROPERTIES
    BUNDLE TRUE
    BUNDLE_EXTENSION "plugin")
```

---

## 7 Testing Matrix

| Scenario                            | Expected                            | Notes                                  |
| ----------------------------------- | ----------------------------------- | -------------------------------------- |
| OBS GL backend → VDMX               | <2 frames latency, 1080p60          | Compare with DistroAV metrics.         |
| OBS Metal backend → Syphon Recorder | Identical latency & CPU to GL path. | Ensure Metal publishing path works.    |
| Filter on a 4K Media Source         | 4K30 zero‑copy success              | Validate per‑source filter.            |
| Start/Stop spam (50×)               | No leaks (`leaks` <1 KB)            | Mirrors DistroAV’s stress test script. |

---

## 8 Future Enhancements

* Multi‑server publish (Program + Preview) ‑ replicate DistroAV’s dual‑output toggle.
* FPS throttle – follow `ndi_output_tick()` pattern that drops frames based on next timestamp.
* Colour‑space dictionary – add `kSyphonServerDescriptionColorSpaceKey` once Syphon pull‑request #157 lands.

---

Happy hacking – and remember: **if it works in DistroAV, it’s probably the right pattern here too** 🎉
