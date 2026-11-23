# Task 14 sign-off corrections — 2026-11-23

Implementation baseline: `d69eb11353eb6b54600a3db6a463cb1f731b1818` on **main**, including Claude's ladder improvements. Historical audit baseline `5034527`, its worktree, and its local diagnostic evidence are preserved. The independent audit and original Task 14 report are not rewritten. Issue [#59](https://github.com/Melo9002/fusefire-proving-grounds/issues/59) remains open for owner sign-off.

## Root causes and corrections

| Finding | Correction | Classification |
|---|---|---|
| F1: catalog assumed an empty local `content/` directory existed in Git | Remove that obsolete area entry. No tracked content or current runtime/tool reference uses that tree. Keep STALE/UNMAPPED validation unchanged. | Invariant: reproducible catalog and usable CI |
| F2: attack replacement overwrote live work at cancellation limit; shot callback resumed after cancellation | At exhaustion, refuse the outer request with both handles SKIPPED and preserve the live operation. Snapshot operation identity around host callbacks; stop if it was interrupted/replaced. Detach old state before cleanup and handle notifications. | Invariant: no orphan handles or stale timeline continuation |
| F3: completion observers escaped reaction replacement or teardown | Close admission before teardown callbacks, cancel owned work, and make teardown idempotent. Apply the same guarantees to neutral reactions and the humanoid bridge's delegated reaction. A completion callback that tears down a family prevents the remaining visual frame. | Invariant: terminal cleanup |
| F4: equality test masked refused movement and sampled AP before reset | Six independent, explicitly prepared flat/ramp/stair-up/stair-down/ladder-up/ladder-down scenarios. Require arrival, exact queried AP cost and observed stair/ladder frames at 1x and observed 4x. No repair teleport after refusal. | Invariant: successful authoritative traversal independent of presentation |
| F5: acos-based quaternion comparison amplified near-unit rounding | Compare relative rotation with `2*atan2(length(xyz),abs(w))`. Preserve 0.0001 m and 0.001 rad thresholds. Add zero-change/small-change/position controls and require compared final samples to come from the same engine frame. | Invariant equality; contract thresholds |
| F6: diagnostics gate matched driving calls but missed property writes | Add a bounded text pattern for direct/compound/indexed writes through known rig/presenter/skeleton receiver names. Keep legitimate reads and diagnostics' own snapshot writes. | Invariant observational diagnostics; bounded textual protection |

## Lifecycle decisions

An outer replacement already in progress has precedence over work started by its interruption callbacks, preserving the established ordinary behavior. Both old handles settle before replacement takes ownership. After the existing cancellation budget is exhausted, the outer request is explicitly SKIPPED; it never overwrites a live nested request. Ordinary completion observers may request subsequent work when no teardown or cleanup hook owns the transition.

Host cleanup hooks cannot start new work (SKIPPED). A removed presenter/family refuses supported one-shots (CANCELLED); unsupported family actions keep their existing SKIPPED result and explanation. Terminal teardown sets the guard before notifying observers, so cross-action callbacks cannot restart attacks or holds. A fresh lifetime requires a fresh presenter. ActionHandle's settle-once semantics and gameplay rules are unchanged.

No generic lifecycle framework was introduced. These checks remain in the existing owners: AttackSequence, CharacterPresenter and MotionPresenter. The humanoid motion bridge cancels only its own still-pending delegated reaction; it does not tear down an independently owned character.

## Files

Production: `presentation/characters/presenter/attack_sequence.gd`, `character_presenter.gd`, `humanoid_motion_bridge.gd`, and `presentation/motion/motion_presenter.gd`.

Tests: new `tests/presentation_reentry_test.gd`, `tests/pose_comparison_test.gd`, `tests/support/pose_comparison.gd`; updated `presentation_authority_test.gd`, `pose_ownership_test.gd`, `animation_module_boundaries_test.gd`, and `tests/catalog.json` (plus generated UIDs for the three new scripts).

Documentation: this report, the canonical animation guide link, and an explicit measurement caveat in `tools/quality/animation_perf_baseline.gd`. The benchmark algorithm and animation hot paths are not optimized. No approved pose/route reference, ladder geometry, movement rule, damage rule or replay schema is changed.

## Regression evidence

