# Script extension on the Dice autoload. Design: lancer-tactics-claude/specs/2026-09-12-karmic-dice-design.md §5
#
# Every attack, save, check and non-attack d20 in the game goes through
# roll_d20_with_player_interventions(event), which calls roll_d20() internally (dice.gd:147-148).
# Two overrides, both static like the originals:
#
#   1. roll_d20_with_player_interventions stashes the event and runs the vanilla body via super.
#   2. roll_d20 rolls exactly what vanilla rolls, then - only if a real event is stashed and no test
#      cheat is active - hands the value to ReagKarma.apply().
#
# The stash is consumed (cleared) inside roll_d20 the moment it is read, so a d20 rolled without an
# event during the vanilla body's later awaits (player intervention prompts) cannot pick it up.
#
# The cheat check runs BEFORE the roll: CHEAT_ROLL_QUEUE is consumed inside roll_dice exactly as
# vanilla consumes it, and a cheated value is returned untouched. Every unpacked mod is installed
# during every other mod's spec run, so this guard is what keeps their suites green.
#
# Overriding a static function on an autoload, and having the base's own internal call reach the
# override, is the same mechanism Reag-ThyHubris relies on for UnitRelation (is_adjacent ->
# adjacent_characters). spec/test_karma_probe.gd proves it for THIS file.
extends "res://engine/utils/dice.gd"

const ReagKarma := preload('res://unpacked/Reag-LancerKarmaDice/res/engine/utils/reag_karma.gd')

static var _current_event:EventCore = null

static func roll_d20_with_player_interventions(event:EventCore) -> int:
	_current_event = event
	var result:int = await super(event)
	_current_event = null # normally already consumed by roll_d20; belt and braces
	return result

static func roll_d20() -> int:
	var event:EventCore = _current_event
	_current_event = null
	var cheating:bool = CHEAT_ROLL_MAX or CHEAT_ROLL_LOW or not CHEAT_ROLL_QUEUE.is_empty()
	var raw:int = roll_and_sum({count = 1, dietype = 20})
	if cheating or event == null: return raw
	return ReagKarma.apply(raw, event)
