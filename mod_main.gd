extends Node

const MOD_ID := "Reag-LancerKarmaDice" ## Name of the directory that this file is in

## 1.4.x workaround (see reload_extended_autoloads_140 below). This path exists only on 1.4.x and is
## used purely as a version test.
const MOD_LIBRARY_140 := 'res://engine/mod/mod_library.gd'
## Autoloads this mod extends with .gd_ext.gd files, by autoload name => vanilla script path.
const EXTENDED_AUTOLOADS := {
	&'Dice': 'res://engine/utils/dice.gd',
}

# Runs when this mod is activated (whenever active mods are changed)
func _init() -> void:
	ModLoaderLog.info("Activating.", MOD_ID)

	# Adds the translations from your localization/localizations.csv
	LancerTacticsMod.add_translations(MOD_ID)

	# Scans res/: adds new resources and scripts, overwrites matching resources, and installs
	# matching .gd_ext.gd files as script extensions.
	LancerTacticsMod.add_overwrite_extend_mod_resources(MOD_ID)

# Runs when this mod's node is added to the tree (whenever active mods are changed)
func _ready() -> void:
	if ResourceLoader.exists(MOD_LIBRARY_140):
		reload_extended_autoloads_140.call_deferred()

## 1.4.x installs mods AFTER the autoloads exist and only reloads an autoload whose PLAIN .gd a mod
## replaced (ModApplier.apply_script_changes_to_autoload_nodes). Our file is a .gd_ext.gd, so the
## live Dice node keeps its pre-extension script and none of our overrides run. Deferred from
## _ready on purpose: by then every queued script extension has been applied, so load(vanilla_path)
## already returns the extended script (take_over_path). Copied from Reag-ThyHubris/mod_main.gd,
## where it is proven against three autoloads. Upstream bug 5; still present in 1.4.2.
func reload_extended_autoloads_140() -> void:
	for autoload_name:StringName in EXTENDED_AUTOLOADS:
		var node:Node = get_tree().root.get_node_or_null(NodePath(autoload_name))
		if node == null: continue
		var extended:Script = load(EXTENDED_AUTOLOADS[autoload_name])
		if node.get_script() == extended: continue # already right (engine fixed, or nothing extended it)
		node.set_script(null)
		node.set_script(extended)
		ModLoaderLog.info('Reloaded autoload %s with its script extension (1.4.x workaround).' % autoload_name, MOD_ID)

# This only runs on game startup when this mod is enabled; use it to make any manual changes to the game
# that are outside of the LancerTacticsMod normal enable/disable sequence that should NOT be reverted when
# active mods change. This will be run AFTER all mods' _init and _ready functions.
func on_first_initialization() -> void:
	ModLoaderLog.info("On game start for substantial mod.", MOD_ID)
