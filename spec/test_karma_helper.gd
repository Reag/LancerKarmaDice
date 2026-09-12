# Every rule in reag_karma.gd, driven directly. No RNG, no real attacks - those are in
# test_karma_seam.gd. Events are SpecFactory dummies carrying a unit; Context.create pulls the map
# from the unit, so nothing else is needed for the map-change logic.
extends GutTest

const ReagKarma := preload('res://unpacked/Reag-LancerKarmaDice/res/engine/utils/reag_karma.gd')

var game:Gamemaster
var player:Unit
var enemy:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	player = SpecFactory.create_unit(game.map, Vector2i(0,0))
	enemy = SpecFactory.create_unit(game.map, Vector2i(3,3), Faction.AI_ENEMY)
	ReagKarma.prime(game.map, {})

func after_each():
	ReagKarma.reset()
	ReagKarma.config_source = ReagKarma.read_baseline_values
	ReagKarma.extra_die = ReagKarma.roll_extra_die

## A plain d20 event for a unit: no AttackRoll on the context, so it classifies as CHECK.
func check_event(unit:Unit) -> EventCore:
	return SpecFactory.dummy_event({unit = unit})

## An attack event: an AttackRoll on the context, exactly where event_unit_attack.gd:56 puts it.
func attack_event(unit:Unit, roll:AttackRoll) -> EventCore:
	var event := SpecFactory.dummy_event({unit = unit})
	event.context.object = roll
	return event

## A real save event, shaped exactly as unit_hasecheck.gd run_save_event builds it: the FORCING unit
## in `unit`, the unit actually rolling in `target_unit`.
func save_event(forcer:Unit, saver:Unit) -> EventCore:
	return EventCore.create(&'event_unit_save', {unit = forcer, target_unit = saver, category = Lancer.HASE.SYS})

# ---------------------------------------------------------------- config

func test_defaults_fill_in_for_a_profile_missing_keys():
	ReagKarma.load_config({})
	assert_eq(ReagKarma.config, ReagKarma.DEFAULTS, 'Empty values => every default.')
	ReagKarma.load_config({strength = 9})
	assert_eq(ReagKarma.config.strength, 9, 'A present key is taken.')
	assert_eq(ReagKarma.config.kick_in, 2, 'An absent key keeps its default.')

func test_numbers_are_clamped_and_coerced():
	# The panel's SpinBox is unbounded (allow_greater/lesser) and emits floats.
	ReagKarma.load_config({kick_in = 0, low_roll_threshold = 40, strength = 99})
	assert_eq(ReagKarma.config.kick_in, 1, 'kick_in floor is 1.')
	assert_eq(ReagKarma.config.low_roll_threshold, 19, 'threshold ceiling is 19.')
	assert_eq(ReagKarma.config.strength, 19, 'strength ceiling is 19.')
	ReagKarma.load_config({kick_in = 25, low_roll_threshold = 0, strength = 0})
	assert_eq(ReagKarma.config.kick_in, 20, 'kick_in ceiling is 20.')
	assert_eq(ReagKarma.config.low_roll_threshold, 1, 'threshold floor is 1.')
	assert_eq(ReagKarma.config.strength, 1, 'strength floor is 1.')
	ReagKarma.load_config({strength = 4.0, enabled = 0})
	assert_true(ReagKarma.config.strength is int and ReagKarma.config.strength == 4, 'Floats become ints.')
	assert_true(ReagKarma.config.enabled is bool and ReagKarma.config.enabled == false, 'Booleans are coerced.')

func test_unknown_keys_are_ignored():
	ReagKarma.load_config({not_a_setting = 1})
	assert_false(ReagKarma.config.has('not_a_setting'), 'Only schema keys survive.')

func test_policy_table_blind():
	ReagKarma.load_config({outcome_aware = false, mixed_mode = true}) # mixed is ignored when blind
	assert_eq(ReagKarma.policy[ReagKarma.KIND.ATTACK], ReagKarma.GRADER.THRESHOLD)
	assert_eq(ReagKarma.policy[ReagKarma.KIND.CHECK], ReagKarma.GRADER.THRESHOLD)
	assert_eq(ReagKarma.policy[ReagKarma.KIND.BARE], ReagKarma.GRADER.THRESHOLD)

func test_policy_table_aware():
	ReagKarma.load_config({outcome_aware = true, mixed_mode = false})
	assert_eq(ReagKarma.policy[ReagKarma.KIND.ATTACK], ReagKarma.GRADER.OUTCOME)
	assert_eq(ReagKarma.policy[ReagKarma.KIND.CHECK], ReagKarma.GRADER.EXCLUDED)
	assert_eq(ReagKarma.policy[ReagKarma.KIND.BARE], ReagKarma.GRADER.EXCLUDED)

