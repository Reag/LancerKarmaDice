# Karma Dice for Lancer

A [Lancer Tactics](https://wickworks.itch.io/lancer-tactics) mod that takes the edge off bad luck.
After a run of bad d20 results, the next roll gets a nudge upward, in the spirit of Baldur's
Gate 3's Karmic Dice. Who it helps, what counts as bad, how hard it nudges and whether it may
manufacture a crit are all yours to set from the in-game Mod Manage panel. No restart needed to
change a setting, and switching it off is one checkbox.

Requires Lancer Tactics **1.4.2**.

## What it does

The game rolls one d20 for every attack, save, check and contested check. Karma Dice watches those
rolls and keeps a running count of consecutive bad results. Once the run reaches the kick-in count,
the next eligible d20 is corrected: either a flat bonus is added, or one extra d20 is rolled and the
higher kept. A corrected roll is then capped so that karma never turns a miss into a critical hit
unless you allow it. A good result ends the run. Memory resets at the start of every combat.

Corrections are visible: each one writes a line to the battle log naming the mech, the raw die and
the corrected value.

## Settings

Open Mod Manage, select Karma Dice, and change any of these. Press **Apply changes** and the new
values take effect at the start of your next combat, including in a campaign you are already
playing.

| Setting | Default | What it does |
|---|---|---|
| Enabled | on | Master switch. Off means every roll is vanilla. |
| Players only | on | On: only your own mechs get karma. Off: everyone does, enemies included, sharing one run. |
| Outcome-aware | off | Off: a bad result is a low raw d20 on any roll. On: a bad result is a **missed attack**; saves and checks are ignored unless Mixed mode is on. |
| Mixed mode | off | Only with Outcome-aware on: saves, checks and other non-attack d20s use the low-roll rule and count toward the same run. |
| Reroll instead of bonus | off | Off: adds Strength to the die. On: rolls one extra d20 and keeps the higher. Strength is ignored. |
| Allow karma crits | off | Off: a corrected roll is capped at 19. On: it may reach 20. |
| Kick-in | 2 | How many bad results in a row before karma corrects the next roll. 1 to 20. |
| Low roll threshold | 7 | A raw d20 at or below this counts as bad. 1 to 19. |
| Strength | 3 | Bonus added once karma is active. 1 to 19. Ignored in reroll mode. |

Attacks include tech attacks such as Invade. A natural 20 is never lowered by the cap, and a die
that already meets the cap is left alone.

## Good to know

- **Enabling or disabling the mod itself asks for a restart.** It extends two of the game's core
  services, which the game treats as a substantial change. Changing settings never does.
- **It also fixes the config panel.** Lancer Tactics 1.4.2 has two small bugs in Mod Manage: the
  panel never shows a mod's default values, and changing a value never offers Apply changes. This
  mod patches both from the mod side, for every mod with settings, not just itself. The bugs are
  reported to Wickworks; the patches are harmless once they are fixed upstream.
- **Other mods.** Karma Dice extends `dice.gd` and `unit_hasecheck.gd` rather than replacing them,
  so it coexists with any mod that does the same. A mod that replaces either file wholesale will
  silently switch karma off.
- **Game updates.** Each Lancer Tactics patch release needs a matching entry in this mod's
  manifest before the game stops warning about a version mismatch.

## For developers

Everything under `res/` mirrors the game's own paths:

- `res/engine/utils/dice.gd_ext.gd` extends the `Dice` autoload and hands every real d20 (test
  cheats excluded) to the helper.
- `res/engine/utils/reag_karma.gd` is the whole rulebook: config, the per-kind grading policy,
  the streak, and the correction. It knows nothing about `Dice`, so it can be tested directly.
- `res/engine/character/unit/service/unit_hasecheck.gd_ext.gd` records which unit is rolling a
  save or check, since the engine's event names the unit that forced it.
- `res/ui/page/omninet/mod_manage/*.gd_ext.gd` are the two config-panel patches.

Panel text lives in `localization/localizations.csv`; the manifest's schema carries translation
keys, so corrections and other languages never touch the manifest.

The `spec/` folder holds the GUT suite (55 tests), written against the modkit's
`test/factory/spec_factory.gd`. Run it from the Lancer Tactics modkit with this folder checked out
under `unpacked/`, using the GUT panel in the editor pointed at `res://unpacked/Reag-LancerKarmaDice/spec`,
or any GUT runner that loads the modkit's `test/factory/pre_run_hook.gd` first. Run it windowed, not
headless: a headless viewport makes every gear-activating spec fail on an engine error.

The specs ship inside the release zip. They are inert there; only `res/` is loaded by the game.
