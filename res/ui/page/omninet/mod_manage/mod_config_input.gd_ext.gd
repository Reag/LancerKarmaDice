# Script extension on the Mod Manage config input. Works around a vanilla bug, reported to
# Wickworks 2026-09-12:
#
#   engine/mod/mod_config.gd:96 (get_default_values_from_schema) calls
#   crawl_default_values_from_schema_recursive(manifest.config_schema.properties) WITHOUT passing
#   the `default_values` dictionary it goes on to return, so the crawl fills a throwaway local and
#   every mod with a config_schema starts with EMPTY values. The panel then renders every boolean
#   as false and every number as 0, whatever the schema's `default` says.
#
# Fixed here at the display layer only: when there is no stored value, show the property's schema
# default instead of null. Stored values are untouched - a mod still has to fill defaults itself
# when reading config (reag_karma.gd does) - so this changes what the player SEES, not what any mod
# gets. A one-line fix in mod_config.gd makes this file redundant; it is harmless if both exist.
#
# Composable (.gd_ext.gd, not a replacement), so it coexists with any other mod touching this file.
# spec/test_mod_manage_patches.gd proves it is live by rendering through the real scene.
extends "res://ui/page/omninet/mod_manage/mod_config_input.gd"

func rerender(config:Dictionary, current_value = null) -> void:
	if current_value == null and config.has('default'):
		current_value = config.default
	super(config, current_value)
