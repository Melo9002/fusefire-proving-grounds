# Combat prediction and feedback corrections

The three reproduced inconsistencies from the [combat audit](combat-audit-2026-11-15.md) are corrected. This does not change the accuracy formula, cover penalties, damage, Aim bonus or during-route Shield/Guard rules. AI movement choices can change because their visibility information is now correct.

## Changes

1. **Attack/Guard coverage and AI movement use the actual shot samples.** `CombatRules.has_firing_lane_to_cell()` shares the normal five-point body visibility calculation. Occupied cells use their actual body's height; empty cells assume a hostile with the shooter's height. The controller uses this for painted coverage. AI destination scoring and its separate safe-second-advance gate use the shared incoming/outgoing shot evaluations. Their existing scoring weights remain unchanged. Geometric coverage still does not grant AP, supply or permission to attack friendly actors.
2. **Blocker selection follows intersection distance.** The existing segment/bounds test now also supplies entry distance, allowing selection of the nearest blocking cell rather than the first cell traversed. Compound parts and existing diagonal-seam rules are retained; equal-distance diagnostics use a stable coordinate tie-break. The actual blocker marker consumes this result. This does not replace tactical bounds with render-mesh collision.
3. **Completed destinations exclude canceled Shield.** `evaluate_attack_after_move()` is a pure use of the existing checkpoint evaluation with target Shield disabled. Movement feedback and AI destination evaluation use it; the text now explains Shield cancellation. The real movement reaction resolver still uses `evaluate_attack_at_cell()`, retaining current Shield during path checkpoints before the existing Move cleanup. Previewing never clears live stance.

Boolean coverage stops at the first clear body sample. Once an attack evaluation has its first blocked sample's nearest blocker, later samples only need a blocked/clear answer. This avoids repeatedly calculating unused diagnostic detail while preserving the full visibility fraction and current accuracy calculation.

## Reproductions and controls

The new `combat_prediction_consistency_test.gd` initially reported **eight failures** before the production fixes. It now passes, including:

- A raised target with one visible sample remains a legal **50%** shot / **35%** Guard reaction. Painted coverage includes it and AI recognizes a firing opportunity.
- A nearby low barrier that blocks every sample is excluded from coverage and receives no AI firing reward. The reversed incoming case receives no false exposure score, including the safe-advance gate.
- A shorter actual target is evaluated using its own body height.
- Two walls report the nearer wall in either firing direction, including compound parts. The feedback marker uses that result. Reordering diagonal seam candidates does not change the reported tie or open/closed-corner behavior.
- Incoming Shield prediction at a completed destination is **100%, no Shield, ×1 damage**, matching an actual committed Move. A during-route checkpoint remains **80%, Shield active**, preserving current semantics. Prediction leaves the authoritative state fingerprint unchanged.

The [before/after evidence](combat-consistency-evidence-2026-11-16.json) preserves exact observations. Cover-label, direction-boundary and clear-height examples, plus the ordinary attack's chance/damage/RNG roll, match the baseline. The original dated audit/evidence remain historical; the diagnostic tool now reports current corrected behavior.

## Verification

| Check | Result |
| --- | --- |
| Focused prediction regression and diagonal seam check | Passed |
| Combat subsystem | 26 passed, 0 failed, 1 explicit-only diagnostic skipped |
| UI subsystem | 25 passed, 0 failed, 1 explicit-only capture skipped |
| Replay subsystem | 15 passed, 0 failed, 0 skipped |
| AI subsystem, final rerun | 22 passed, 0 failed, 1 explicit-only simulation skipped |
| Focused cover, Shield, Guard and warehouse roof/slab checks | Passed |
| Final safe-second-advance and stalemate recovery checks | Passed |
| Final current-content playthrough | Freight 86/86 actions to victory; Fleet 47/47 to defeat; both replays verified |
| Rendered tactical feedback check | Passed; normal Depot move/shot captures inspected |

The initial AI subsystem run had **21 passes, one failure and one skip**. Its sole failure was a test assuming Match Setup completes loading within 0.2 seconds. The test now waits for the explicit battle-ready scene transition and asserts loading appears; every selected difficulty/commander assertion remains. Its focused rerun and the final full AI subsystem rerun passed. This was a defective timing assumption, not an AI attack-legality failure.

Combat/UI/replay broad runs were supplemented by focused checks after the boolean-query optimization and final safe-advance/diagnostic adjustments. No full-suite run was performed. The existing allied-faction smoke retains its four-ObjectDB-instance/one-resource exit warning; certificate/user-log diagnostics remain environmental. Final focused/rendered logs had no script/parse or leak errors. Headless success alone does not establish visual correctness, and the normal HUD captures are not a manual playthrough of every synthetic geometry case.

On the development machine, three final headless coverage builds per seed-16 site took approximately **11.1–11.4 ms Depot, 19.4–20.5 ms Freight, 14.9–15.3 ms Fleet**. These are event-driven coverage rebuilds, not per-frame timings or a portable performance gate. They are a bounded spot check, not a full AI-turn performance benchmark. Evidence: `artifacts/combat04-cost-final.txt`.

Main logs: `artifacts/combat04-fix-combat.txt`, `combat04-fix-ui.txt`, `combat04-fix-ai-final.txt`, `combat04-fix-replay.txt`, `combat04-regression-before.txt`, `combat04-regression-after.txt`, `combat04-fix-before.json`, `combat04-fix-after.json`. Rendered captures: `artifacts/tactical-decision-feedback.png`, `artifacts/tactical-shot-feedback.png`.

```powershell
godot_console --headless --path . --script res://tests/combat_prediction_consistency_test.gd
godot_console --headless --path . --script res://tests/diagonal_combat_test.gd
godot_console --headless --path . --script res://tools/quality/combat_current_audit.gd -- artifacts/combat-current-evidence.json
godot_console --path . --script res://tests/tactical_decision_feedback_hud_test.gd -- capture
```

## Future tuning direction

The owner's requested direction is recorded in the [milestone plan](../combat-2-plan.md): high-ground bonuses, low-ground penalties, range falloff that begins gently then steepens sharply, and a substantially stronger Aim/ability contribution. Exact curves and values are intentionally still open. Implement that later with a small shared editable tuning resource and explainable modifiers; establish replay rule-version handling before intentional balance changes. No such balancing changes were included here.