The new lifecycle and numerical tests were executed **before** repair. Import passed; both tests failed for the intended original defects (including the real tactical visual's null shot-handle script error and identical-pose angle 0.001381068). A refined teardown check was also run red to ensure it observes the first teardown, rather than hiding escaped work with a second cleanup.

The lifecycle test covers finite nested callbacks, cancellation exhaustion, both attack handles, reaction replacement, immediate cross-action teardown, repeated teardown, delegated bridge cleanup, completion-triggered removal, and a real shot-state observer requesting a hit.

The authority test retains AP/record/cell tamper controls. Its normal run includes a real AP-starved stair request checked by the same leg validator. The explicit command `godot_console --headless --path . --script res://tests/presentation_authority_test.gd -- --refuse-traversal` fails for refused stairs, wrong destination/cost and absent stair frames. It no longer reports success just because both configurations refused the same actions.

A virtual-source diagnostic control inserts `rig.aim_blend = 1.0` into the monitor's scanned source: the strengthened gate reports that exact write and exits unsuccessfully. No production file is modified by the control.

Catalog controls copy the tracked source/checker files into a fresh source-only projection without local empty directories (Godot resource loading is unnecessary for `check`). Clean validation passes; an injected stale area and an unmapped source each exit 2; restored validation passes. The checker itself is unchanged. The preserved helper is local `agent-comms/signoff_catalog_controls.py`.

Iteration failures were investigated rather than hidden: a mixed-indentation parser error was corrected; an existing unsupported-action assertion caught a precedence change, so the implementation was corrected to preserve SKIPPED for unsupported actions; redundant fixture placement on an already occupied own cell was removed after its application ERROR appeared in a nominal PASS log. No assertion was loosened to obtain green output.

## Verification

Final selections, elapsed costs and repository state are recorded below after execution. No full tier is permitted or executed. Individual failures of deliberate controls are expected evidence, not green production verification. The runner rejects zero-exit script/parser errors.

## Limits and deferred work

The historical five-stage shin intermittence is **not declared solved**. A deterministic numerical false-positive is fixed and same-frame sample comparison is now checked, but this does not establish the cause of every historical failure. Keep the ownership assertions and declared bone roles intact; do not broaden ownership, increase tolerances, or skip the test.

The diagnostics gate is a textual tripwire, not alias analysis or a parser. Renamed aliases, dynamic calls/setters and arbitrary data flow can bypass its protection. Current known direct writes and driving calls are checked; runtime observation tests complement it.

F7 remains deferred: 240 manual benchmark calls within one engine frame skip frame-guarded work. Existing figures are comparative idle microbenchmarks, not complete real-frame costs. Historical duration/cost-aware selection, broader flaky-test handling, benchmark redesign, and trace artifact retention belong to the separate Ironclad campaign.

No fresh rendered/playthrough verdict or exact historical pose/route JSON equality is claimed. The original audit images/evidence are preserved. Hosted CI cannot verify these unpushed corrections yet. Final owner sign-off should wait for the corrected commit's hosted check + smoke result; issue #59 is not closed by this implementation.

## Executed results and costs

| Selection / control | Result | Elapsed |
|---|---|---|
| Initial permanent lifecycle + pose tests on original implementations | import PASS; two intended test FAILs | 23.70 s |
| Immediate-first-teardown regression on original implementation | expected FAIL | 3.13 s |
| Directly affected authority, pose ownership, boundaries, reentry, motion contracts | 5 PASS; subsequent log inspection found redundant fixture placement and that test setup was corrected | 49.26 s |
| Final targeted reentry, pose comparison, existing combat lifecycle, gesture, rescue handles, authority, traversal replay and replay file workflow | **8 PASS, 0 FAIL** | **130.13 s** |
| Explicit final exhaustion-outcome check | 1 PASS | 3.12 s |
| Existing 25-member smoke selection + fresh import | **26 PASS, 0 FAIL** | **93.79 s** |
| Two cheap regressions, verified after adding them to final SMOKE membership | **2 PASS, 0 FAIL** | **3.30 s** |
| Final catalog and clean source-only projection | PASS; 285 scripts, 35 explicit-only, 104 FAST, 27 SMOKE | checks about 1 s each; four-control helper about 4 s total |
| Inject stale area / unmapped source | expected nonzero exit 2 in each case; restored projection PASS | included above |
| Inject observed-state assignment into scanned diagnostic | expected FAIL, exact property write reported | about 1 s |
| Deliberately refuse stair traversals via CLI | expected FAIL (7 assertions), not a green test | about 15 s |

The final 27-member smoke set is covered by the 25-member tier run plus the two named regressions. It was **not** redundantly rerun as one 28-process invocation after changing only those membership flags. Hosted CI will execute all 27 scripts plus import together after an authorized push. The complete named outputs live in ignored `artifacts/test-results/20261123-003758-select`, `20261123-004112-smoke`, and `20261123-004425-select`; pose ownership evidence is in `20261123-003331-select`. Negative-control engine logs are `artifacts/task14-boundary-control.engine.log` and `artifacts/task14-refused-traversal.engine.log`.

The final authority run completes every normal and observed leg, spends the queried AP, and observes stair/ladder presentation. Its log has no redundant-placement ERROR. Pose ownership passes with its original bone declarations and thresholds plus six final-sample synchronization checks. No approved trace was regenerated or silently updated.

Warnings were classified: `gesture_capability_test` still reports 19 leaked ObjectDB instances / 6 resources at shutdown, matching several pre-change logs including `20261122-191239-full` and `20261122-225236-full`. This known warning is not silently represented as a new clean-shutdown result. Replay-file workflow intentionally rejects a stale plot manifest; its assertion checks `STALE_PLOT_REVISION`. Smoke's current-generation test also deliberately rejects invalid content. A project-import warning about the temporary source-only projection's nested `project.godot` was harmless; that owned projection marker was removed after validation so it is not retained as another editor project. No new script/parser error remains in final verification.

No full suite was run. The other ordinary tests, explicit-only captures/stress batches and a human playtest remain unverified by this task.

## Review disposition

All reproduced local findings F1–F6 have bounded corrections and focused verification. There is no currently reproduced material local blocker from this assignment. The work is ready for review on main; no branch, PR, merge or push is required to inspect it. **Formal milestone sign-off remains the owner's decision and should wait for the corrected commit's hosted catalog + smoke result.** The historical shin intermittence remains explicitly unresolved rather than being declared fixed by inference.

Deferred: F7/performance instrumentation, historical test-duration management and proportional quality gates; visual stair/ladder/finger/ragdoll work; broad interactive playtesting. Those are separate tasks. Original audit worktree/evidence and other agents' worktrees are preserved. Existing Kenney/SVG import changes are excluded from the implementation commit.
