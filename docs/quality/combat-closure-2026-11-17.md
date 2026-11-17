# Milestone 04 — final combat validation, 2026-11-17

**Milestone 04 is validated for the current prototype scope.** Final ordinary full run: **159 pass / 0 fail / 14 policy skips**, exit zero, 1,435.73 seconds (23 minutes 56 seconds). No unexplained UI/AI/query/commit or replay divergence was observed in the checked contexts. The remaining engine-investigation and polish limits below are explicit; this is not a declaration of final balance or complete coverage of every asset, mission and machine. The [reliability decision](../combat-reliability.md) retains the provisional numbers; this delivery adds checks and makes the test runner honest about script errors, without retuning the balance scalars. It also fixes a demonstrated endpoint defect in guaranteed shots.

## Scope and ownership

Combat legality, costs and resolution remain in CombatRules and TacticalActionService. Player feedback and AI target scoring consume the same attack query. Destination previews evaluate the proposed supported point, cancel the stances that Move cancels, and distinguish normal outgoing/incoming fire from a Guard opportunity along the route. Presentation and holograms do not create another tactical actor or consume combat RNG.

The milestone now has controlled examples and rules for physical directional cover, partial exposure, flanking, compound geometry, nearest blockers, corners, actual height and 3D range, Aim, Shield and Guard. The existing editable Tactical Test Range is selectable without duplicating its scene. Ordinary asset placement and the supported-point foundation are preserved.

No destruction feature, critical hits, new animation framework or new map-generation system was added. Step 10 deliberately defers destruction; step 11 deliberately retains the current settings. Detailed rule history stays in the linked reports instead of being merged into the everyday editor guide.

## What changed in this final batch

- Added a repeatable reliability check using real attack commits and Guard retaliation, plus a bounded measurement command. It measures fixed conditions without altering tuning.
- Added six current-site query checks: Depot, Freight Yard and Fleet Station, seeds 16/17. They use real generated geometry, supported points and the actual AI target scorer.
- Expanded complete current-content playthrough/save/replay coverage from two site/seed cases to all six. Existing completion, movement/shooting, content-manifest, every-action, result and combat-log assertions are retained.
- Added repeatable shot, target-inventory and destination-option timing, with state/RNG purity checks.
- Added real-site shot/move capture mode and reviewed the interface at 1440 × 900. Camera occlusion updates remain active in captures even though camera movement is frozen.
- Fixed Ironclad’s false PASS after an unhandled script error with exit zero. The explicit diagnostic now includes both a nonzero exit and a zero-exit script-error probe. It rejects both without treating ordinary expected application-level negative tests as script failures.

