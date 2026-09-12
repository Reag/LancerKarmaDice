# Karmic Dice: the pure engine. Design: lancer-tactics-claude/specs/2026-09-12-karmic-dice-design.md
#
# dice.gd_ext.gd hands every real (non-cheated) d20 that was rolled for an event to apply(); this
# file decides whether and how to correct it. It knows nothing about Dice, and nothing here rolls
# the base die. The one piece of randomness (the extra die in reroll mode) is behind a Callable so
# specs can pin it.
#
# Everything scoped to "whose roll is this" - the players_only faction test and the battle-log line -
# goes through roller(), NOT context.unit: on a save event the engine puts the FORCING unit in
# context.unit and the saver in context.target_unit. See roller() for the residual gap on plain and
# contested checks.
#
# All state is static: there is one karma memory per game, reset whenever the map changes.
extends RefCounted

const MOD_ID := &'Reag-LancerKarmaDice'
const LOG_KEY := &'reag_karmic_dice.corrected.log'

## What kind of d20 this is. CHECK and BARE cannot be told apart at the seam today (neither puts
## anything on the context); classify() returns CHECK for both and no policy row treats them
## differently. Keep both values so a future row can split them. See design §6.
enum KIND { ATTACK, CHECK, BARE }
## How a kind is graded. EXCLUDED: not this mode's business, return raw untouched.
enum GRADER { EXCLUDED, THRESHOLD, OUTCOME }

const DEFAULTS := {
	enabled = true,
	players_only = true,
	outcome_aware = false,
	mixed_mode = false,
	reroll_mode = false,
	allow_crits = false,
	kick_in = 2,
	low_roll_threshold = 7,
	strength = 3,
}

static var config:Dictionary = DEFAULTS.duplicate()
static var policy:Dictionary = build_policy(DEFAULTS) # KIND => GRADER
static var streak:int = 0
static var map:WeakRef = null
static var pending_roll:Object = null # the last AttackRoll awaiting outcome grading (outcome-aware only)
static var calls:int = 0
static var corrections:int = 0
static var declined:int = 0 # rolls returned raw because players_only ruled the roller out
static var last_seen:Dictionary = {}
static var last:Dictionary = {}
## Set by unit_hasecheck.gd_ext.gd for the duration of UnitHasecheck.roll_check: the unit actually
## rolling a save, check or contested check. Null outside that window (and for every attack).
static var rolling_unit:Unit = null
static var battle_log:BattleLogBus = load('res://ui/component/battle_log/battle_log_bus.tres')

## Specs: forget everything. Config is left alone on purpose (prime() sets it).
static func reset() -> void:
	streak = 0
	map = null
	pending_roll = null
	calls = 0
	corrections = 0
	declined = 0
	last_seen = {}
	last = {}
	rolling_unit = null

## Specs: bind the state to this map with these config values, so apply() never goes to the
## baseline profile mid-test.
static func prime(for_map:MapState, values:Dictionary) -> void:
	reset()
	map = weakref(for_map)
	load_config(values)

## Where config values come from. Default: the baseline modset profile. Specs swap in a lambda.
static var config_source:Callable = read_baseline_values
## The one die this file rolls (reroll mode). Specs pin it.
static var extra_die:Callable = roll_extra_die

static func roll_extra_die() -> int:
	return 1 + (randi() % 20)

## The BASELINE profile, not Modset.get_current(): a campaign save freezes its own copy of the modset
## (campaign.gd:114, lancer_tactics.gd:86-89) and get_current() prefers it, so reading that would
## mean a change made in Mod Manage never reaches an existing campaign. get_baseline() is what Mod
## Manage's Apply changes just saved. Design §2, §4.
static func read_baseline_values() -> Dictionary:
	var modset:Modset = Modset.get_baseline()
	if modset == null: return {}
	# get_config never returns null - it falls back to ModConfig.create (modset.gd:105-107).
	return modset.get_config(MOD_ID).values

static func load_config(values:Dictionary) -> void:
	var merged:Dictionary = DEFAULTS.duplicate()
	for key in values:
		if merged.has(key): merged[key] = values[key]
	for key in ['enabled', 'players_only', 'outcome_aware', 'mixed_mode', 'reroll_mode', 'allow_crits']:
		merged[key] = bool(merged[key])
	merged.kick_in = clampi(int(merged.kick_in), 1, 20)
	merged.low_roll_threshold = clampi(int(merged.low_roll_threshold), 1, 19)
	merged.strength = clampi(int(merged.strength), 1, 19)
	config = merged
	policy = build_policy(config)

