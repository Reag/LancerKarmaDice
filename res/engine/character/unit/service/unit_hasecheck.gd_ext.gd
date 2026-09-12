# Script extension on the UnitHasecheck autoload. Design §8, probed 2026-09-12.
#
# Every save, check and contested check rolls its d20 inside UnitHasecheck.roll_check(event, unit,
# ...), and `unit` there IS the unit rolling. The event it passes on to Dice does not carry that:
# a save event names the forcer in context.unit (event_unit_save.gd:38-39), and a plain or
# contested check runs on whatever event the caller had - in a contested check BOTH units roll on
# the one event (unit_hasecheck.gd:10-12). So reag_karma.gd's roller() could only guess for those.
#
# This override records the rolling unit just before the die is thrown and clears it after, so
# roller() can prefer it over any guess. The stash is consumed inside the same synchronous window
# as Dice's own event stash: roll_check's first await is the d20 itself.
#
# UnitHasecheck is an autoload with no class_name, but that is not proof a .gd_ext.gd fires on it
# (unit_action.gd installs cleanly and never runs - CLAUDE.md, dead seams). Whether THIS one fires
# is decided by spec/test_karma_seam.gd's contested-check test, which cannot pass without it.
# mod_main.gd reloads the live autoload node after install (1.4.x bug 5), same as for Dice.
extends "res://engine/character/unit/service/unit_hasecheck.gd"

const ReagKarma := preload('res://unpacked/Reag-LancerKarmaDice/res/engine/utils/reag_karma.gd')

static func roll_check(
	event:EventCore,
	unit:Unit,
	flat_bonus:int,
	hase_type:Lancer.HASE,
	forcing_action:SpecificAction = null,
	is_save:bool = false,
	flags_and_statuses:Array = []
) -> int:
	ReagKarma.rolling_unit = unit
	var result:int = await super(event, unit, flat_bonus, hase_type, forcing_action, is_save, flags_and_statuses)
	ReagKarma.rolling_unit = null
	return result
