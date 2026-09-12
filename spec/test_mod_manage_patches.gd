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
