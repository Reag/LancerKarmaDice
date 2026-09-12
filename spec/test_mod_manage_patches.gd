# Two vanilla Mod Manage bugs, patched from this mod (design §8, found in the in-game check on
# 2026-09-12; both reported to Wickworks):
#
#   1. engine/mod/mod_config.gd:96 calls the schema crawl without passing in the dictionary it then
#      returns, so every schema default is dropped and the panel renders blank / false / 0 for every
#      mod with a config_schema. Patched at the INPUT: mod_config_input.gd_ext.gd falls back to the
#      property's schema default when no stored value exists. Display only - the stored values stay
#      exactly what the player set, which is what reag_karma.gd already expects.
#   2. ui/page/omninet/mod_manage/mod_manage.gd:351 has_pending_changes_to_mod_activations never
#      compares config VALUES (only enabled, priority, version), so changing a value never shows the
#      Apply changes button. Patched by mod_manage.gd_ext.gd, which adds a values comparison.
#
# The point of this file is proving both extensions are LIVE (CLAUDE.md, dead seams): (1) by
# instantiating the real input scene and rendering through it, (2) by checking the script loaded
# from the vanilla path carries the override, and exercising the comparison it delegates to.
extends GutTest

const INPUT_SCENE := 'res://ui/page/omninet/mod_manage/mod_config_input.tscn'
const MANAGE_SCRIPT := 'res://ui/page/omninet/mod_manage/mod_manage.gd'

func make_input() -> Node:
	var input:Node = load(INPUT_SCENE).instantiate()
	add_child_autoqfree(input)
	return input

# ---------------------------------------------------------------- bug 1: defaults

func test_a_boolean_input_with_no_stored_value_shows_the_schema_default():
	var input := make_input()
	input.rerender({type = 'boolean', default = true, title = 'x'}, null)
	assert_true(input.get_node('%Boolean').button_pressed, 'Rendered true from the schema default, not false from null.')

func test_a_number_input_with_no_stored_value_shows_the_schema_default():
	var input := make_input()
	input.rerender({type = 'number', default = 7, title = 'x'}, null)
	assert_eq(int(input.get_node('%Number').value), 7, 'Rendered 7 from the schema default, not 0 from null.')

func test_a_stored_value_still_wins_over_the_default():
	var input := make_input()
	input.rerender({type = 'number', default = 7, title = 'x'}, 3)
	assert_eq(int(input.get_node('%Number').value), 3, 'The stored 3 beats the default 7.')
	input.rerender({type = 'boolean', default = true, title = 'x'}, false)
	assert_false(input.get_node('%Boolean').button_pressed, 'A stored false beats a default true.')

func test_a_property_without_a_default_still_renders_vanilla_style():
	var input := make_input()
	input.rerender({type = 'number', title = 'x'}, null)
	assert_eq(int(input.get_node('%Number').value), 0, 'No default, no stored value: vanilla shows 0.')

func test_a_title_that_is_a_translation_key_renders_as_its_text():
	var input := make_input()
	input.rerender({type = 'boolean', default = true, title = 'reag_karmic_dice.config.enabled.title', description = 'reag_karmic_dice.config.enabled.desc'}, null)
	assert_eq(input.get_node('%Label').text, tr('reag_karmic_dice.config.enabled.title'), 'Title is the translated text, not the key.')
	assert_eq(input.get_node('%Desc').text, tr('reag_karmic_dice.config.enabled.desc'), 'Description too.')
	assert_ne(input.get_node('%Label').text, 'reag_karmic_dice.config.enabled.title', 'Sanity: the row exists, so the key did not leak through.')

# ---------------------------------------------------------------- bug 2: Apply for value changes

func test_the_mod_manage_script_carries_the_override():
	var script:Script = load(MANAGE_SCRIPT)
	var names:Array = script.get_script_method_list().map(func(m:Dictionary) -> String: return m.name)
	assert_true(names.has('config_values_differ'), 'mod_manage.gd_ext.gd took over the vanilla script path.')

func test_config_values_differ_compares_values_and_nothing_else():
	var script = load(MANAGE_SCRIPT)
	var a := ModConfig.new()
	var b := ModConfig.new()
	a.values = {strength = 3}
	b.values = {strength = 3}
	assert_false(script.config_values_differ(a, b), 'Same values: no change.')
	b.values = {strength = 4}
	assert_true(script.config_values_differ(a, b), 'A changed value counts.')
	b.values = {}
	assert_true(script.config_values_differ(a, b), 'A newly set key counts too (the panel starts from empty values).')
	a.values = {}
	a.is_enabled = true
	a.user_priority = 5
	assert_false(script.config_values_differ(a, b), 'Enabled and priority are vanilla\'s comparison, not this one.')

