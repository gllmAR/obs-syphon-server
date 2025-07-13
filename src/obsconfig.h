#pragma once

// Basic configuration for macOS build of OBS Studio headers
// This is a minimal configuration to allow compilation of the plugin

/* #undef GIO_FOUND */
/* #undef PULSEAUDIO_FOUND */
/* #undef XCB_XINPUT_FOUND */
/* #undef ENABLE_WAYLAND */

#define OBS_RELEASE_CANDIDATE 0
#define OBS_BETA 0

// macOS-specific paths - these should match the installed OBS
#define OBS_DATA_PATH "/Applications/OBS.app/Contents/Resources/data"
#define OBS_PLUGIN_PATH "/Applications/OBS.app/Contents/PlugIns"
#define OBS_PLUGIN_DESTINATION "/Applications/OBS.app/Contents/PlugIns"
