# THE probe. Does a .gd_ext.gd on engine/utils/dice.gd actually run? Three engine files install
# cleanly and never fire (CLAUDE.md, "Dead extension seams"), and nobody knows why, so this is not
# assumed. It also proves the two-layer stash: roll_d20_with_player_interventions stashes the
# event, roll_d20 consumes it, and a cheated roll never reaches the helper at all.
#
# If every test here fails with calls == 0, check the editor/game log for a parse error in
# dice.gd_ext.gd first (a script that fails to parse installs "successfully" and does nothing).
# The likeliest culprit is `await super(event)` inside a static coroutine; see the plan's fallback.
extends GutTest

const ReagKarma := preload('res://unpacked/Reag-LancerKarmaDice/res/engine/utils/reag_karma.gd')

var game:Gamemaster
var shooter:Unit
var target:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	shooter = SpecFactory.create_unit(game.map, Vector2i(0,0))
	shooter.core.equip_system(&'mw_assault_rifle')
	target = SpecFactory.create_unit(game.map, Vector2i(1,1), Faction.AI_ENEMY)
	ReagKarma.prime(game.map, {}) # defaults; streak 0, so nothing is corrected - this file only watches the seam

func after_each():
	ReagKarma.reset()
	Dice.CHEAT_ROLL_QUEUE.clear()

func test_a_real_attack_roll_reaches_the_helper_as_an_attack():
	await SpecFactory.start_turn(game, shooter)
	await SpecFactory.use_solo(game, shooter, &'mw_assault_rifle', target)
	assert_eq(ReagKarma.calls, 1, 'Exactly one d20 went through the seam (the attack roll; damage dice are not d20s).')
	assert_eq(ReagKarma.last_seen.get('kind', -1), ReagKarma.KIND.ATTACK, 'It was classified as an attack (context.object is the AttackRoll).')
	var raw:int = ReagKarma.last_seen.get('raw', 0)
	assert_true(raw >= 1 and raw <= 20, 'The raw value is a d20 face, got %s.' % raw)

func test_a_cheated_roll_never_reaches_the_helper():
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await SpecFactory.start_turn(game, shooter)
	await SpecFactory.use_solo(game, shooter, &'mw_assault_rifle', target)
	assert_eq(ReagKarma.calls, 0, 'The cheat guard runs before the roll, so the helper is never consulted.')

func test_a_bare_roll_with_no_event_never_reaches_the_helper():
	await SpecFactory.start_turn(game, shooter)
	await SpecFactory.use_solo(game, shooter, &'mw_assault_rifle', target)
	assert_eq(ReagKarma.calls, 1, 'Sanity: one call.')
	# roll_d20() called outside roll_d20_with_player_interventions has no stashed event (bark chance,
	# gamemaster.gd:310), so it must be vanilla and must not be counted.
	var bare := Dice.roll_d20()
	assert_true(bare >= 1 and bare <= 20, 'Bare roll is a d20 face.')
	assert_eq(ReagKarma.calls, 1, 'A roll with no stashed event does not reach the helper.')