func test_policy_table_mixed():
	ReagKarma.load_config({outcome_aware = true, mixed_mode = true})
	assert_eq(ReagKarma.policy[ReagKarma.KIND.ATTACK], ReagKarma.GRADER.OUTCOME)
	assert_eq(ReagKarma.policy[ReagKarma.KIND.CHECK], ReagKarma.GRADER.THRESHOLD)
	assert_eq(ReagKarma.policy[ReagKarma.KIND.BARE], ReagKarma.GRADER.THRESHOLD)

func test_reading_the_baseline_profile_does_not_error():
	# Smoke only: in a test run the baseline is whatever testkit applied. Values may be empty.
	var values := ReagKarma.read_baseline_values()
	assert_true(values is Dictionary, 'Returns a Dictionary, possibly empty.')

# ---------------------------------------------------------------- eligibility

func test_disabled_returns_raw_and_touches_nothing():
	ReagKarma.prime(game.map, {enabled = false, kick_in = 1, strength = 5})
	ReagKarma.streak = 3
	assert_eq(ReagKarma.apply(4, check_event(player)), 4, 'Vanilla value.')
	assert_eq(ReagKarma.streak, 3, 'Streak untouched.')
	assert_eq(ReagKarma.corrections, 0, 'Nothing corrected.')
	assert_eq(ReagKarma.calls, 1, 'But the call was still counted (seam liveness).')

func test_players_only_skips_an_enemy_and_takes_a_player():
	ReagKarma.prime(game.map, {players_only = true, kick_in = 1, strength = 5})
	ReagKarma.streak = 1
	assert_eq(ReagKarma.apply(4, check_event(enemy)), 4, 'Enemy: vanilla.')
	assert_eq(ReagKarma.streak, 1, 'Enemy rolls do not feed the streak either.')
	assert_eq(ReagKarma.apply(4, check_event(player)), 9, 'Player: corrected.')

# ---------------------------------------------------------------- roller

func test_a_save_is_attributed_to_the_saver_not_the_forcer():
	# A player Invading an enemy: the enemy rolls the save, so players_only must decline it.
	ReagKarma.prime(game.map, {players_only = true, kick_in = 1, strength = 5})
	ReagKarma.streak = 1
	assert_eq(ReagKarma.apply(4, save_event(player, enemy)), 4, 'The ENEMY rolled; not the player.')
	assert_eq(ReagKarma.corrections, 0, 'So nothing was corrected.')

func test_a_save_forced_on_the_player_is_the_players_roll():
	ReagKarma.prime(game.map, {players_only = true, kick_in = 1, strength = 5})
	ReagKarma.streak = 1
	assert_eq(ReagKarma.apply(4, save_event(enemy, player)), 9, 'The player rolled, so karma helps.')

func test_a_plain_check_still_uses_context_unit():
	# Not a save event and no AttackRoll: context.unit is all there is (roller() documents the gap).
	ReagKarma.prime(game.map, {players_only = true, kick_in = 1, strength = 5})
	ReagKarma.streak = 1
	assert_eq(ReagKarma.apply(4, check_event(player)), 9, 'Player check: corrected.')
	ReagKarma.streak = 1
	assert_eq(ReagKarma.apply(4, check_event(enemy)), 4, 'Enemy check: declined.')

func test_everyone_mode_takes_an_enemy():
	ReagKarma.prime(game.map, {players_only = false, kick_in = 1, strength = 5})
	ReagKarma.streak = 1
	assert_eq(ReagKarma.apply(4, check_event(enemy)), 9, 'Enemy corrected when players_only is off.')

# ---------------------------------------------------------------- threshold grading

func test_threshold_grading_counts_low_rolls_and_resets_on_a_good_one():
	ReagKarma.prime(game.map, {kick_in = 99, low_roll_threshold = 7})
	ReagKarma.apply(7, check_event(player))
	assert_eq(ReagKarma.streak, 1, 'At the threshold is bad.')
	ReagKarma.apply(1, check_event(player))
	assert_eq(ReagKarma.streak, 2, 'Below it is bad.')
	ReagKarma.apply(8, check_event(player))
	assert_eq(ReagKarma.streak, 0, 'Above it resets.')

func test_kick_in_boundary():
	# Correction applies when the streak BEFORE this roll has reached kick_in.
	ReagKarma.prime(game.map, {kick_in = 2, strength = 3, low_roll_threshold = 7})
	assert_eq(ReagKarma.apply(3, check_event(player)), 3, 'First bad roll: streak 0 before, no correction.')
	assert_eq(ReagKarma.apply(3, check_event(player)), 3, 'Second: streak 1 before, still none.')
	assert_eq(ReagKarma.apply(3, check_event(player)), 6, 'Third: streak 2 before => +3.')
	assert_eq(ReagKarma.corrections, 1, 'One correction recorded.')
	assert_eq(ReagKarma.last.raw, 3)
	assert_eq(ReagKarma.last.corrected, 6)
	assert_eq(ReagKarma.last.streak, 2, 'last.streak is the streak that triggered it.')

