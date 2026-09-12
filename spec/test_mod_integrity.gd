# Wiring, not behaviour: is the mod installed, does its manifest name the engine, is nothing
# misfiled, and does the battle-log line resolve. Behaviour lives in test_karma_*.gd.
extends GutTest

const ModContentAudit := preload('res://testkit/mod_content_audit.gd')
const Compat := preload('res://testkit/modkit_compat.gd')

const MOD_ID := 'Reag-LancerKarmaDice'
const LOG_KEY := 'reag_karmic_dice.corrected.log'

func test_the_mod_is_actually_loaded():
	assert_true(Compat.is_mod_active(MOD_ID), '%s is loaded and active.' % MOD_ID)

func test_the_manifest_names_this_engine_version():
	# 1.4.1+ compares the PATCH too for a requires_restart mod (mod_util.gd). See CLAUDE.md.
	var manifest = ModLibrary.get_manifest(StringName(MOD_ID))
	assert_not_null(manifest, '%s has a manifest.' % MOD_ID)
	if manifest == null: return
	assert_true(ModUtil.is_mod_likely_compatible_with_game_version(manifest),
		'%s declares %s in compatible_game_version.' % [MOD_ID, Compat.version_label()])
	assert_true(manifest.requires_restart, 'Extending an autoload is not cleanly undoable, so the mod is Substantial.')

func test_no_resource_is_filed_under_the_wrong_index():
	var problems := ModContentAudit.find_misfiled_resources(MOD_ID)
	for problem:String in problems: gut.p('  %s' % problem)
	assert_eq(problems.size(), 0, 'Every resource landed in the right ContentLibrary index.')

func test_the_battle_log_line_is_localized():
	# tr() reads the compiled localizations.en.translation, not the CSV. If this fails right after
	# editing the CSV, the artifact is stale: run filesystem_manage(op="scan") in the editor or the
	# --import command from the plan, then re-run. See CLAUDE.md "Editing a mod's localization".
	var text := tr(LOG_KEY)
	assert_ne(text, LOG_KEY, 'The key resolves to text.')
	assert_true(text.contains('{raw}') and text.contains('{corrected}'), 'It has both roll placeholders.')
	assert_true(text.contains('{unit}'), 'And it names the unit that rolled (log_unit fills {unit}).')

func test_the_config_schema_has_every_key_with_a_default():
	var manifest = ModLibrary.get_manifest(StringName(MOD_ID))
	if manifest == null: return fail_test('Manifest present.')
	var props:Dictionary = manifest.config_schema.get('properties', {})
	var expected := ['enabled', 'players_only', 'outcome_aware', 'mixed_mode', 'reroll_mode',
		'allow_crits', 'kick_in', 'low_roll_threshold', 'strength']
	assert_eq(props.keys(), expected, 'All nine keys, in panel order.')
	for key in expected:
		if not props.has(key): continue
		assert_true(props[key].has('default'), '%s has a default.' % key)
		assert_true(props[key].has('title') and props[key].has('description'), '%s has title and description.' % key)
