#!/bin/bash

# OBS Syphon Server Plugin Installation Script
# This script will install the plugin to your OBS plugins directory

set -e

PLUGIN_NAME="obs-syphon-server"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_PATH="${SCRIPT_DIR}/${PLUGIN_NAME}.plugin"
PLUGINS_DIR="${HOME}/Library/Application Support/obs-studio/plugins"

echo "🔌 OBS Syphon Server Plugin Installer"
echo "======================================"
echo ""

# Check if plugin bundle exists
if [ ! -d "${PLUGIN_PATH}" ]; then
    echo "❌ Error: Plugin bundle not found at ${PLUGIN_PATH}"
    echo "   Make sure you extracted the archive and run this script from the extracted directory."
    exit 1
fi

echo "📍 Plugin found: ${PLUGIN_PATH}"
echo "🎯 Install target: ${PLUGINS_DIR}"
echo ""

# Remove quarantine attribute
echo "🔓 Removing quarantine attribute..."
if xattr -r -d com.apple.quarantine "${PLUGIN_PATH}" 2>/dev/null; then
    echo "✅ Quarantine attribute removed"
else
    echo "⚠️  No quarantine attribute found (this is normal for locally built plugins)"
fi

# Create plugins directory if it doesn't exist
echo "📁 Creating plugins directory..."
mkdir -p "${PLUGINS_DIR}"

# Check if plugin already exists
if [ -d "${PLUGINS_DIR}/${PLUGIN_NAME}.plugin" ]; then
    echo "⚠️  Plugin already exists. Removing old version..."
    rm -rf "${PLUGINS_DIR}/${PLUGIN_NAME}.plugin"
fi

# Copy plugin
echo "📦 Installing plugin..."
cp -R "${PLUGIN_PATH}" "${PLUGINS_DIR}/"

# Verify installation
if [ -d "${PLUGINS_DIR}/${PLUGIN_NAME}.plugin" ]; then
    echo "✅ Plugin installed successfully!"
    echo ""
    echo "🚀 Next steps:"
    echo "   1. Restart OBS Studio"
    echo "   2. The plugin will automatically start publishing your OBS output as 'OBS Studio'"
    echo "   3. Use any Syphon-enabled application to receive the video feed"
    echo ""
    echo "📋 Plugin location: ${PLUGINS_DIR}/${PLUGIN_NAME}.plugin"
else
    echo "❌ Installation failed!"
    exit 1
fi
