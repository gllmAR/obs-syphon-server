/*
 * obs-syphon-server — module entry.
 *
 * Registers:
 *   - syphon_server_filter (per-source publisher, used as a video filter)
 *   - Tools menu "Syphon..." item that opens the settings panel
 * Starts:
 *   - Program publisher (on by default)
 *   - Preview publisher (off by default)
 */

#include <obs-module.h>
#include "plugin-support.h"
#include "syphon-publisher.h"
#include "syphon-tools.h"

extern struct obs_source_info syphon_filter_info;

OBS_DECLARE_MODULE()
OBS_MODULE_USE_DEFAULT_LOCALE("obs-syphon-server", "en-US")

MODULE_EXPORT const char *obs_module_description(void)
{
	return "Publish OBS output and individual sources to Syphon";
}

MODULE_EXPORT const char *obs_module_name(void)
{
	return "obs-syphon-server";
}

bool obs_module_load(void)
{
	obs_register_source(&syphon_filter_info);
	syphon_publisher_init();
	syphon_tools_register();
	obs_log(LOG_INFO, "obs-syphon-server v%s loaded", plugin_version);
	return true;
}

void obs_module_unload(void)
{
	syphon_publisher_shutdown();
	obs_log(LOG_INFO, "obs-syphon-server unloaded");
}