One production edge-case correction makes a 100% shot succeed even when the random roll equals 100. [Godot documents randf() as inclusive of 1.0](https://docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html#class-randomnumbergenerator-method-randf), so the former strict comparison could violate the guarantee. The exact-boundary regression failed before the fix. Direct fire and both Guard paths share this hit check; each still consumes its usual draw. The formula, scalars, action costs, damage rules, AI doctrine, map content and replay schema are otherwise unchanged.

Simulation identity is now **`prototype-1.5-guaranteed-hit-11`**. Earlier identities reject explicitly. The already-running first broad run was stopped after finding this edge case so a fresh broad run could validate the final shared helper and replay identity together.

## Reliability decision

[The measurement report](combat-reliability-2026-11-17.md) records **17 conditions × 2,048 trials**, all final measurement processes exiting zero. Close exposed and flanking shots are genuinely guaranteed. Cover and steep range falloff introduce risk; Aim recovers 35 percentage points without adding damage. Ordinary hits remain 25 and misses zero. The measured hit rates agree with predictions and exact deterministic rolls.

Aim affects only the next shot. With 3 AP, Aim → Attack → Attack gives one boosted and one ordinary shot; it is not automatically superior to three ordinary shots. With a target needing one hit and 2 AP left, Aim can improve the chance of finishing while saving ammo. A genuine 95% shot can still miss; the interface says so honestly.

Shield is the main balance watchpoint. Close frontal fire is 80%/9 damage on hit, versus 100%/25 unprotected. Its fixed 120° arc, expiry and Attack/Reload restrictions give it a cost, but stationary trials cannot establish whether that protection feels right in a whole battle. Keep it provisional rather than pretending that an expected-damage table settles enjoyment or difficulty.

## Current-site agreement and replay

The six-case query test finds a genuinely supported, unoccupied firing cell in each generated site. This relocation is test setup, not a player teleport feature. It then compares HUD/direct queries, target inventories, proposed-origin evaluation, actual AI candidate chance and committed shot chance/damage. It checks that repeated queries and destination options leave state and RNG unchanged.

Normal, blocked, partial, cover, elevated, Shield and Guard contexts also have their focused tests in the broad run. The current-site probe is not claimed to exhaust every obstacle or body pose. Complete battle replays check saved content identity, every recorded action, final result and regenerated combat log; merely reopening a replay is not counted as fidelity validation.

| Site | Seed | Result | Round | Saved actions verified |
| --- | --- | --- | --- | --- |
| service depot | 16 | victory | 4 | 45/45 |
| service depot | 17 | defeat | 6 | 62/62 |
| freight yard | 16 | victory | 5 | 52/52 |
| freight yard | 17 | victory | 3 | 35/35 |
| fleet station | 16 | victory | 12 | 100/100 |
| fleet station | 17 | victory | 3 | 35/35 |

All six complete battles and saved playbacks passed under simulation 11: **329 actions verified**. The seed-17 Depot defeat is an expected recorded outcome, not a test failure. These are two-versus-two Eliminate matches; no claim of balanced win rate or complete coverage of other missions is made.

The broader current-mission matrix additionally passed **48 initialization/Aim-replay cases** (three sites × two seeds × eight mission presets), including tactical placement and fixed-scenery reconstruction. Each replays one committed Aim action; it is not 48 completed AI missions.

## Query performance

Measured on an **AMD Ryzen 5 5500**, Windows, Godot 4.7.2. Graphics captures use D3D12 Forward+ on an NVIDIA GeForce RTX 5060. Each measurement uses eight warmups and 128 read-only samples. Shot is a direct target query; inventory evaluates the current target list; destination options evaluate normal incoming and outgoing fire against both enemies after a proposed move. This excludes path search, rendering and the whole AI planning turn.

Initial p95 observations across the six site/seed fixtures were 0.287–0.959 ms for direct shots, 0.403–1.093 ms for inventories and 0.506–3.402 ms for destination options. These were development-machine observations under concurrent validation, not hardware-independent guarantees. The final headless rerun below had no other Godot validation process running; all 80 functional/purity checks passed and the process exited zero. For this two-enemy prototype, a practical review budget is p95 below 2 ms for direct shots, 3 ms for inventory and 8 ms for destination options. These are review targets, not timing assertions that fail on slower collaborators’ machines.

| Site / seed | Direct shot p95 | Target inventory p95 | Destination options p95 | Worst sample across these three |
| --- | --- | --- | --- | --- |
| service depot / 16 | 0.273 ms | 0.381 ms | 1.010 ms | 1.110 ms |
| service depot / 17 | 0.319 ms | 0.414 ms | 0.488 ms | 0.616 ms |
| freight yard / 16 | 0.527 ms | 0.642 ms | 1.974 ms | 2.058 ms |
| freight yard / 17 | 0.380 ms | 0.495 ms | 0.641 ms | 0.680 ms |
| fleet station / 16 | 0.949 ms | 1.072 ms | 3.277 ms | 3.554 ms |
| fleet station / 17 | 0.287 ms | 0.402 ms | 0.484 ms | 0.538 ms |

All measured p95 values meet those review targets. The worst individual sample is retained in the table instead of being hidden by an average. These fixtures use the current two-enemy roster and legal firing contexts; larger rosters, longer-range weapons and path search need separate measurement.

Do not interpret these measurements as a fix for whole AI-turn stalls. Path search, candidate counts, animation waits and larger squads still need the separate profiling work in [#4](https://github.com/Melo9002/fusefire-proving-grounds/issues/4).

## Rendered feedback

Capture mode generates shot and move views for all six site/seed cases. The final graphics run passed **92 checks**, including 12 saved site/seed captures, and exited zero. Shot/move views were inspected at 1440 × 900. Representative tracked evidence: [Depot shot](images/combat-closure/service_depot-16-shot.png), [Freight destination](images/combat-closure/freight_yard-16-move.png), [Fleet destination](images/combat-closure/fleet_station-16-move.png).

The original fixed Fleet seed-16 audit angle obscured the selected actor behind the warehouse. The capture harness now chooses a clear ordinary orbit using the existing camera obstruction query; the original obstructed image remains in local artifacts. This makes UI inspection possible without claiming that every player camera angle is obstruction-free. No production camera behavior was changed; the existing camera follow-ups remain open. Review checks readable hit chance and damage, costs and remaining resources, honest chance words/colors, the translucent destination character, blue route, outgoing lines from the destination and explanations for unavailable targets. The capture harness uses existing camera occlusion; the deliberately frozen audit view is kept distinct from ordinary camera behavior.

A separate current-version decision-preview graphics run passed **58 checks** and saved five inspected controls/preview captures. It includes the optional confirmation and large Cancel control: [move review](images/combat-closure/move-confirmation.png).

This is visual inspection of controlled captures, not a manual mouse-driven playthrough or verification at every display resolution. The projected character uses the same animation adapter as the real unit. Shader appearance and final authored/procedural cover-pose fitting remain separate polish.

## Failures and limits

The new reliability fixture exposed a native Godot shutdown access violation. Early runs printed zero assertion failures but exited with 0xC0000005; they are failures. Process pacing, deferred teardown and splitting processes alone did not solve it. The corrected fixture has a real floor reference and resolves standing points directly instead of constructing an unused temporary navigation graph. Its focused reruns and complete isolated measurement pass with identical outcomes. A temporary-graph-only probe did not independently reproduce the fault, so engine-level cause is unconfirmed. [#33](https://github.com/Melo9002/fusefire-proving-grounds/issues/33) retains the investigation. This is not a blanket gameplay crash fix.

The initial real-site check also had a defective AI-controller lookup and an incorrect visualizer call signature. Both were corrected in the new test; a completeness assertion now requires all six cases to reach the final checks, and the runner rejects script errors rather than trusting passing text alone.

The existing root-certificate-store error is an environment diagnostic, recorded separately from combat failures. The sandboxed headless import also cannot save the editor settings file under AppData; project import/parser checks still exit zero. These are recorded environment limitations, not silently described as clean engine logs. The first completed broad run reported **158 pass / 1 fail / 14 policy skips**. The gallery-picking failure was an obsolete expectation from before the owner-approved visible-ascent UX fix: inspecting Ground does not make a still-visible upper deck unclickable. The test now positively checks visible-deck selection and explicitly cycles to legal ground beneath it, while preserving hidden-deck, blocked-ground and real upper-movement assertions. The focused gallery test passes, as does the 15-check visible-ascent regression. No gameplay picker behavior was reverted to satisfy the old test.

Verbose log review also identified two unowned UnitStats Nodes in the allied extraction test. Their leaked script/native-class references accounted for four ObjectDB leak warnings. Attaching those stats as children of the fixture’s units fixes ownership; the verbose focused rerun passes without the leak diagnostics. This is a test-fixture fix, not a claim of a project-wide production memory-leak repair. A fresh broad run passed after both corrections; no valid assertions are weakened, deleted or skipped.

Remaining explicit limits: provisional balance and human pacing feedback; rounded/concave mesh approximations and particular asset openings; no new tactical corner-peeking origin or destruction; camera ownership/unselected-unit visibility follow-ups; larger-squad AI profiling; exported Windows/collaborator-machine validation; local-parcel replay portability. The complete Eliminate matrix is not claimed as complete rescue/survival/objective-driven AI coverage.

## Final verification ledger

| Check | Actual result |
| --- | --- |
| Ordinary Ironclad full | **159 passed / 0 failed / 14 policy skips**, exit 0, 1,435.73s |
| Exact roll endpoints / old simulation rejection | **9 checks, 0 failures**; endpoint regression reproduced one failure before the fix |
| Seeded reliability | **17 × 2,048 outcomes**, inventory plus all condition processes exit 0 |
| Current-site queries / AI / commits / purity | **80 checks, 0 failures**, six site/seed cases |
| Current-site rendered feedback | **92 checks, 0 failures**, 12 captures, exit 0 |
| Decision-preview rendered controls | **58 checks, 0 failures**, five captures, exit 0 |
| Complete current-site battle/file replay | **6 matches, 329/329 actions**, matching results and recent combat logs |
| Current mission initialization/Aim replay | **48 cases, 0 failures** |
| Runner negative diagnostic | **11 ordinary passes + 2 intentional failures**, exit 1 as required |
| Corrected gallery / visible ascent | Both focused checks pass; visible ascent **15 checks / 0 failures** |
| Allied fixture ownership | Focused verbose rerun passes without the earlier ObjectDB/resource leaks |

The short decision-preview graphics run overlapped the early part of the final broad run. Its functional results are recorded separately; broad-run duration is not an isolated performance benchmark. The final quiet query measurement was run after the broad and graphics processes exited.

The runner now checks both stdout/stderr and the engine log for script errors. After the full pass, the engine-log channel was made explicit in the runner as well; every completed full-run engine log was independently checked against that stricter condition, and the smoke/negative diagnostic was rerun. No gameplay or test assertions changed after the full pass.

Final full logs: `artifacts/test-results/20261117-150453-full/`; first completed diagnostic full: `artifacts/test-results/20261117-143756-full/`. The first run remains 158/1/14 in its original logs. Fresh full verification follows the contract/lifetime corrections; its totals are not assembled from selected reruns.

All fourteen exclusions are the existing explicit-only policy: extended AI/stress/generation metrics and specialized asset/editor/render capture workflows. No exclusion or ordinary test assertion was removed to achieve the result. The separate graphics checks above supplement the full tier; they do not turn its policy skip count into zero.

Final log review found no script/parser failures or ObjectDB/resource leak warnings. Remaining non-certificate engine diagnostics are the sandboxed editor-settings save restriction and deliberate initialization rejections in stale-content/retirement/loading/replay negative tests. Those rejection cases are expected and assert safe failure. No claim of an environment-error-free run or clean exported-build verification is made.

## Reproduce and owner review

```powershell
./tools/run_tests.ps1 full
./tools/run_tests.ps1 smoke -ProbeFailureHandling
./tools/measure_combat_reliability.ps1
godot_console --headless --path . --script res://tests/combat_real_map_closure_test.gd
godot_console --path . --script res://tests/combat_real_map_closure_test.gd -- artifacts/combat-closure-review
godot_console --path . --script res://tests/combat_decision_preview_test.gd -- capture artifacts/decision-closure-review
```

For ordinary quick checking, `./tools/run_tests.ps1 smoke` takes about 50 seconds on this machine; a broad full pass takes about 24 minutes.

The failure-probe command intentionally returns nonzero with two diagnostic failures. The ordinary full command must not include those probes. Large statistical measurements retain every seed/assertion while running one condition per process. Raw logs and images live under ignored `artifacts/`; the tracked report records the conclusions and key counts.

For a quick human pass, use the selectable Tactical Test Range and one normal site. Compare a close exposed shot, a covered shot, a flank and an elevated shot. Compare Aim with firing immediately, and check Shield/Guard from the enemy’s direction. Hover a move, inspect incoming/outgoing predictions, enable movement confirmation if desired, then cancel once before committing. Save and watch the battle replay. Send the GFL2 reference when convenient for later UI comparison; it is not a prerequisite for these checks.