func test_the_corrected_value_is_what_gets_graded():
	# Karma helped, so a good corrected result ends the run - design §6 step 6.
	ReagKarma.prime(game.map, {kick_in = 1, strength = 3, low_roll_threshold = 7})
	ReagKarma.streak = 1
	assert_eq(ReagKarma.apply(5, check_event(player)), 8, '5 + 3.')
	assert_eq(ReagKarma.streak, 0, '8 > 7, so the streak resets even though the raw 5 was bad.')
	ReagKarma.streak = 1
	assert_eq(ReagKarma.apply(2, check_event(player)), 5, '2 + 3.')
	assert_eq(ReagKarma.streak, 2, '5 <= 7, still bad, streak grows.')

# ---------------------------------------------------------------- correction

func test_bonus_mode_caps_at_19_by_default():
	ReagKarma.prime(game.map, {kick_in = 1, strength = 5, allow_crits = false})
	ReagKarma.streak = 1
	assert_eq(ReagKarma.apply(16, check_event(player)), 19, '16 + 5 = 21, capped to 19.')

func test_bonus_mode_reaches_20_when_crits_are_allowed():
	ReagKarma.prime(game.map, {kick_in = 1, strength = 5, allow_crits = true})
	ReagKarma.streak = 1
	assert_eq(ReagKarma.apply(16, check_event(player)), 20, 'Capped to 20 instead.')

func test_the_cap_never_lowers_a_natural_roll():
	ReagKarma.prime(game.map, {kick_in = 1, strength = 5, allow_crits = false})
	ReagKarma.streak = 1
	assert_eq(ReagKarma.apply(20, check_event(player)), 20, 'A natural 20 is not turned into a 19.')
	assert_eq(ReagKarma.corrections, 0, 'And it does not count as a correction.')

func test_reroll_mode_keeps_the_higher_of_two_dice():
	ReagKarma.prime(game.map, {kick_in = 1, reroll_mode = true, strength = 19})
	ReagKarma.extra_die = func() -> int: return 12
	ReagKarma.streak = 1
	assert_eq(ReagKarma.apply(4, check_event(player)), 12, 'Extra die was higher.')
	ReagKarma.streak = 1
	assert_eq(ReagKarma.apply(15, check_event(player)), 15, 'Original was higher; strength 19 is ignored.')
	assert_eq(ReagKarma.corrections, 1, 'Keeping the original is not a correction.')

func test_reroll_mode_respects_the_cap():
	ReagKarma.prime(game.map, {kick_in = 1, reroll_mode = true, allow_crits = false})
	ReagKarma.extra_die = func() -> int: return 20
	ReagKarma.streak = 1
	assert_eq(ReagKarma.apply(4, check_event(player)), 19, 'A kept 20 is lowered to 19 when crits are disallowed.')
	ReagKarma.prime(game.map, {kick_in = 1, reroll_mode = true, allow_crits = true})
	ReagKarma.extra_die = func() -> int: return 20
	ReagKarma.streak = 1
	assert_eq(ReagKarma.apply(4, check_event(player)), 20, 'And allowed when they are.')

func test_a_correction_is_logged_to_the_battle_log():
	ReagKarma.prime(game.map, {kick_in = 1, strength = 3})
	ReagKarma.streak = 1
	var seen:Array[String] = []
	var catcher := func(text:String) -> void: seen.append(text)
	ReagKarma.battle_log.on_log_text.connect(catcher)
	ReagKarma.apply(4, check_event(player))
	ReagKarma.battle_log.on_log_text.disconnect(catcher)
	assert_eq(seen.size(), 1, 'One line logged.')
	if seen.is_empty(): return
	assert_true(seen[0].contains('from a 4 to a 7'), 'It names raw and corrected: %s' % seen[0])
	# If on_log_text never fires under X.TEST_MODE (it should - setup_gamemaster relies on the bus),
	# replace the signal capture with assertions on ReagKarma.last.raw / .corrected and say so in the
	# task report; do not drop the log call itself.

# ---------------------------------------------------------------- outcome-aware

func fresh_roll() -> AttackRoll:
	return AttackRoll.new() # hit defaults to false; pre/target left null on purpose (classify uses `is`, not is_valid)

