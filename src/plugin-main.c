/*
 * obs-syphon-server — module entry
 *
 * Registers:
 *   - syphon_server_filter   per-source Syphon publisher (apply as filter)
 *   - Tools menu entries for toggling Program / Preview Syphon outputs
 * Runs:
 *   - Program publisher auto-started; Preview publisher off by default.
 *
 * All publishing paths are GPU-only (no CPU readback or upload).
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
	return "Publish OBS output and individual sources to Syphon (zero-copy GPU)";
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
	obs_log(LOG_INFO, "obs-syphon-server v%s loaded (zero-copy GPU)", plugin_version);
	return true;
}

void obs_module_unload(void)
{
	syphon_publisher_shutdown();
	obs_log(LOG_INFO, "obs-syphon-server unloaded");
}
