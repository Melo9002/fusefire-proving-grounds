# AI baseline, milestone 05 step 2 — 2026-11-18

Starting commit: `bddac04` (plus the passive per-round sampler described below). This records what the current AI does before any step 3+ behavior change. It is automated evidence (E2); it is not a playtest and says nothing about how the battles look or feel.

## How it was measured

- Harness: `tests/ai_baseline_report.gd` (explicit-only; in no Ironclad tier) drives the real battle scene through `AIMatchSimulator`, so movement, combat, missions and turns are the real rules. `tools/quality/ai_baseline_summary.py` turns its JSON and the `[AIPlan]` log lines into the table below.
- Matrix: Service Depot, Freight Yard, Fleet Station x all 8 mission kinds x seeds 16 and 17 = **48 matches**, run one at a time. Three player units vs three enemies (one extra ally in Protect/Rescue, plus the VIP in Protect), Normal difficulty, default commanders, 30-round limit, 8 s stall limit, 60 s timeout, `Engine.time_scale` 12, headless. No match hit any limit.
- Reproduce: `godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=main profile-ai`, then `python tools/quality/ai_baseline_summary.py artifacts/ai-baseline/main --log <godot log>`. Arguments: `site=`, `mission=`, `seeds=`, `difficulty=`, `players=`, `enemies=`.
- Information available to the AI is unchanged: it reads the live battlefield, with no fog-of-war or perception filter.
- Diagnostics only read state. The simulator gained passive per-round samples (objective progress, HP and units alive per side); no decision or random draw depends on them.

## Results

All 48 matches completed; none stalled, hit the round limit or timed out. 3,415 AI decisions, **0 rejected actions**, **0 immediate there-and-back moves** (A to B followed by B to A).

| Mission | Runs | Victory | Defeat | Avg rounds | Avg time s | Avg waits | Avg planning ms/match |
|---|---|---|---|---|---|---|---|
| Eliminate | 6 | 6 | 0 | 6.7 | 7.8 | 6.2 | 1642 |
| Enemy Evacuation | 6 | 3 | 3 | 5.2 | 8.8 | 5.8 | 2045 |
| Extract | 6 | 6* | 0 | 5.5 | 11.1 | 8.7 | 2803 |
| Interact Terminal | 6 | 6 | 0 | 2.8 | 5.6 | 0.2 | 1369 |
| Protect | 6 | 5 | 1 | 8.3 | 13.5 | 19.8 | 2798 |
| Reach | 6 | 6 | 0 | 2.0 | 3.7 | 0.0 | 565 |
| Rescue | 6 | 3 | 3 | 6.0 | 12.2 | 4.3 | 2342 |
| Survive | 6 | 6 | 0 | 6.8 | 13.9 | 11.2 | 3043 |

\* Three of these six "Victories" are wrong; see finding 1. "Completed" in simulator output means the match ended, not that the mission succeeded.

**Planning time** (movement goal-path planning only, `_move_along_goal_path`, frame yields excluded): 2,336 plans, mean 42.7 ms, median 33.1, p95 99.7, p99 149.7, **max 238.2 ms**; 27% exceed 50 ms and 5% exceed 100 ms. The slowest matches are Protect/Survive/Extract on Depot and Fleet Station. Target scoring and other decision work are not included. No budget exists yet; step 11 owns that.

Per-match detail (Time is simulator wall time at 12x scale; "Returns" is immediate there-and-back moves; "Stagnant rds" is rounds with no change in objective progress, HP or units alive):

