# OBS Syphon Server Plugin

A plugin for OBS Studio that provides Syphon server functionality on macOS, allowing OBS to share video frames with other applications via the Syphon framework.

## Status

✅ **Main Output Server**: Automatically shares the entire OBS canvas as "OBS-Main"  
❌ **Source Filters**: Disabled due to symbol conflicts with OBS's built-in Syphon framework

## Quick Start

1. Build and install the plugin:
```bash
mkdir build_macos && cd build_macos
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc) && make install
```

2. Start OBS Studio - the "OBS-Main" Syphon server will be automatically available

3. Use any Syphon client to receive the OBS canvas

## Current Limitations

- **Filter crashes**: Adding Syphon filters to individual sources causes OBS to crash
- **Symbol conflicts**: Both the plugin and OBS include Syphon classes, causing Objective-C runtime conflicts
- **Main output only**: Only the entire canvas can be shared, not individual sources

## Technical Details

The plugin builds its own Syphon framework to avoid dependency issues, but this creates class conflicts with OBS's built-in Syphon support. The main output works because it uses a different code path, but filters directly conflict with OBS's existing Syphon implementation.

## Requirements

- macOS 10.14+
- OBS Studio 31.x
- CMake 3.16+
- Xcode command line tools

## License

GPL v2.0 - See LICENSE file for details.
