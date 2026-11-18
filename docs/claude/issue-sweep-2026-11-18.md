# Issue sweep — 2026-11-18

A pass over the open GitHub issues that were small and well-scoped enough to settle with evidence. Mission outcome bugs (#39, #40, #41) are written up in [mission outcome fixes](mission-outcomes-2026-11-18.md).

| Issue | Result | Evidence |
| --- | --- | --- |
| #2 camera apertures | **Fixed.** `TacticalCamera` now updates and restores only the apertures inside its own battle (`_owned_apertures`). An unrelated aperture mid-transition went from 0.75 to 0.00 before; it now keeps its state. | `tests/battle_dependency_isolation_test.gd` (new aperture case, failed first). The existing aperture, obstruction, readability, compact-battlefield and roof checks pass. |
| #3 simulation diagnostics | **Already fixed** by the 2026-11-17 repair batch (`classify_stop`: a terminal result wins over every limit, with an empty reason). Closed after confirming against the code. | `tests/ai_simulation_classification_test.gd`. |
| #21 contributor quick start | **Mostly current already.** The README lists the three sites and the range, the Godot version, controls and test commands. Fixed the two stale CI statements in the Ironclad guide: CI runs the smoke tier on pushes to `main` (recent runs passed; pull-request runs not checked). Left open for you to close or widen. | `docs/quality/project-ironclad.md`; GitHub run list. |
| #31 Shield replay identity | **Done.** Recordings store `shield_capability_signature` for the archetypes in the battle (when Shield is enabled) and playback refuses a mismatch before any action. Old recordings are unaffected. | `tests/replay_shield_identity_test.gd` (33 checks); [replay](../replay.md). |
| #44 AI on legacy flat maps | **Could not reproduce.** The fixture's flat map, open ground, hostile 21 cells away: the unit advances. Filed while the scenario fixture still ran a second background activation. Closed; scenario S6c guards it. | `tests/ai_decision_scenarios_test.gd` (S6c). |

## Suites after these changes

Replay 18, combat 40, AI 32, UI 26, movement 24, assets 9 passed, 0 failed. Missions was last run (17) after the carrier change and is unaffected by these.

## Not taken

Left alone as design questions or larger work: #7, #8, #9, #10, #11, #12, #17, #18, #20, #22, #32. #33 (a native Godot shutdown crash) needs the original fixture and was not investigated. #16 (squad card names) is small UI polish that needs a look at the art direction first. #4 and #5 belong to milestone 05 step 11 and step 12.