| Match | Status | Result | Rounds | Time s | Dec | Rej | Move | Atk | Wait | Guard | Aim | Returns | Stagnant rds | 1st progress rd | Plans | Think total ms | Think max ms | >50 ms |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| fleet_station-ELIMINATE-16 | Completed | Victory | 5 | 5.8 | 56 | 0 | 26 | 23 | 0 | 0 | 4 | 0 | 1 | 3 | 26 | 951 | 63 | 3 |
| fleet_station-ELIMINATE-17 | Completed | Victory | 4 | 4.8 | 48 | 0 | 23 | 21 | 0 | 0 | 3 | 0 | 1 | 4 | 23 | 756 | 56 | 2 |
| fleet_station-ENEMY_EVACUATION-16 | Completed | Victory | 4 | 6.8 | 47 | 0 | 30 | 13 | 2 | 1 | 0 | 0 | 1 | 3 | 33 | 1564 | 110 | 11 |
| fleet_station-ENEMY_EVACUATION-17 | Completed | Defeat | 3 | 6.8 | 46 | 0 | 33 | 10 | 0 | 1 | 1 | 0 | 1 | 3 | 34 | 1354 | 92 | 7 |
| fleet_station-EXTRACT-16 | Completed | Victory | 9 | 15.6 | 109 | 0 | 46 | 24 | 21 | 5 | 9 | 0 | 2 | - | 77 | 5378 | 174 | 49 |
| fleet_station-EXTRACT-17 | Completed | Victory | 3 | 6.3 | 48 | 0 | 29 | 13 | 3 | 0 | 1 | 0 | 1 | 3 | 34 | 1403 | 94 | 9 |
| fleet_station-INTERACT_TERMINAL-16 | Completed | Victory | 6 | 10.9 | 76 | 0 | 46 | 20 | 1 | 4 | 4 | 0 | 1 | 6 | 61 | 3512 | 99 | 35 |
| fleet_station-INTERACT_TERMINAL-17 | Completed | Victory | 2 | 3.8 | 21 | 0 | 21 | 0 | 0 | 0 | 0 | 0 | 1 | 2 | 21 | 732 | 102 | 2 |
| fleet_station-PROTECT-16 | Completed | Victory | 6 | 10.3 | 96 | 0 | 44 | 26 | 13 | 6 | 5 | 0 | 2 | 5 | 50 | 1752 | 111 | 10 |
| fleet_station-PROTECT-17 | Completed | Victory | 8 | 14.2 | 120 | 0 | 57 | 23 | 19 | 16 | 2 | 0 | 4 | 5 | 70 | 3360 | 174 | 19 |
| fleet_station-REACH-16 | Completed | Victory | 2 | 3.4 | 21 | 0 | 21 | 0 | 0 | 0 | 0 | 0 | 1 | 2 | 21 | 504 | 36 | 0 |
| fleet_station-REACH-17 | Completed | Victory | 2 | 4.0 | 24 | 0 | 24 | 0 | 0 | 0 | 0 | 0 | 1 | 2 | 24 | 589 | 35 | 0 |
| fleet_station-RESCUE-16 | Completed | Victory | 7 | 12.2 | 112 | 0 | 62 | 26 | 6 | 4 | 2 | 0 | 1 | 3 | 67 | 2173 | 87 | 9 |
| fleet_station-RESCUE-17 | Completed | Defeat | 5 | 9.6 | 79 | 0 | 52 | 17 | 0 | 6 | 1 | 0 | 2 | 4 | 58 | 1586 | 64 | 1 |
| fleet_station-SURVIVE-16 | Completed | Victory | 7 | 12.9 | 90 | 0 | 50 | 14 | 13 | 10 | 0 | 0 | 0 | 2 | 64 | 2411 | 98 | 15 |
| fleet_station-SURVIVE-17 | Completed | Victory | 9 | 18.6 | 108 | 0 | 62 | 11 | 18 | 13 | 0 | 0 | 2 | 2 | 84 | 5657 | 216 | 46 |
| freight_yard-ELIMINATE-16 | Completed | Victory | 8 | 11.5 | 91 | 0 | 38 | 24 | 14 | 9 | 1 | 0 | 2 | 7 | 61 | 3153 | 168 | 27 |
| freight_yard-ELIMINATE-17 | Completed | Victory | 8 | 7.8 | 71 | 0 | 31 | 23 | 6 | 7 | 1 | 0 | 3 | 4 | 44 | 1486 | 70 | 5 |
| freight_yard-ENEMY_EVACUATION-16 | Completed | Victory | 10 | 12.2 | 89 | 0 | 39 | 16 | 21 | 6 | 5 | 0 | 4 | 3 | 66 | 3229 | 100 | 26 |
| freight_yard-ENEMY_EVACUATION-17 | Completed | Defeat | 3 | 6.4 | 46 | 0 | 29 | 11 | 1 | 1 | 3 | 0 | 1 | 3 | 33 | 1423 | 95 | 11 |
| freight_yard-EXTRACT-16 | Completed | Victory | 8 | 11.1 | 82 | 0 | 38 | 15 | 19 | 4 | 3 | 0 | 3 | - | 61 | 3066 | 110 | 22 |
| freight_yard-EXTRACT-17 | Completed | Victory | 4 | 9.9 | 65 | 0 | 41 | 16 | 3 | 2 | 1 | 0 | 1 | - | 48 | 2766 | 134 | 24 |
| freight_yard-INTERACT_TERMINAL-16 | Completed | Victory | 2 | 4.8 | 27 | 0 | 26 | 0 | 0 | 1 | 0 | 0 | 1 | 2 | 27 | 1149 | 171 | 2 |
| freight_yard-INTERACT_TERMINAL-17 | Completed | Victory | 2 | 4.2 | 24 | 0 | 24 | 0 | 0 | 0 | 0 | 0 | 1 | 2 | 24 | 994 | 98 | 6 |
| freight_yard-PROTECT-16 | Completed | Victory | 6 | 9.8 | 92 | 0 | 40 | 27 | 13 | 4 | 5 | 0 | 2 | 5 | 44 | 1557 | 106 | 9 |
| freight_yard-PROTECT-17 | Completed | Defeat | 10 | 13.1 | 131 | 0 | 49 | 30 | 25 | 13 | 8 | 0 | 3 | 5 | 65 | 2349 | 108 | 14 |
| freight_yard-REACH-16 | Completed | Victory | 2 | 3.4 | 21 | 0 | 21 | 0 | 0 | 0 | 0 | 0 | 1 | 2 | 21 | 524 | 34 | 0 |
| freight_yard-REACH-17 | Completed | Victory | 2 | 4.1 | 24 | 0 | 24 | 0 | 0 | 0 | 0 | 0 | 1 | 2 | 24 | 631 | 35 | 0 |
| freight_yard-RESCUE-16 | Completed | Defeat | 5 | 12.0 | 89 | 0 | 54 | 19 | 5 | 1 | 3 | 0 | 1 | 3 | 58 | 2675 | 182 | 15 |
| freight_yard-RESCUE-17 | Completed | Victory | 6 | 10.7 | 95 | 0 | 56 | 23 | 2 | 2 | 3 | 0 | 1 | 4 | 59 | 1837 | 138 | 7 |
| freight_yard-SURVIVE-16 | Completed | Victory | 6 | 11.7 | 89 | 0 | 43 | 20 | 11 | 4 | 7 | 0 | 0 | 2 | 57 | 3017 | 150 | 22 |
| freight_yard-SURVIVE-17 | Completed | Victory | 6 | 11.3 | 82 | 0 | 45 | 16 | 6 | 10 | 2 | 0 | 0 | 2 | 54 | 2366 | 130 | 18 |
| service_depot-ELIMINATE-16 | Completed | Victory | 7 | 8.0 | 72 | 0 | 35 | 24 | 3 | 4 | 3 | 0 | 2 | 3 | 42 | 1406 | 58 | 2 |
| service_depot-ELIMINATE-17 | Completed | Victory | 8 | 8.7 | 69 | 0 | 31 | 15 | 14 | 6 | 1 | 0 | 5 | 3 | 51 | 2100 | 95 | 11 |
| service_depot-ENEMY_EVACUATION-16 | Completed | Victory | 8 | 13.6 | 87 | 0 | 49 | 16 | 11 | 6 | 2 | 0 | 1 | 4 | 66 | 3395 | 136 | 27 |
| service_depot-ENEMY_EVACUATION-17 | Completed | Defeat | 3 | 6.9 | 46 | 0 | 35 | 8 | 0 | 2 | 0 | 0 | 1 | 3 | 37 | 1307 | 96 | 5 |
| service_depot-EXTRACT-16 | Completed | Victory | 5 | 13.3 | 76 | 0 | 52 | 11 | 4 | 3 | 3 | 0 | 1 | 5 | 61 | 2394 | 89 | 20 |
| service_depot-EXTRACT-17 | Completed | Victory | 4 | 10.1 | 65 | 0 | 56 | 2 | 2 | 2 | 0 | 0 | 2 | 4 | 60 | 1810 | 68 | 7 |
| service_depot-INTERACT_TERMINAL-16 | Completed | Victory | 2 | 3.6 | 20 | 0 | 20 | 0 | 0 | 0 | 0 | 0 | 1 | 2 | 20 | 631 | 79 | 1 |
| service_depot-INTERACT_TERMINAL-17 | Completed | Victory | 3 | 6.2 | 38 | 0 | 35 | 2 | 0 | 1 | 0 | 0 | 1 | 3 | 36 | 1194 | 64 | 5 |
| service_depot-PROTECT-16 | Completed | Victory | 10 | 19.8 | 148 | 0 | 69 | 18 | 27 | 27 | 4 | 0 | 2 | 6 | 88 | 5226 | 238 | 31 |
| service_depot-PROTECT-17 | Completed | Victory | 10 | 13.9 | 152 | 0 | 57 | 43 | 22 | 14 | 9 | 0 | 2 | 9 | 68 | 2540 | 98 | 15 |
| service_depot-REACH-16 | Completed | Victory | 2 | 3.4 | 21 | 0 | 21 | 0 | 0 | 0 | 0 | 0 | 1 | 2 | 21 | 542 | 49 | 0 |
| service_depot-REACH-17 | Completed | Victory | 2 | 3.7 | 23 | 0 | 23 | 0 | 0 | 0 | 0 | 0 | 1 | 2 | 23 | 602 | 36 | 0 |
| service_depot-RESCUE-16 | Completed | Defeat | 7 | 14.9 | 100 | 0 | 63 | 18 | 5 | 4 | 1 | 0 | 1 | 3 | 69 | 2791 | 100 | 19 |
| service_depot-RESCUE-17 | Completed | Victory | 6 | 14.0 | 102 | 0 | 69 | 7 | 8 | 7 | 0 | 0 | 2 | 3 | 77 | 2990 | 134 | 23 |
| service_depot-SURVIVE-16 | Completed | Victory | 7 | 17.8 | 94 | 0 | 52 | 16 | 13 | 6 | 4 | 0 | 0 | 2 | 70 | 2876 | 110 | 23 |
| service_depot-SURVIVE-17 | Completed | Victory | 6 | 10.8 | 83 | 0 | 47 | 13 | 6 | 10 | 3 | 0 | 0 | 2 | 54 | 1929 | 120 | 11 |

