# Script extension on the Mod Manage config panel: render config inputs in the order the schema
# INTENDS, not the order the file happens to be in.
#
# Vanilla iterates config_schema.properties.keys() (mod_config_panel.gd:127-131), i.e. file order.
# But the Godot editor / Mod Tool rewrites manifest.json with the properties sorted alphabetically
# every time it touches the mod, so file order cannot be relied on (Karma Dice's nine settings kept
# coming back as allow_crits, enabled, kick_in, ...). A property may therefore carry an integer
# `order`; inputs are sorted by it after vanilla has rendered them, lowest first, ties and
# properties without `order` keeping their vanilla position. Any mod's schema can use it.
#
# Composable (.gd_ext.gd): vanilla still builds the inputs, this only moves them.
# spec/test_mod_manage_patches.gd proves it against the real panel scene.
extends "res://ui/page/omninet/mod_manage/mod_config_panel.gd"

const ReagKarma := preload('res://unpacked/Reag-LancerKarmaDice/res/engine/utils/reag_karma.gd')

func rerender_config(mod:ModCore, config:ModConfig) -> void:
	super(mod, config)
	var properties:Dictionary = mod.manifest.config_schema.get('properties', {})
	if properties.is_empty(): return
	reorder_config_inputs(%ConfigInputs, properties, own_order_for(mod))

## Karma Dice's own order lives in CODE (reag_karma.gd DEFAULTS, a literal in panel order), not in
## the manifest: manifest.json gets rewritten by tools that sort its keys and, worse, by anything
## holding a stale copy, so an `order` field there did not survive the day. Other mods get an empty
## list here and are ordered by their own `order` fields, if any.
static func own_order_for(mod:ModCore) -> Array:
	if mod.id == ReagKarma.MOD_ID: return ReagKarma.DEFAULTS.keys()
	return []

## Matches each visible input to its property through `reag_property`, which
## mod_config_input.gd_ext.gd records on every render, then moves the inputs into `order` order.
## Neither label text (translated, and tr() differs per node) nor child index (the panel pools
## its children) is relied on.
## `code_order`, when given, is the authoritative key order and beats any `order` fields; keys not
## in it follow, in their `order` / file order.
static func reorder_config_inputs(container:Node, properties:Dictionary, code_order:Array = []) -> void:
	var visible_inputs:Array[Node] = []
	for child in container.get_children():
		if child is Control and child.visible and child.get('reag_property') != null: visible_inputs.append(child)
	var by_title:Dictionary = {} # raw schema title (the key) => input
	for input:Node in visible_inputs:
		var rendered:Dictionary = input.get('reag_property')
		by_title[str(rendered.get('title', ''))] = input

	var ordered_keys:Array = properties.keys()
	var position:Dictionary = {} # key => vanilla index, for stable ties
	for i in ordered_keys.size(): position[ordered_keys[i]] = i
	ordered_keys.sort_custom(func(a, b) -> bool:
		var ca:int = code_order.find(a)
		var cb:int = code_order.find(b)
		if ca >= 0 or cb >= 0:
			if ca < 0: return false
			if cb < 0: return true
			return ca < cb
		var oa = properties[a].get('order', null)
		var ob = properties[b].get('order', null)
		if oa == null and ob == null: return position[a] < position[b]
		if oa == null: return false
		if ob == null: return true
		if oa != ob: return oa < ob
		return position[a] < position[b]
	)

	var first_index:int = container.get_child_count()
	for input:Node in visible_inputs: first_index = mini(first_index, input.get_index())
	var target:int = first_index
	for key in ordered_keys:
		var input:Node = by_title.get(str(properties[key].get('title', '')), null)
		if input == null: continue
		container.move_child(input, target)
		target += 1
