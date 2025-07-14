# OBS Syphon Server Plugin - Installation Instructions

## Quick Installation

### Option 1: Automatic Installation (Recommended)
1. **Extract the archive:**
   ```bash
   tar -xJf obs-syphon-server-*-macos-universal.tar.xz
   cd obs-syphon-server-*-macos-universal/
   ```

2. **Run the installation script:**
   ```bash
   ./install.sh
   ```
   
   The script will automatically:
   - Remove quarantine attributes
   - Install the plugin to the correct OBS directory
   - Verify the installation

3. **Restart OBS Studio**

### Option 2: Manual Installation
1. **Extract the archive:**
   ```bash
   tar -xJf obs-syphon-server-*-macos-universal.tar.xz
   ```

2. **Remove quarantine attribute (IMPORTANT):**
   ```bash
   xattr -r -d com.apple.quarantine obs-syphon-server.plugin
   ```
   
   ⚠️ **This step is required** - macOS quarantines downloaded files and may prevent the plugin from loading properly.

3. **Install the plugin:**
   ```bash
   mkdir -p ~/Library/Application\ Support/obs-studio/plugins/
   cp -r obs-syphon-server.plugin ~/Library/Application\ Support/obs-studio/plugins/
   ```

4. **Restart OBS Studio**

## Troubleshooting

### Plugin Not Loading
- Make sure you've removed the quarantine attribute 
- Verify the plugin is in the correct directory: `~/Library/Application Support/obs-studio/plugins/`
- Check OBS Studio logs for error messages

### Permission Issues
Make sure the plugin directory is writable:
```bash
ls -la ~/Library/Application\ Support/obs-studio/plugins/
```

### Architecture Issues
This plugin is built as a universal binary and supports both Intel and Apple Silicon Macs.

## Requirements
- macOS 10.15 (Catalina) or later
- OBS Studio 28.0 or later
- Compatible with both Intel and Apple Silicon Macs

## Usage
After installation, you'll find "Syphon Server" in the Filters menu when right-clicking on any source in OBS Studio.

## Support
For issues and support, please visit: https://github.com/gllmAR/obs-syphon-server
