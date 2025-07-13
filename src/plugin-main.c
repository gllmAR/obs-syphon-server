/*
OBS Syphon Server Plugin
Copyright (C) 2025 OBS Syphon Team

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program. If not, see <https://www.gnu.org/licenses/>
*/

#include <obs-module.h>
#include <plugin-support.h>

#ifdef __APPLE__
// Forward declarations for our output registration function
extern void register_syphon_output(void);

// Filter is disabled due to symbol conflicts with OBS's Syphon framework
// extern struct obs_source_info sy_filter_info;

// Forward declarations for main server functions
extern void syphon_main_server_start(void);
extern void syphon_main_server_stop(void);
extern bool syphon_main_server_is_running(void);
#endif

OBS_DECLARE_MODULE()
OBS_MODULE_USE_DEFAULT_LOCALE(PLUGIN_NAME, "en-US")

bool obs_module_load(void)
{
#ifdef __APPLE__
	// Register the Syphon server output using the new function
	register_syphon_output();

	// Register the Syphon server filter (temporarily disabled due to symbol conflicts)
	// TODO: Re-enable once dynamic loading is properly implemented
	// obs_register_source(&sy_filter_info);
	// obs_log(LOG_INFO, "[syphon] Registered Syphon server filter");

	// Start the main server automatically
	syphon_main_server_start();
	obs_log(LOG_INFO, "[syphon] Auto-started main server");

	obs_log(LOG_INFO, "[syphon] Plugin loaded successfully (version %s)", plugin_version);
	return true;
#else
	obs_log(LOG_ERROR, "[syphon] Plugin is only supported on macOS");
	return false;
#endif
}

void obs_module_unload(void)
{
#ifdef __APPLE__
	// Stop the main server
	syphon_main_server_stop();
#endif
	obs_log(LOG_INFO, "[syphon] Plugin unloaded");
}
