# Milestone 04, step 1 — Current combat audit

Step 1 complete: [current rules](../combat-current-rules.md), traced consumers, reproducible evidence and ranked findings. Audited production code at `2bbc7b1`; existing texture-import edits were left untouched. No gameplay, map content, balance or production implementation was changed. This audit adds documentation and an explicit diagnostic tool.

## What is already consistent

Player hover and action availability use `BattleController.query_attack()` and the action service's target inventory. `AIController._find_attack_target()` consumes that same inventory; AI attacks call the same `try_attack()`/`submit_attack()` path. Execution recomputes the evaluation and validates the action window/resources/revision before drawing RNG or spending resources. Raw geometry helpers intentionally do not include all action permission checks.

Guard movement reactions use `evaluate_attack_at_cell()` with the checkpoint and −15 modifier. Retaliation uses `evaluate_attack()` after the incoming attack has resolved. Both use the same body-sampling and Shield calculation, with their documented reaction-specific eligibility/costs. They are not ordinary attacks requiring another AP expenditure.

Repeated direct/inventory queries preserved combat RNG, revision and AP in the diagnostic. Its normal clear-shot commit matched the predicted 100% and dealt 25 damage. Existing action/reaction tests also passed. No direct UI-versus-AI normal-shot legality disagreement was found in the shared inventory path; that does not establish correctness of every supporting consumer.

## Ranked findings

| Rank | Finding and classification | Evidence / consequence | Follow-up |
| --- | --- | --- | --- |
| **1 — High** | **Range/Guard overlays and AI destination firing heuristics disagree with actual shot geometry. Reproduced inconsistency.** | A raised target is a legal 50% shot and produces a 35% Guard checkpoint reaction, but its tile is absent from the painted range and AI firing score is 0. Conversely, a nearby low barrier blocks all five samples while the painted range includes the destination and AI assigns a firing score of 10. | Steps 4/9: align these consumers with the existing attack evaluation appropriate to their context. Preserve the already-shared direct shot inventory. |
| **2 — Medium** | **The highlighted blocker need not be the nearest obstruction. Reproduced diagnostic defect.** | Shooting from X=9 toward X=1 with full walls at X=7 and X=3 reports X=3. Geometry candidates are traversed by cell/order, not sorted by ray intersection distance. Both walls block, so legality is correct while the explanation points past the first wall. | Steps 4/9: report the actual nearest relevant intersection and its protecting geometry. |
| **3 — Medium** | **Incoming destination evaluation retains Shield that Move cancels. Reproduced post-state mismatch.** | Before a legal move, `evaluate_attack_at_cell()` gives the enemy 80% and ×0.35 damage protection. After committing that move, Shield is off and the same incoming attack is 100% / ×1.0. | Steps 8/9: evaluate the intended post-move defensive state. Keep during-route reaction ordering an explicit decision. Current move text shows line/cover, not the numerical 80% or multiplier, so this is not a claim that those wrong numbers are currently displayed. The text also mentions Aim cancellation but omits Shield cancellation. |
| **4 — Design decision** | **Cover is a coarse directional label, and half/full have the same accuracy penalty. Existing prototype contract.** | Holding geometry fixed while switching LOW/FULL gives a legal 50% shot in both cases, even with all five samples clear. One covered neighboring cell changes chance from 100% to 50% at the dominant-axis diagonal boundary. | Steps 2/5: decide intended half/full protection, flanking, face/contact requirements and exposure interaction before changing tests or numbers. The label-only probe is synthetic; full-height geometry can independently make a real full-cover shot illegal. |
| **5 — Compatibility decision before balancing** | **Recorded `simulation_version` is not enforced by recording-header validation. Source-confirmed and header-probed gap.** | A document tagged `audit-unknown-combat-rules` passes `is_playable()` header checks. Later replay action/state comparisons still detect divergence; this is not evidence that incompatible combat silently replays successfully. | Step 7: define rejection/compatibility for intentional rules changes before tuning. Preserve existing historical rule flags and result verification. |
| **6 — Design decision** | **There is no explicit continuous height-advantage modifier. Existing prototype limit.** | Clear level and elevated shots both return 100%; source confirms height currently enters range/geometry, not an accuracy bonus. That capped example alone would not prove absence of a bonus; the formula establishes it. | Steps 2/6: define actual-height advantage and its interaction with cover/range. |