## Design §6, the seam for every mode: apply() looks up policy[kind] and never tests the flags.
static func build_policy(cfg:Dictionary) -> Dictionary:
	if not cfg.outcome_aware:
		return {KIND.ATTACK: GRADER.THRESHOLD, KIND.CHECK: GRADER.THRESHOLD, KIND.BARE: GRADER.THRESHOLD}
	var rest:GRADER = GRADER.THRESHOLD if cfg.mixed_mode else GRADER.EXCLUDED
	return {KIND.ATTACK: GRADER.OUTCOME, KIND.CHECK: rest, KIND.BARE: rest}

static func classify(event:EventCore) -> KIND:
	if event.context.object is AttackRoll: return KIND.ATTACK
	return KIND.CHECK

## Who actually rolled this die. For an attack it is context.unit. For anything that went through
## UnitHasecheck.roll_check (every save, check and contested check), unit_hasecheck.gd_ext.gd has
## stashed the exact roller in rolling_unit, which is authoritative. The two fallbacks below only
## matter if that extension is not live: a SAVE event names the FORCING unit in context.unit and the
## saver in context.target_unit (unit_hasecheck.gd run_save_event, event_unit_save.gd:38-39); a
## plain or contested check runs on whatever event the caller had, so context.unit is a guess.
static func roller(event:EventCore, kind:KIND) -> Unit:
	var context:Context = event.context
	if kind != KIND.ATTACK and Unit.is_valid(rolling_unit): return rolling_unit
	if kind != KIND.ATTACK and is_save_event(event) and Unit.is_valid(context.target_unit):
		return context.target_unit
	return context.unit

static func is_save_event(event:EventCore) -> bool:
	return event.base != null and event.base.event_type == &'event_unit_save'

static func apply(raw:int, event:EventCore) -> int:
	if event == null or event.context == null: return raw
	var context:Context = event.context
	calls += 1
	var kind:KIND = classify(event)
	var unit:Unit = roller(event, kind)
	last_seen = {raw = raw, kind = kind}

	if map == null or map.get_ref() != context.map:
		var keep_calls := calls
		reset()
		calls = keep_calls
		map = weakref(context.map)
		load_config(config_source.call())

	if not config.enabled: return raw
	if config.players_only:
		if not Unit.is_valid(unit) or unit.get_faction() != Faction.PLAYER:
			declined += 1
			return raw
	var grader:GRADER = policy.get(kind, GRADER.EXCLUDED)
	if grader == GRADER.EXCLUDED: return raw

	if grader == GRADER.OUTCOME:
		grade_pending(context.object)
		remember_pending(context.object)

	var streak_before:int = streak
	var corrected:int = correct(raw) if streak >= config.kick_in else raw

	if grader == GRADER.THRESHOLD:
		grade_threshold(corrected)

	if corrected != raw:
		record(raw, corrected, kind, streak_before, context, unit)
	return corrected

## Bonus or reroll, then the crit cap - but never below the raw die (a natural 20 stays 20).
static func correct(raw:int) -> int:
	var boosted:int = maxi(raw, int(extra_die.call())) if config.reroll_mode else raw + config.strength
	var cap:int = 20 if config.allow_crits else 19
	return maxi(raw, mini(boosted, cap))

static func grade_threshold(value:int) -> void:
	streak = streak + 1 if value <= config.low_roll_threshold else 0

## `context` is only read for the AttackRoll; `unit` is the roller (see roller()), which is who the
## battle-log line must name.
static func record(raw:int, corrected:int, kind:KIND, streak_before:int, context:Context, unit:Unit) -> void:
	corrections += 1
	last = {
		raw = raw,
		corrected = corrected,
		kind = kind,
		streak = streak_before,
		attack_roll = context.object if kind == KIND.ATTACK else null,
	}
	if Unit.is_valid(unit):
		battle_log.log_unit(LOG_KEY, unit, {raw = raw, corrected = corrected})
	print('    KARMA: %s -> %s (streak %s, %s)' % [raw, corrected, streak_before, KIND.keys()[kind]])

## Grade the pending AttackRoll by its hit flag, which is final by the time the NEXT d20 is rolled
## (attack_roll.gd:72 sets it right after the roll; later sequence steps may flip it, but all of them
## run before any other d20). Skipped when the pending roll IS the current one: a reroll re-enters
## the seam with the same object and its hit flag is provisional. Only one roll is ever pending,
## because every outcome-graded call grades and clears the previous one.
static func grade_pending(current:Object) -> void:
	if pending_roll == null or pending_roll == current: return
	streak = 0 if pending_roll.hit else streak + 1
	pending_roll = null

static func remember_pending(current:Object) -> void:
	pending_roll = current
