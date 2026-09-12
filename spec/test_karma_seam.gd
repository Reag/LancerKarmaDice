# Through the real attack path. What the helper specs cannot prove: that the corrected value is
# what vanilla actually uses (AttackRoll.base_roll), that the cheat guard protects other mods'
# suites in practice, and that faction scoping works on real units.
#
# Determinism without seeding the RNG: strength 19 with kick_in 1 and a primed streak turns any raw
# d20 BELOW the cap into exactly the cap - 19, or 20 with allow_crits - so the corrected base_roll is
# a fixed number. A raw that already meets the cap is left alone by correct() (it never returns below
# raw) and records nothing at all; that branch is what assert_corrected_to() below exists for.
extends GutTest

const ReagKarma := preload('res://unpacked/Reag-LancerKarmaDice/res/engine/utils/reag_karma.gd')

var game:Gamemaster
var shooter:Unit
var target:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)

func after_each():
	ReagKarma.reset()
	Dice.CHEAT_ROLL_QUEUE.clear()

func arm(faction:Faction.SIDE) -> void:
	shooter = SpecFactory.create_unit(game.map, Vector2i(0,0), faction)
	shooter.core.equip_system(&'mw_assault_rifle')
	var other:Faction.SIDE = Faction.AI_ENEMY if faction == Faction.PLAYER else Faction.PLAYER
	target = SpecFactory.create_unit(game.map, Vector2i(1,1), other)

func shoot() -> void:
	await SpecFactory.start_turn(game, shooter)
	await SpecFactory.use_solo(game, shooter, &'mw_assault_rifle', target)

## strength 19 + kick_in 1 + primed streak corrects ANY raw die to the cap - except a raw that is
## ALREADY at or above the cap, which correct() leaves alone (it never returns below raw), so no
## correction is recorded at all. `expected` is the cap, so that is exactly what to branch on: with
## allow_crits off (cap 19) both a 19 and a 20 are pass-throughs, with it on only a 20 is.
func assert_corrected_to(expected:int, check_base_roll:bool = true) -> void:
	var raw:int = ReagKarma.last_seen.get('raw', 0)
	if raw >= expected:
		assert_eq(ReagKarma.corrections, 0, 'A raw %s already meets the cap of %s, so it is never corrected.' % [raw, expected])
		return
	assert_eq(ReagKarma.corrections, 1, 'One correction (raw %s).' % raw)
	if ReagKarma.last.is_empty(): return fail_test('A correction was recorded.')
	assert_eq(ReagKarma.last.corrected, expected, 'Corrected to the cap.')
	if check_base_roll and ReagKarma.last.attack_roll is AttackRoll:
		assert_eq(ReagKarma.last.attack_roll.base_roll, expected, 'And vanilla used the corrected value as the base roll.')

func test_a_primed_player_attack_is_corrected_all_the_way_to_base_roll():
	arm(Faction.PLAYER)
	ReagKarma.prime(game.map, {kick_in = 1, strength = 19, allow_crits = false})
	ReagKarma.streak = 1
	await shoot()
	assert_corrected_to(19)
	if ReagKarma.corrections > 0:
		assert_true(ReagKarma.last.attack_roll is AttackRoll, 'The AttackRoll was retained.')

func test_crits_allowed_reaches_20():
	arm(Faction.PLAYER)
	ReagKarma.prime(game.map, {kick_in = 1, strength = 19, allow_crits = true})
	ReagKarma.streak = 1
	await shoot()
	assert_corrected_to(20)

func test_a_cheated_roll_passes_through_even_with_a_primed_streak():
	# THE guard for every other mod's suite.
	arm(Faction.PLAYER)
	ReagKarma.prime(game.map, {kick_in = 1, strength = 19})
	ReagKarma.streak = 1
	Dice.CHEAT_ROLL_QUEUE.append(5)
	await shoot()
	assert_eq(ReagKarma.calls, 0, 'Helper never consulted.')
	assert_eq(ReagKarma.corrections, 0, 'Nothing corrected.')
	assert_true(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'The queued 5 was consumed by the attack roll exactly as vanilla consumes it.')

func test_an_enemy_attack_is_left_alone_under_players_only():
	arm(Faction.AI_ENEMY)
	ReagKarma.prime(game.map, {players_only = true, kick_in = 1, strength = 19})
	ReagKarma.streak = 1
	await shoot()
	assert_eq(ReagKarma.calls, 1, 'The seam saw it.')
	assert_eq(ReagKarma.corrections, 0, 'And declined it.')

