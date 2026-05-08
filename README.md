# obs-syphon-server

Publish OBS Studio's program output and individual sources to
[Syphon](http://syphon.v002.info/) on macOS.

> macOS-only, Apple Silicon (arm64). Tested on macOS 26 with OBS 31 (OpenGL backend).

## Features

- **Program publisher** — publishes OBS's main canvas as Syphon server `OBS`
  (auto-started).
- **Preview publisher** — optional second server `OBS Preview` (off by default;
  toggle via the *Tools → Syphon...* menu).
- **Per-source filter** — apply *Syphon Server (publish source)* as a video
  filter on any source to publish that source as its own Syphon server with a
  user-defined name.
- **Idle-aware** — when no Syphon client is connected, the publish path skips
  the GPU readback entirely (CPU usage drops to ~0).

## Build

Prerequisites:
- macOS 12+ on Apple Silicon
- OBS Studio installed at `/Applications/OBS.app` (provides `libobs`)
- Xcode Command Line Tools, CMake 3.20+, Ninja

```sh
git clone --recursive https://github.com/gllmAR/obs-syphon-server.git
cd obs-syphon-server
cmake -G Ninja -B build
cmake --build build
cmake --build build --target install-plugin     # → ~/Library/Application Support/obs-studio/plugins
```

To uninstall: `cmake --build build --target uninstall-plugin`.

## How it works

The OBS macOS build uses the OpenGL graphics backend. OpenGL wraps Syphon
IOSurfaces as `GL_TEXTURE_RECTANGLE_ARB` while OBS's own texrenders use
`GL_TEXTURE_2D`, which makes direct `gs_copy_texture` between them silently
no-op (black frames). So the publish path is:

1. Render the source/canvas into a `GS_BGRA` texrender.
2. `gs_stage_texture` → `gs_stagesurface_map` (essentially zero-copy on Apple
   Silicon — unified memory).
3. `memcpy` into the Syphon server's IOSurface.
4. `[server publish]`.

When `SyphonServerBase.hasClients` reports no client, steps 2-4 are skipped.

## Source layout

```
src/
  plugin-main.c          module entry, registers filter + tools, starts publishers
  syphon-server.{h,mm}   thin C wrapper around SyphonServerBase
  syphon-publisher.{h,mm} program/preview publishers (obs_add_main_rendered_callback)
  syphon-filter.mm       per-source publisher (OBS_SOURCE_TYPE_FILTER)
  syphon-tools.{h,mm}    Tools menu UI
  obsconfig.h            stub for libobs headers
deps/
  obs-studio/            submodule (used for headers only; libobs comes from /Applications/OBS.app)
  Syphon-Framework/      submodule (compiled in-tree as a static lib)
data/locale/en-US.ini    UI strings
```

## License

GPL v2 — see [LICENSE](LICENSE).