The geometry-model limitations remain relevant: ordinary mesh-derived boundaries are boxes per visible mesh part, and cover uses stamped cell labels. This audit does not establish a fresh truck/building mesh defect from screenshots; visual alignment needs the controlled asset examples planned for step 3. No destructible-cover path was found in the audited tactical action/geometry code; its bounded investigation remains step 10.

## Exact diagnostic setups

`tools/quality/combat_current_audit.gd` launches an isolated seed-1604 Depot battle, then replaces only its in-memory map with a controlled 12 × 12 empty grid. Tile size and elevation step are explicitly 1; attack range is 20. Existing actors, query/commit service, scorers and feedback functions are exercised. It does not save or register content, open a live editor, or create another runtime generator.

| Case | Fixed setup | Observed result |
| --- | --- | --- |
| Raised head visible | Shooter `(1,0,5)`, target `(9,2,5)`, wall `(5,0,5)` height 2.0. | One of five samples visible; normal 50%, inventory agrees, Guard checkpoint 35%; range omits tile, AI position firing score 0. |
| Low barrier close to shooter | Shooter `(1,0,5)`, target `(9,0,5)`, low barrier `(2,0,5)` height 1.15, not flagged as a full LOS blocker. | All samples blocked; normal attack rejects; range includes tile, AI firing score 10. The single-line helper excludes low cover from its candidate set. |
| Cover labels | Shooter `(1,0,5)`, target `(6,0,5)`, adjacent obstacle `(5,0,5)` height 0.2; switch only LOW/FULL label. | Both legal 50%, visibility 1.0. This isolates the formula from geometry classification. |
| Direction boundary | Target `(6,0,6)`, cover `(6,0,5)`; shooter `(1,0,2)`, `(1,0,1)`, `(2,0,1)`. | Chance 100%, 50%, 50%; the exact tie checks both axes. |
| Blocker order | Shooter `(9,0,5)`, target `(1,0,5)`, height-3 walls `(7,0,5)` and `(3,0,5)`. | Reports `(3,0,5)` despite `(7,0,5)` being nearer. |
| Shield destination | Shooter/player `(2,0,5)`, hostile `(7,0,5)`; commit Shield then Move to `(2,0,6)`. | Move is legal. Hypothetical incoming calculation retains protection; actual completed destination has none. |

Guard evidence above calls the real checkpoint resolver on a prepared reaction/path fixture; it is not a claim of an end-to-end AI movement playthrough. Shield evidence commits actual Shield and Move actions. The header probe uses a synthetic diagnostic recording only for header acceptance; no full playback of that mutated-map recording is attempted.

Reproduce twice:

```powershell
godot_console --headless --path . --script res://tools/quality/combat_current_audit.gd -- artifacts/combat04-audit-evidence.json
godot_console --headless --path . --script res://tools/quality/combat_current_audit.gd -- artifacts/combat04-audit-evidence-repeat.json
```

The final two independent runs produced **identical JSON for all 10 observations**, with zero fixture failures. The [checked-in evidence](combat-audit-evidence-2026-11-15.json) preserves those values. This tool observes today's behavior; it is outside automatic regression discovery and does not prescribe future combat rules.

## Verification and limits

- Fresh combat subsystem: **25 passed, 0 failed, 1 skipped** (explicit-only map-quality diagnostic). Logs: `artifacts/test-results/20261115-234112-subsystem-combat`.
- Fresh focused AI-position, AI-target, tactical-decision-feedback and replay-schema checks: **four passed, zero failures**. Logs: `artifacts/combat04-ai-position.txt`, `combat04-ai-target.txt`, `combat04-feedback.txt`, `combat04-replay-schema.txt`.
- Final diagnostic/repeat logs contain no script/parse errors or resource-leak warnings. The combat subsystem retains the previously observed allied-faction test exit warning (four ObjectDB instances / one resource). Certificate/user-log diagnostics remain environmental; none was presented as fixed.
- Early diagnostic setup had inconsistent grid scale and incomplete deferred teardown; both were corrected before final evidence. The elevated-wall placement was refined to isolate head visibility correctly. These were diagnostic-fixture issues, not game defects or altered production behavior.
- No full suite, new complete-battle/replay matrix, rendered usability review, arbitrary asset-alignment audit or broad hit-rate statistical experiment was performed. Headless facts do not establish visual readability, and passing existing tests does not invalidate the reproduced consumer discrepancies.

Next is **step 2: define FuseFire's intended rules**, including half/full cover, flanking, exposure, height, reliability and compatibility choices. XCOM comparison belongs there; no external design claims were needed for this current-code audit.
