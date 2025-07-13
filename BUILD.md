# OBS Syphon Server Plugin - Build Configuration Guide

## Prerequisites

### Required Software
- **macOS 10.15+** (Catalina or later)
- **Xcode Command Line Tools**
- **CMake 3.28+**
- **Git**

### Optional but Recommended
- **Ninja** build system (`brew install ninja`)
- **Homebrew** package manager

### OBS Studio Development Environment
This plugin requires OBS Studio development headers. You have several options:

1. **Build OBS Studio from source** (recommended for development)
2. **Use pre-built development package** (if available)
3. **Install via Homebrew** (`brew install obs`)

## Quick Start

1. **Run the setup script:**
   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```

2. **Configure your OBS Studio path** (if not in standard location):
   ```bash
   export OBS_ROOT="/path/to/obs-studio"
   ```

3. **Build the plugin:**
   ```bash
   ./build.sh          # Debug build
   ./build.sh Release  # Release build
   ```

## Manual Build Steps

If you prefer to build manually:

```bash
# 1. Initialize submodules
git submodule update --init --recursive

# 2. Create build directory
mkdir -p build/Debug
cd build/Debug

# 3. Configure with CMake
cmake ../.. \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DSyphon_ROOT="../../deps/Syphon-Framework" \
    -G Ninja

# 4. Build
ninja
```

## Build Configuration Options

### CMake Variables
- `CMAKE_BUILD_TYPE`: Debug or Release
- `CMAKE_OSX_ARCHITECTURES`: Target architectures (arm64, x86_64, or both)
- `Syphon_ROOT`: Path to Syphon Framework (auto-detected from submodule)
- `OBS_ROOT`: Path to OBS Studio installation/build

### Environment Variables
- `OBS_ROOT`: OBS Studio installation path
- `SYPHON_FRAMEWORK_PATH`: Custom Syphon Framework path

## Installation

After building, you can install the plugin:

1. **Find your OBS plugins directory:**
   - **Intel Mac:** `/Applications/OBS.app/Contents/PlugIns/`
   - **Apple Silicon:** `/Applications/OBS.app/Contents/PlugIns/`
   - **Custom build:** `<obs-build>/rundir/RelWithDebInfo/obs-plugins/`

2. **Copy the plugin:**
   ```bash
   cp build/Debug/obs-syphon-server.plugin /Applications/OBS.app/Contents/PlugIns/
   ```

## Development Workflow

### Code Style
- Follow OBS Studio coding conventions
- Use clang-format for C/C++ code: `./build-aux/run-clang-format`
- Use swift-format for any Swift code: `./build-aux/run-swift-format`

### Testing
1. Build in Debug mode for development
2. Test with various OBS scenes and sources
3. Monitor for memory leaks using Instruments
4. Validate Syphon server discovery in client apps

### Debugging
- Use Xcode debugger with OBS Studio
- Enable verbose logging in plugin
- Use Console.app to monitor system logs

## Troubleshooting

### Common Issues

**"Syphon Framework not found"**
- Run `./setup.sh` to download the submodule
- Check that `deps/Syphon-Framework/Syphon.h` exists

**"OBS headers not found"**
- Ensure OBS Studio development environment is set up
- Set `OBS_ROOT` environment variable
- Install OBS development package

**"Architecture mismatch"**
- Ensure you're building for the same architecture as your OBS Studio
- Use `CMAKE_OSX_ARCHITECTURES` to specify target architectures

**Plugin doesn't load in OBS**
- Check that the plugin is in the correct directory
- Verify that all dependencies are satisfied
- Check OBS Studio logs for error messages

### Getting Help
- Check the [OBS Studio Plugin Development Guide](https://obsproject.com/wiki/Plugin-Development)
- Review the [Syphon Framework Documentation](https://syphon.github.io/)
- Compare with [DistroAV implementation](https://github.com/DistroAV/DistroAV) for reference patterns
