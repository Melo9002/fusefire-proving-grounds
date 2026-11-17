# Combat milestone 04 — step 8: defensive actions

Delivered 2026-11-17. [Everyday rules and hands-on checks](../combat-defensive-actions.md). Numeric costs/benefits remain unchanged: Aim +35 at 1 AP; Guard all remaining AP and one reaction at -15/1 SP; default Shield 1 AP, inclusive 120° front, -20 incoming accuracy and ×0.35 hit damage. Ordinary hits remain 25; accuracy never scales damage.

## Findings and corrections

1. **Guard silently skipped opportunities.** The service now exposes a read-only reaction query for readiness, hostility, SP, carrying, range and body-sample LOS. Both movement and retaliation use that query; no parallel prediction formula. Committed feedback identifies movement checkpoints or retaliation, final chance, shot/SP consumption, or the latest checked no-fire reason and whether a reaction remains reserved. A directly attacked watcher defeated before responding reports that explicitly. No message is added for every path cell or every non-triggering enemy action.
2. **Shield used integer-cell directions despite supported-position combat.** Committed facing and incoming protection now use the horizontal difference between the same supported points used by range/LOS. The arc is still inclusive and fixed after commitment, without tracking the chosen threat. An overhead threat with no horizontal bearing cannot establish a zero-direction stance or consume AP. Controlled within-cell offsets demonstrate both sides of the old grid/physical disagreement; service query, outgoing/checkpoint evaluation, Guard and a committed hit agree. Four rotated arc boundaries and actual authored stacked galleries are covered.
3. **Skip canceled Shield before the enemy turn** ([#29](https://github.com/Melo9002/fusefire-proving-grounds/issues/29)). `submit_simple(wait)` formerly cleared every stance. It now preserves Shield while spending remaining AP. Move still retains Shield for eligible route reactions and clears it at completion; Aim and other incompatible actions clear it. This is a behavior correction, not a cost or strength retune. The expanded regression reproduced **49 checks / 3 failures** before correction, then passed unchanged. A saved unmodified current-range Shield → Skip recording verifies the retained state, exact facing, spent AP and regenerated explanation.
4. **Status/tooltip gaps.** Aim states that it does not stack or add damage. Guard explains its two trigger kinds, no facing cone, no Aim bonus, legal-opportunity checks and consumption on a miss. Shield explains cost, arc, modifiers, fixed direction, action restrictions, Skip/Move behavior and expiry. Its cost/permissions follow its capability, and its status displays `SHIELD 120° FRONT`, not vector components mislabeled as degrees. An absent capability with stale Shield state gets a safe unavailable label. Aim, Shield and unused Guard expiry are reported once at the next activation; same-activation reselection does not expire or log twice.

The existing five-entry recent-combat history stays bounded. New explanations are presentation fields regenerated during replay, not random draws or additional simulation inputs. Aim/Shield activation and Aim consumption/Move cancellation also enter that log. Existing reaction events still record actual outcomes, ordering and costs.

## Replay and tuning boundary

Simulation identity is **`prototype-1.5-defense-direction-10`** because physical Shield direction and Skip retention change the rules. Prior identities reject clearly. Existing action schemas and the shared combat tuning signature remain; no new replay format or asset workflow was added. Current settings are deterministic through normal queries, execution, saved reconstruction and replay.

Shield remains a horizontal arc, with no new vertical cone, manual facing widget, Shield model/animation or tactical peeking. Guard checks existing movement checkpoints, not arbitrary continuous points between them. Fine presentation/chance colors remain step 9; overall defensive balance remains provisional.

A separate compatibility improvement is tracked as [#31](https://github.com/Melo9002/fusefire-proving-grounds/issues/31): the replay header hashes shared combat settings but not per-archetype Shield capability values. Current playback compares resolved outcomes; capability edits can produce later explicit divergence rather than an early settings rejection. Advance the simulation revision when shipping changed Shield capability semantics; this review does not claim arbitrary post-recording capability edits are portable.

## Verification

| Final evidence | Result |
| --- | --- |
| Focused defensive review | **51 checks, 0 failures** |
| Focused saved Shield/Skip replay | **8 checks, 0 failures**, verifies both exact actions and log |
| Combat subsystem | **33 pass, 0 fail, 1 explicit metrics skip**, 147.80s |
| Replay subsystem | **17 pass, 0 fail, 0 skip**, 408.52s |
| Final smoke | **11 pass, 0 fail, 0 skip**, 48.38s |
| Graphics review | **55 checks, 0 failures**, four inspected captures |

Focused coverage includes physical shifted positions, live/preview/Guard/committed agreement, rotated inclusive boundaries, a real overhead gallery target, no AP spent on invalid facing, costs and stance transitions, zero-AP reserved reactions, no-SP/range/LOS/carrying/friendly reasons, non-triggering enemy Aim, real blocked and out-of-range moves, a deliberately seeded miss consuming SP/reservation, explicit expiry, retaliation and death-before-response. No-RNG and state-purity assertions are preserved.

Final combat and replay runs include the Shield/Skip correction. Test-only additions for tooltip configurability, real stacked surfaces and the final explanation assertion were subsequently verified by the final focused and rendered runs. Saved Freight/Fleet playthrough checks now also compare regenerated recent-combat logs. The broad replay matrix, file workflow, rescue, surface and ordinary playback checks passed. No fresh full-project or full AI subsystem claim is made.

The first HUD iteration produced an actual null-capability callback error in an existing Guard fixture despite its zero assertion failures/process exit. It was diagnosed and fixed, then combat rerun. An initial feedback-script type-inference error was also corrected before broad verification. Final logs were scanned for unexpected script/parse/compile errors; none found. Existing root-certificate environment messages remain. The runner's false-PASS gap is logged separately as [#30](https://github.com/Melo9002/fusefire-proving-grounds/issues/30).

Graphics captures under `artifacts/defense-review/`: `shield-active.png`, `shield-skipped.png`, `guard-blocked.png`, `guard-miss.png`. They confirm readable stance/log feedback and the retained Shield at zero AP. The blocked fixture injects tactical obstruction to test feedback; these images do not establish visible-model boundary alignment or Shield pose quality. This is focused rendered review, not an exhaustive manual battle verdict.

Commands:

```powershell
godot_console --headless --path . --script res://tests/defensive_actions_review_test.gd
godot_console --headless --path . --script res://tests/defensive_actions_replay_test.gd
.\tools\run_tests.ps1 subsystem -Subsystem combat
.\tools\run_tests.ps1 subsystem -Subsystem replay
.\tools\run_tests.ps1 smoke
godot_console --path . --script res://tests/defensive_actions_review_test.gd -- capture artifacts/defense-review
```

Step 8 closes this review; it does not close milestone 04. Next: step 9, chance colors and presentation refinement.
