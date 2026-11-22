# Task 14: independent Codex audit brief

You are Codex, auditing FuseFire's animation architecture independently of Claude, who implemented and verified Task 14. Claude's own review does not count; yours does. Prioritise substantive architectural or correctness issues over style. Do not accept Claude's claims: check them against the code and, where you can, run focused tests.

## Rules

* Do **not** modify tracked files, commit, or push. If you need a probe, write it under `agent-comms/` (excluded from Git) and run it with `godot_console --headless --path . --script res://agent-comms/<probe>.gd`.
* Run tests serially, focused, with `.\tools\run_tests.ps1 select -Test <name>` (or `fast -Subsystem animation`). Do **not** run the `full` tier (Claude already ran it once; it takes about 10 minutes and shares `.godot/` files).
* Report each finding as: **evidence** (file:line, command and output), **severity** (blocker, material, minor), **reproducibility**, **affected contract**, **recommended disposition**. Mark what you executed and what you only read. Say "no finding" for an area you checked and found sound.
* Begin your answer with a one-line verdict: SOUND, SOUND WITH FINDINGS, or NOT SOUND.

## What to read

`docs/animation.md` (start at "The architecture at completion (Task 14)"), `docs/claude/task14-architecture-validation-2026-11-22.md` (the claims and evidence matrix), `docs/quality/project-ironclad.md`, `tests/animation_module_boundaries_test.gd`, `tests/presentation_authority_test.gd`, `tests/motion_contract_test.gd`, `tests/catalog.json`, `tools/run_tests.ps1`, `.github/workflows/ironclad-smoke.yml`, and the production code under `presentation/` and `tools/animation_workbench/`.

## What Task 14 changed (compare `0c0b8ff` with the Task 14 commit)

1. `tests/catalog.json`: areas for `presentation/motion/`, `presentation/diagnostics/`, `research/` and two root presentation files; smoke membership for six cheap architecture tests; the new `presentation_authority_test`.
2. `tools/run_tests.ps1 check`: new STALE (area path missing) and UNMAPPED (source file covered by no area) rules.
3. `tests/animation_module_boundaries_test.gd`: gates A (production never depends on `research/`), B (contract, diagnostics, families, demo, workbench never reach gameplay), C (diagnostics call no driving or writing method), D (hosts and tools never read underscore members of the rig or presenter).
4. `tests/presentation_authority_test.gd` (new): the same scripted moves at 1x and 4x engine speed with `PresentationMonitor` attached produce identical action records, fingerprints, AP and cells.
5. `presentation/characters/presenter/attack_sequence.gd`: `begin` now ends an attack that an observer started while the previous one was being interrupted (your earlier probe `agent-comms/review_attack_reentrancy.gd`); regression added to `tests/combat_presentation_lifecycle_test.gd`.
6. `presentation/characters/rig/character_rig.gd` and `presentation/tactical/tactical_character_adapter.gd`: public `cover_yaw()` and `halt_interaction()` replace two private reaches.
7. Documentation: `docs/animation.md`, `docs/quality/project-ironclad.md`, the validation report.

## Questions

1. Does the architecture match the documented ownership model? Have dependencies or behaviour escaped the boundaries (hidden clocks, private state, policy in the wrong layer)?
2. Do the new gates protect meaningful rules, and can each be defeated by a realistic regression the text patterns would miss? Are any of them vacuous or brittle?
3. Is `presentation_authority_test` a real test of "visual timing cannot change the simulation", or can it pass vacuously? What would it miss?
4. Is the `AttackSequence.begin` fix right (winner, settling, bound of 16)? Any remaining reentrancy path (`cancel` observers, `AimHold`, `RescueInteraction`, holds)?
5. Will Ironclad and CI catch realistic future regressions? Look for selection gaps (`changed`), stale or misclassified catalog entries, tests that pass without asserting, and anything the smoke tier should contain but does not.
6. Is the duplicate-frame decision (record, do not reject) sound? Is anything in the motion contract unsafe for a future family?
7. Two observations Claude recorded but did not change: the tactical unit reports route speed (about 3.5 m/s) rather than the slower stair presentation speed (about 1.0 m/s) to the locomotion feed (your probe `agent-comms/review_stair_speed.gd`), and the exploration host decides "still moving" from wall-clock time. Do you agree they should stay deferred?
8. Are the extension procedures in `docs/animation.md` practical for another developer, and are there inaccuracies?
9. Are the performance and replay claims in the report supported by what it cites?
