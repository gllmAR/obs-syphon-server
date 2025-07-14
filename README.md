# OBS Syphon Server Plugin

> **🍎 macOS Only**: This plugin uses the Syphon framework which is exclusive to macOS. It will not build or run on Windows or Linux.

A plugin for OBS Studio that publishes video output via Syphon, enabling seamless video sharing with other macOS applications like VDMX, Resolume, Quartz Composer, and other Syphon-enabled software.

## What is Syphon?

[Syphon](http://syphon.v002.info/) is a real-time video sharing framework for macOS that allows applications to share frames with one another in real-time with minimal overhead. Think of it as a high-performance, low-latency video pipeline between applications on the same Mac.

## Features

- **Main Output**: Publishes OBS Studio's main program output as a Syphon server
- **Low Latency**: Near-zero latency video sharing between applications
- **High Performance**: GPU-optimized with both OpenGL and Metal support
- **Easy Integration**: Works with any Syphon-enabled application
- **Automatic Detection**: Appears in Syphon clients as "OBS Studio"

## How It Works

The plugin creates a Syphon server that publishes OBS Studio's main program output. Other applications can then receive this video feed in real-time through the Syphon framework.

```
┌─────────────┐    Syphon    ┌─────────────┐
│             │   ────────►  │             │
│ OBS Studio  │              │ VDMX/       │
│ (Server)    │   GPU Memory │ Resolume/   │
│             │   ◄────────  │ Other Apps  │
└─────────────┘              └─────────────┘
```

## Installation

### Prerequisites
- macOS 11.0 (Big Sur) or later
- OBS Studio 28.0 or later
- Applications that support Syphon input

### Download & Install

1. **Download** the latest release from the [Releases page](../../releases)
2. **Extract** the archive:
   ```bash
   tar -xJf obs-syphon-server-*-macos-universal.tar.xz
   cd obs-syphon-server-*-macos-universal/
   ```
3. **Install** using the included script:
   ```bash
   ./install.sh
   ```
   Or install manually:
   ```bash
   xattr -r -d com.apple.quarantine obs-syphon-server.plugin
   mkdir -p ~/Library/Application\ Support/obs-studio/plugins/
   cp -r obs-syphon-server.plugin ~/Library/Application\ Support/obs-studio/plugins/
   ```
4. **Restart** OBS Studio

⚠️ **Important**: The quarantine removal step is required for downloaded plugins to work properly.

### Build from Source
```bash
git clone --recursive https://github.com/gllmAR/obs-syphon-server.git
cd obs-syphon-server
cmake --preset macos
cmake --build --preset macos
```

## Usage

### Basic Setup
1. Install the plugin in OBS Studio
2. The plugin automatically starts publishing your main program output as "OBS Studio"
3. Open any Syphon-enabled application
4. Look for "OBS Studio" in the Syphon server list
5. Select it to receive the video feed

### Syphon-Compatible Applications
- **Video Mixing**: VDMX, Resolume Arena/Avenue, Modul8
- **Live Graphics**: Quartz Composer, TouchDesigner, Max/MSP/Jitter
- **Streaming**: Wirecast, mimoLive, Ecamm Live
- **Recording**: Syphon Recorder, ScreenSearch
- **Development**: Unity, Unreal Engine, openFrameworks, Cinder

### Performance Tips
- **Metal Backend**: Use OBS Studio with Metal rendering for best performance
- **Resolution**: Higher resolutions require more GPU memory and bandwidth
- **Frame Rate**: Match your OBS output frame rate with receiving applications

## Configuration

The plugin currently has minimal configuration options:
- **Server Name**: Fixed as "OBS Studio" (may be configurable in future versions)
- **Auto-Start**: Automatically starts when OBS Studio launches
- **Format**: Publishes in RGBA format at your OBS canvas resolution

## Troubleshooting

### Plugin Not Loading
- Ensure you're running macOS 11.0 or later
- Verify OBS Studio version is 28.0 or later
- Check that the plugin is in the correct directory
- Restart OBS Studio after installation

### No Syphon Output
- Verify OBS Studio is actively outputting video
- Check that your canvas has content
- Ensure receiving application supports Syphon input
- Try restarting both OBS Studio and the receiving application

### Performance Issues
- Lower your OBS canvas resolution
- Reduce frame rate if necessary
- Close unnecessary applications
- Use Metal rendering in OBS Studio preferences

### Compatibility
- Some older Syphon applications may not see the server immediately
- Metal-based Syphon apps will have better performance than OpenGL-based ones

## Technical Details

### Architecture
- **Main Output Publisher**: Captures OBS program output and publishes via Syphon
- **Dual Graphics Support**: Optimized paths for both OpenGL and Metal
- **Zero-Copy Pipeline**: Direct GPU memory sharing where possible
- **Minimal CPU Overhead**: GPU-based processing throughout

### Syphon Server Details
- **Server Name**: "OBS Studio"
- **Format**: RGBA (32-bit per pixel)
- **Color Space**: sRGB
- **Frame Rate**: Matches OBS output frame rate
- **Resolution**: Matches OBS canvas resolution

## Development

### Contributing
This project welcomes contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Architecture Reference
The plugin is inspired by the [DistroAV NDI plugin](https://github.com/DistroAV/DistroAV) architecture, replacing NDI transport with Syphon:

- **Output Module**: Publishes main program feed (`syphon_output.mm`)
- **Common Framework**: Shared Syphon integration (`syphon_common.mm`)
- **Metal/OpenGL Support**: Automatic backend detection and optimization

### Building
Requires:
- Xcode 14+ with Command Line Tools
- CMake 3.16+
- OBS Studio source code (as git submodule)
- Syphon Framework (as git submodule)

## License

This project is licensed under the GPL v2 License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Syphon Framework](http://syphon.v002.info/) - Real-time video sharing framework
- [DistroAV NDI Plugin](https://github.com/DistroAV/DistroAV) - Architecture inspiration
- [OBS Studio](https://obsproject.com/) - Broadcasting software platform

---

## Future Enhancements

- **Multiple Outputs**: Support for publishing preview output and individual sources
- **Custom Server Names**: User-configurable Syphon server names
- **UI Panel**: Qt-based control panel for advanced settings
- **Filter Support**: Syphon output filter for individual sources
- **Color Space Control**: Extended color space and format options

For feature requests and bug reports, please use the [GitHub Issues](../../issues) page.
