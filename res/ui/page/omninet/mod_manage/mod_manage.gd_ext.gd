# Script extension on the Mod Manage page. Works around a vanilla bug, reported to Wickworks
# 2026-09-12:
#
#   ui/page/omninet/mod_manage/mod_manage.gd:351 has_pending_changes_to_mod_activations decides
#   whether the "Apply changes" button shows by comparing each mod's pending ModConfig against the
#   current one on is_enabled, user_priority and version ONLY. Config VALUES are never compared,
#   so changing a value in the config panel never surfaces the button and the change cannot be
#   applied (short of also nudging the load priority, which does register).
#
# Fixed here by keeping vanilla's answer and adding one more reason to say yes: any listed mod
# whose pending values differ from its current values. Nothing else about the page changes -
# is_restart_required_to_apply_changes still only fires on enabling/disabling a Substantial mod,
# so a value change on this (Substantial) mod applies without a restart, as intended.
#
# Composable (.gd_ext.gd). spec/test_mod_manage_patches.gd proves the vanilla path carries this
# override and exercises the comparison.
extends "res://ui/page/omninet/mod_manage/mod_manage.gd"

func has_pending_changes_to_mod_activations() -> bool:
	if super(): return true
	var current_modset := Modset.get_current()
	return listed_mods.any(func(mod:ModCore) -> bool:
		return config_values_differ(pending_modset.get_config(mod.id), current_modset.get_config(mod.id))
	)

## Values only. Enabled, priority and version stay vanilla's comparison.
static func config_values_differ(pending:ModConfig, current:ModConfig) -> bool:
	if pending == null or current == null: return false
	return pending.values.hash() != current.values.hash()