Most common Wait reasons across the matrix: "No legal shot or reachable approach" (102), "No legal shot or safe second advance" (76), "VIP has no useful follow movement" (45), "No useful objective advance or supporting shot" (about 80 in several wordings), "No useful escort move or legal shot" (20). These are legitimate holds in the cases inspected, not loops, but Protect carries the most waits (about 20 per match).

## Findings

1. **Extract reports Victory when the whole squad is wiped out before anyone extracts (rules bug, not AI).** `freight_yard-EXTRACT-16`, `freight_yard-EXTRACT-17` and `fleet_station-EXTRACT-16` end `Victory` with every player dead, zero Extract actions and the extract objective at 0/0. Cause: `ObjectiveManager` shrinks `total_units` when a unit dies (`objective_manager.gd:386`), so with none extracted `extracted_units >= total_units` becomes `0 >= 0` (`objective_manager.gd:461`). This makes the baseline's win rate look better than it is. **Fixed 2026-11-18 (#39):** Victory now needs at least one unit or VIP actually extracted. The three matches above rerun as Defeat; `fleet_station-EXTRACT-17`, a genuine win, is unchanged. Regression: `tests/squad_loss_outcome_test.gd`.
2. **Rescue can end in Defeat after the rescue succeeded.** 3 of 6 Rescue runs end Defeat with the rescue objective complete and `extract_rescue` not. In `service_depot-RESCUE-16` and `fleet_station-RESCUE-17` the last player unit extracts alone while the rescued ally is still on the field, which empties the squad and loses the mission. `freight_yard-RESCUE-16` is a plain tactical loss. Needs a decision on whether an escort should be allowed to leave first. **Resolved 2026-11-18 (#40):** the real cause was a carrier's death stranding the VIP; it now drops and the Rescue objective reopens. See [mission outcome fixes](mission-outcomes-2026-11-18.md).
3. **Enemy Evacuation seed 17 is lost in 3 rounds on all three sites; seed 16 is won on all three.** The enemies reach the exit almost untouched (players land 8-10 attacks but stop only one enemy). This looks like zone placement or pacing, and it deserves a look before step 9 tunes escorts and carriers. **Investigated 2026-11-18 (#41):** not a placement bug (players are about twice as close to the exit); a pacing/AI question for steps 9-10. See [mission outcome fixes](mission-outcomes-2026-11-18.md).
4. **Planning slices are long enough to matter.** See the planning figures above; these feed the existing planning-performance issue.
5. **No oscillation, deadlock or stall appeared in this matrix.** That is evidence about these 48 setups only: three-on-three, Normal difficulty, two seeds, and `move_returns` only detects immediate A-B-A reversals.

## Limits of this baseline

- One squad size, one difficulty, default commanders, seeds 16/17 only. Larger squads, other difficulties, Cautious/Aggressive commanders and carrier-heavy cases are not covered.
- Planning time covers movement planning only, measured in headless runs at 12x time scale; presentation is still running (it is compressed, not removed).
- F3 evidence for individual decisions has not been collected here; the decision records in the JSON carry the same explanations F3 shows.
- No human playtest. These numbers show the AI is legal and finishes; they do not show it plays well.
