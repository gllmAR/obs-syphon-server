# OBS Syphon Server Plugin - Installation Instructions

## Quick Installation

### Option 1: Using the Installer Package (Recommended)
If you downloaded the `.pkg` installer:

1. **Remove quarantine attribute first:**
   ```bash
   xattr -d com.apple.quarantine obs-syphon-server-*-macos-universal.pkg
   ```

2. **Run the installer:**
   - Double-click the `.pkg` file, or
   - Run from command line: `sudo installer -pkg obs-syphon-server-*-macos-universal.pkg -target /`

3. **Restart OBS Studio**

The installer will automatically install the plugin to your user's OBS plugins directory (`~/Library/Application Support/obs-studio/plugins/`).

### Option 2: Manual Installation
If you downloaded the `.tar.xz` archive:

1. **Extract the plugin:**
   ```bash
   tar -xJf obs-syphon-server-*-macos-universal.tar.xz
   ```

2. **Remove quarantine attribute (IMPORTANT):**
   ```bash
   sudo xattr -r -d com.apple.quarantine obs-syphon-server.plugin
   ```
   
   ⚠️ **This step is required** - macOS quarantines downloaded files and may prevent the plugin from loading properly.

3. **Install the plugin:**
   ```bash
   cp -r obs-syphon-server.plugin ~/Library/Application\ Support/obs-studio/plugins/
   ```
   
   Or manually copy the `obs-syphon-server.plugin` folder to:
   ```
   ~/Library/Application Support/obs-studio/plugins/
   ```

4. **Restart OBS Studio**

## Troubleshooting

### Plugin Not Loading
- Make sure you've removed the quarantine attribute (step 2 above)
- Verify the plugin is in the correct directory
- Check OBS Studio logs for error messages

### Permission Issues
If you get permission errors, you may need to use `sudo`:
```bash
sudo cp -r obs-syphon-server.plugin ~/Library/Application\ Support/obs-studio/plugins/
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