func test_an_enemy_attack_is_corrected_in_everyone_mode():
	arm(Faction.AI_ENEMY)
	ReagKarma.prime(game.map, {players_only = false, kick_in = 1, strength = 19})
	ReagKarma.streak = 1
	await shoot()
	assert_corrected_to(19)

# ---------------------------------------------------------------- real saves
# The engine attributes a save event to the FORCING unit (context.unit) and puts the roller in
# context.target_unit, so players_only has to read the roller, not context.unit.

## Force a real systems save on `saver`, forced by `forcer`. Vanilla pattern, copied from
## test/gear/test_ms_stable_structure.gd:14-27. CHEAT_ROLL_QUEUE must be empty (after_each clears it)
## or the seam's cheat guard skips the helper entirely.
func force_save(saver:Unit, forcer:Unit) -> void:
	var dummy_event := SpecFactory.dummy_event()
	dummy_event.block = EventBlock.create_multiple([dummy_event])
	add_child_autoqfree(dummy_event.block)
	await UnitHasecheck.make_systems_save(dummy_event, saver, SpecificAction.from_id(forcer, &'ms_fragment_signal'), [])

func test_a_save_forced_by_a_player_on_an_enemy_is_the_enemys_roll():
	arm(Faction.PLAYER) # shooter is the player (forcer), target is the enemy (saver)
	ReagKarma.prime(game.map, {players_only = true, kick_in = 1, strength = 19})
	ReagKarma.streak = 1
	await force_save(target, shooter)
	assert_eq(ReagKarma.calls, 1, 'The seam saw the save roll.')
	assert_eq(ReagKarma.corrections, 0, 'The ENEMY rolled it, so players_only declined it.')
	assert_eq(ReagKarma.streak, 1, 'A declined roll does not feed the streak either (a misattributed roll would have graded it to 0 or 2).')

func test_a_save_forced_on_the_player_is_corrected():
	arm(Faction.AI_ENEMY) # shooter is the enemy (forcer), target is the player (saver)
	ReagKarma.prime(game.map, {players_only = true, kick_in = 1, strength = 19})
	ReagKarma.streak = 1
	await force_save(target, shooter)
	assert_eq(ReagKarma.calls, 1, 'The seam saw the save roll.')
	assert_corrected_to(19, false) # no AttackRoll on a save

func test_a_contested_check_attributes_each_roll_to_its_own_roller():
	# unit_hasecheck.gd:10-12 - BOTH units roll on the ONE event, so nothing on the event can tell
	# the two rolls apart; only the stash set by unit_hasecheck.gd_ext.gd (the roll_check override)
	# can. This is the test that proves that extension is live: without it both rolls are attributed
	# to the event's unit (the player), so nothing is declined; with it exactly the enemy's roll is.
	arm(Faction.PLAYER)
	ReagKarma.prime(game.map, {players_only = true, kick_in = 99})
	var dummy_event := SpecFactory.dummy_event({unit = shooter})
	dummy_event.block = EventBlock.create_multiple([dummy_event])
	add_child_autoqfree(dummy_event.block)
	await UnitHasecheck.make_contested_hull_check(dummy_event, shooter, target, null, [])
	assert_eq(ReagKarma.calls, 2, 'Both units rolled through the seam.')
	assert_eq(ReagKarma.declined, 1, 'Exactly one roll (the enemy\'s) was declined by players_only; 0 means both went to the player, 2 means both to the enemy.')
	assert_null(ReagKarma.rolling_unit, 'The stash is cleared after each roll.')

func test_disabled_is_vanilla():
	arm(Faction.PLAYER)
	ReagKarma.prime(game.map, {enabled = false, kick_in = 1, strength = 19})
	ReagKarma.streak = 1
	await shoot()
	assert_eq(ReagKarma.calls, 1)
	assert_eq(ReagKarma.corrections, 0)

func test_an_attack_that_missed_feeds_the_aware_streak_for_real():
	arm(Faction.PLAYER)
	target.core.frame.stat.evasion = 30 # dummy frame is per-unit (SpecFactory.create_unit_core), safe to edit
	ReagKarma.prime(game.map, {outcome_aware = true, kick_in = 1, strength = 19})
	await shoot() # cannot hit evasion 30; queued as pending, not yet graded
	assert_eq(ReagKarma.streak, 0, 'Lazy: not graded until the next attack.')
	await shoot()
	# The miss was graded on the second roll, which was then corrected.
	assert_corrected_to(19)