func test_aware_mode_grades_the_previous_attack_lazily():
	ReagKarma.prime(game.map, {outcome_aware = true, kick_in = 2, strength = 3})
	var r1 := fresh_roll()
	assert_eq(ReagKarma.apply(10, attack_event(player, r1)), 10, 'Nothing pending yet, streak 0.')
	assert_true(ReagKarma.pending_roll == r1, 'r1 waits for its outcome.')
	r1.hit = false
	var r2 := fresh_roll()
	assert_eq(ReagKarma.apply(10, attack_event(player, r2)), 10, 'r1 graded as a miss => streak 1, below kick_in.')
	assert_eq(ReagKarma.streak, 1)
	r2.hit = false
	var r3 := fresh_roll()
	assert_eq(ReagKarma.apply(10, attack_event(player, r3)), 13, 'r2 miss => streak 2 => corrected.')
	r3.hit = true
	var r4 := fresh_roll()
	assert_eq(ReagKarma.apply(10, attack_event(player, r4)), 10, 'r3 hit => streak reset.')
	assert_eq(ReagKarma.streak, 0)

func test_aware_mode_ignores_the_raw_value():
	ReagKarma.prime(game.map, {outcome_aware = true, kick_in = 99, low_roll_threshold = 19})
	ReagKarma.apply(1, attack_event(player, fresh_roll()))
	assert_eq(ReagKarma.streak, 0, 'A natural 1 is not bad by itself in aware mode; only a miss is.')

func test_a_reroll_of_the_same_attack_is_neither_graded_nor_queued_twice():
	# event_unit_attack.gd:300 calls roll_attack again on the SAME AttackRoll (reroll take second).
	ReagKarma.prime(game.map, {outcome_aware = true, kick_in = 99})
	var r1 := fresh_roll()
	ReagKarma.apply(3, attack_event(player, r1))
	r1.hit = false # the first roll missed, which is WHY it is being rerolled - not final yet
	ReagKarma.apply(3, attack_event(player, r1))
	assert_true(ReagKarma.pending_roll == r1, 'Still the same single pending roll.')
	assert_eq(ReagKarma.streak, 0, 'And its provisional miss was not counted.')

func test_aware_mode_excludes_checks_entirely():
	ReagKarma.prime(game.map, {outcome_aware = true, mixed_mode = false, kick_in = 1, strength = 5, low_roll_threshold = 7})
	ReagKarma.streak = 1
	assert_eq(ReagKarma.apply(2, check_event(player)), 2, 'No nudge for a check.')
	assert_eq(ReagKarma.streak, 1, 'No grading either.')
	assert_eq(ReagKarma.last_seen.kind, ReagKarma.KIND.CHECK, 'It was classified, just excluded.')

func test_mixed_mode_grades_checks_by_threshold_into_the_same_streak():
	ReagKarma.prime(game.map, {outcome_aware = true, mixed_mode = true, kick_in = 2, strength = 3, low_roll_threshold = 7})
	var r1 := fresh_roll()
	ReagKarma.apply(10, attack_event(player, r1))
	r1.hit = false
	assert_eq(ReagKarma.apply(2, check_event(player)), 2, 'Check: streak 0 before (r1 not yet graded - grading is lazy, on the next ATTACK).')
	assert_eq(ReagKarma.streak, 1, 'The low check counted.')
	var r2 := fresh_roll()
	assert_eq(ReagKarma.apply(10, attack_event(player, r2)), 13, 'r1 is graded (miss) BEFORE the kick-in decision: streak 1 -> 2 => this attack is corrected.')
	assert_eq(ReagKarma.streak, 2, 'OUTCOME rolls are not threshold-graded, so the streak stays at 2.')
	assert_eq(ReagKarma.apply(2, check_event(player)), 5, 'Next check: streak 2 => corrected; both kinds share one run.')

# ---------------------------------------------------------------- per-combat memory

func test_a_new_map_resets_the_streak_and_reloads_config():
	ReagKarma.prime(game.map, {kick_in = 1, strength = 3})
	ReagKarma.streak = 1
	ReagKarma.pending_roll = fresh_roll()
	ReagKarma.config_source = func() -> Dictionary: return {strength = 9, kick_in = 1}

	var other_map:MapState = SpecFactory.create_map_state()
	var event := check_event(player)
	event.context.map = other_map

	assert_eq(ReagKarma.apply(10, event), 10, 'Fresh map: streak reset to 0, so no correction.')
	assert_eq(ReagKarma.config.strength, 9, 'Config was reloaded from the source.')
	assert_null(ReagKarma.pending_roll, 'Pending cleared.')
	assert_true(ReagKarma.map.get_ref() == other_map, 'Now bound to the new map.')
	assert_eq(ReagKarma.calls, 1, 'The call counter survives the reset (it is a liveness counter).')

func test_the_same_map_does_not_reload():
	ReagKarma.prime(game.map, {kick_in = 1, strength = 3})
	ReagKarma.config_source = func() -> Dictionary: return {strength = 9}
	ReagKarma.streak = 1
	assert_eq(ReagKarma.apply(10, check_event(player)), 13, 'Same map: config untouched, strength still 3.')