# ---------------------------------------------------------------- input order

const PANEL_SCENE := 'res://ui/page/omninet/mod_manage/mod_config_panel.tscn'
const EXPECTED_ORDER := ['enabled', 'players_only', 'outcome_aware', 'mixed_mode', 'reroll_mode', 'allow_crits', 'kick_in', 'low_roll_threshold', 'strength']

func test_inputs_render_in_schema_order_whatever_the_file_order():
	# Tools rewrite manifest.json with properties sorted alphabetically (and a stale copy can drop
	# any field we add), so the order lives in reag_karma.gd DEFAULTS and mod_config_panel.gd_ext.gd
	# sorts the rendered inputs by it.
	var mod:ModCore = ModLibrary.get_installed_mod(&'Reag-LancerKarmaDice')
	if mod == null: return fail_test('The mod is installed.')
	# Reproduce what the editor does to the file: properties sorted alphabetically. Done on a COPY of
	# the schema swapped in for the duration of the render, then restored.
	var original_schema:Dictionary = mod.manifest.config_schema
	var sorted_schema:Dictionary = original_schema.duplicate(true)
	var sorted_props:Dictionary = {}
	var names:Array = original_schema.properties.keys()
	names.sort()
	for n in names: sorted_props[n] = original_schema.properties[n]
	sorted_schema.properties = sorted_props
	assert_eq(names.front(), 'allow_crits', 'Sanity: the sorted copy really starts with allow_crits.')
	mod.manifest.config_schema = sorted_schema
	var panel:Node = load(PANEL_SCENE).instantiate()
	add_child_autoqfree(panel)
	# get_baseline, not get_current: with no campaign loaded, X.current_campaign() trips a typed-return
	# engine error after earlier specs have populated the tree, and GUT counts engine errors as failures.
	panel.rerender_config(mod, Modset.get_baseline().get_config(&'Reag-LancerKarmaDice'))
	mod.manifest.config_schema = original_schema
	var titles:Array[String] = []
	for child in panel.get_node('%ConfigInputs').get_children():
		if child is Control and child.visible and child.has_node('%Label'): titles.append(child.get_node('%Label').text)
	var expected:Array[String] = []
	for key in EXPECTED_ORDER: expected.append(tr('reag_karmic_dice.config.%s.title' % key))
	assert_eq(titles, expected, 'Nine inputs, in the order the schema intends.')

func test_reorder_is_stable_for_properties_without_order():
	var props := {b = {title = 'B'}, a = {title = 'A', order = 1}, c = {title = 'C'}}
	# Generic path (no code order): `order` fields first, the rest in file order.
	var box := VBoxContainer.new()
	add_child_autoqfree(box)
	for t in ['B', 'A', 'C']:
		var input:Node = load('res://ui/page/omninet/mod_manage/mod_config_input.tscn').instantiate()
		box.add_child(input)
		input.rerender({type = 'boolean', title = t}, false)
	load('res://ui/page/omninet/mod_manage/mod_config_panel.gd').reorder_config_inputs(box, props)
	var titles:Array[String] = []
	for child in box.get_children(): titles.append(child.get_node('%Label').text)
	assert_eq(titles, ['A', 'B', 'C'] as Array[String], 'Ordered first, then the rest in file order.')

func test_code_order_beats_order_fields():
	var props := {b = {title = 'B', order = 1}, a = {title = 'A', order = 2}, c = {title = 'C'}}
	var box := VBoxContainer.new()
	add_child_autoqfree(box)
	for t in ['B', 'A', 'C']:
		var input:Node = load('res://ui/page/omninet/mod_manage/mod_config_input.tscn').instantiate()
		box.add_child(input)
		input.rerender({type = 'boolean', title = t}, false)
	load('res://ui/page/omninet/mod_manage/mod_config_panel.gd').reorder_config_inputs(box, props, ['c', 'a'])
	var titles:Array[String] = []
	for child in box.get_children(): titles.append(child.get_node('%Label').text)
	assert_eq(titles, ['C', 'A', 'B'] as Array[String], 'Code order first (c, a), then the leftovers by their order field.')
