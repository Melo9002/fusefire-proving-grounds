# Mission outcome fixes — 2026-11-18

Issues #39, #40 and #41, all found by the milestone 05 step-2 baseline ([AI baseline](ai-baseline-2026-11-18.md)). Evidence level: automated (E2), plus reruns of the affected baseline matches. No human playtest.

## #39 Extract reported Victory after a squad wipe — fixed

**Rule now:** an Extract mission is won only when someone actually got out. Units lost after an extraction do not undo it.

**Cause:** each death lowers the number of units that must extract, so a wiped squad with nobody extracted read `extracted_units (0) >= total_units (0)` and the Victory shortcut fired before the Defeat branch. `can_end_mission_early` already required `extracted_units + extracted_vips > 0`; the shortcut did not.

**Fix:** the same condition on the Victory shortcut in `ObjectiveManager._evaluate_outcome_rules`.

**Proof:** `tests/squad_loss_outcome_test.gd` fails on the old code and passes after, and also checks that losing units after an extraction is still a Victory. The three baseline matches that ended in a false Victory (`freight_yard` 16 and 17, `fleet_station` 16) rerun as Defeat; `fleet_station` 17, a genuine win, is unchanged.

## #40 Rescue could strand the VIP — fixed (option A)

**What was really wrong:** the issue described the last escort extracting and leaving the VIP behind. The cause is earlier: when a **carrier** died, its carried VIP was neither released nor killed. It stayed hidden and disabled, the Rescue objective stayed completed, and the mission was silently unwinnable but not lost. The baseline's lone extract was only the end of that.

**Rule now:** when a carrier falls, the VIP is put down where the carrier stood (the nearest cell that can be stood on if that one cannot), visible and active, and the **Rescue objective reopens** so any pursuing unit can carry it again. Until it is carried again, escorts cannot extract (the VIP is still outstanding). If there is nowhere at all to put it, the VIP is lost with its extraction objective (a Defeat). A fallen unit that carries nobody changes nothing.

**Where:** `TacticalUnit.release_carried_unit()` restores the passenger and the carrier's speed; `ObjectiveManager.release_carried_unit()` places the VIP and reopens the objective; `BattleController._on_unit_defeated` calls it after the carrier has left the grid. It is a deterministic consequence of the action that killed the carrier, so replay re-executes it.

**Proof:** `tests/rescue_carrier_loss_test.gd`, 28 checks: the drop, the reopen, escorts blocked from extracting, a teammate recovering the VIP, the mission still winnable, the blocked-cell fallback, and a non-carrier loss changing nothing. 12 of them fail on the old code.

**Effect on the baseline (six Rescue matches rerun):**

| Match | Before | After |
| --- | --- | --- |
| `freight_yard` 16 | Defeat, round 5 | **Victory**, round 9 (the AI went back for the dropped VIP) |
| `service_depot` 16, `fleet_station` 17 | Defeat | Defeat: the whole squad is dead and nobody extracted, honest tactical losses |
| the other three | Victory | Victory, unchanged |

The "last unit extracts alone and leaves the VIP" pattern no longer occurs.

## #41 Enemy Evacuation seed 17 — investigated, not a placement bug

Path cost to the exit (enemies 41-49, players 4-23) shows the players are about twice as close as the enemies on every site and seed; the enemies need about 3 rounds. The loss is the player AI failing to stop three 100 HP enemies in about 3 rounds. That belongs to milestone 05 steps 9 and 10 (an interception behavior, pacing). The issue stays open; the numbers are on it.

## Suites

Missions 17, replay 17, AI 32, combat 39, movement 24, UI 26 passed, 0 failed, after the #40 change. The #39 change passed missions 16, replay 17 and AI 31.

## Limits

- The 48-match baseline was not rerun in full after #40; only the six Rescue and four Extract matches were.
- Picking the VIP up again uses the existing Rescue action; there is no new UI for it.
- The VIP stays on the grid where it dropped; there is no separate "dropped" presentation.
