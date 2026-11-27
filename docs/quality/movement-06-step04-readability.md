# Milestone 06.04 — Movement readability and preview consistency

## Baseline and reproduction

Integrated main was `6841acd0fa538816d372cd096e1ec1393a348309`, the merge of PR #102. It includes the movement audit, current combat defaults, checkpoint-aware passenger release and support-aware placement from PRs #99 through #101. Work took place in a separate review branch and checkout.

The [06.01 preview probe](evidence/movement-06/preview_probe.gd) reproduced the original Service Depot seed-16 case on this baseline. Alpha started at `(25, 0, 6)`. A nearby legal stop at `(26, 0, 6)` produced the existing Move preview. The upright tank center at `(30, 0, 8)` returned `unreachable` and blank hover and click text. The new ordinary regression produced three failing assertions on main and confirmed no state or RNG mutation. The corrected build shows **Cannot stand here.** for both hover and click.

## Authority and rejection order

[MouseRaycaster](../../systems/grid/mouse_raycaster.gd) still chooses among the same visible, stoppable floors. It also keeps the first visible rejected upward face from the existing collision scan for diagnostics. This face is used only when the ordinary picker has no selected floor. Its click leads to feedback only. A filtered side face, hidden collider or empty ray does not fabricate a movement target. Unit-selection and layer-cycling behavior keep their existing priority.

[TacticalActionService](../../systems/actions/runtime/tactical_action_service.gd) still validates battle state, actor, activation and AP first. [BattleController](../../systems/battle_controller.gd) then checks the static target and live occupancy before spending work on reachability:

| Evidence | Code and display |
| --- | --- |
| Cell is absent or is already the actor's cell | `invalid_destination` or `already_there`. “No destination here.” or “Already here.” |
| Cell is traversable and rejects stops | `transit_only`. “Cannot stop here.” |
| Non-stoppable terrain, absent support, or insufficient room around the standing point | `cannot_stand` or `unsupported`. “Cannot stand here.” Both can apply in a partially supported tile. The message stays generic when the standing flags cannot identify the precise geometric cause. |
| Another actor owns the destination | `occupied`. Names the actor only when its scene node is visible. Hidden occupancy uses the same generic standing rejection as geometry. |
| A live-clear graph route exceeds the budget | `beyond_movement_range`. “Beyond movement range.” The bounded Dijkstra scan records checked edges just beyond its existing expansion limit. It expands no extra nodes. A target also reached within budget stays eligible for the ordinary path query. |
| Known absence of a route | `path_unavailable`. “No available route.” This can come from an absent graph point, an exhausted reachable component, or a failed targeted path search. |
| No route demonstrated inside the budget | `unreachable`. “No route within movement range.” This includes cases where more distant connectivity is unknown. |

The existing move inventory, path selection, weighted cost, canonical XYZ, occupancy checks, and presentation route remain the ones used for commits. Click and confirmation obtain a fresh shared query. Confirm checks revision and actor identity, then revalidates occupancy even if the revision has not advanced. The action service performs its own commit-time enforcement as before. Invalid previews never submit an action.

## Feedback lifecycle

One existing tactical HUD label owns both successful Move previews and short rejection messages. The current hover query is reused for the same actor, cell, AP, speed, action revision and occupancy revision. The latter is an internal cache invalidator updated by grid register, unregister and relocation APIs. It has no effect on the action revision, fingerprint or replay. The range refreshes on those same board changes. Confirm uses a fresh query regardless of the hover cache.

Rejection clears the pinned target, the drawn path, destination shot lines and preview options. It hides and suspends the same hologram rig so sweeping across a blocked tile does not rebuild the rig on every transition. Cancel, selection and floor changes release the preview. A pinned valid destination retains its contextual inspection. Explicit floor changes unpin it and clear the text. Valid movement retains the existing ghost, AP, cover, Guard and contextual firing readouts. Feedback uses no modal or combat-log entry for a routine rejection.

## Rendered verification

The [ordinary regression](../../tests/movement_readability_test.gd) starts real authored battles and uses the production camera, collision picker and HUD. The capture mode projects the tank and legal stop from the camera into the viewport. It injects a real press/release pair through the viewport for the rejected tank click. The hover captures feed real ray hits into the production hover handler immediately before drawing. The fixture places the actor and frames the view for reproducibility. This is controlled automated input rather than a manual playthrough.

The tank capture shows the rejection with the Move range retained and no ghost or path to the tank. The valid Depot capture retains the pinned-arrival readout. On the Tactical Test Range, the Control Gallery level-3 stair landing still gets its own canonical ghost and path. The floor selector clears the previous pin. Dedicated layered tests cover ordinary Alt-wheel cycling, ground below an upper platform, hidden overlap, the roof, and authored stair/ramp geometry. Confirmation, repaint after occupancy changes, cancellation, reselection and the next successful Move are covered by the focused regression.

[Depot tank rejection](evidence/movement-06/images/readability-01-depot-tank.jpg) · [Pinned Depot move](evidence/movement-06/images/readability-02-depot-pinned.jpg) · [Pinned upper landing](evidence/movement-06/images/readability-03-range-stairs.jpg)

## Timing

The [timing probe](evidence/movement-06/readability_timing.gd) ran the same 3v3 configurations on exact integrated main and the corrected checkout, serially with Godot 4.7.2 Stable. Each row is median/P95 in microseconds from 128 samples after eight warmups. The measurements start after the floor hit. They measure synchronous controller and query work, with no claim about physics-ray time or rendered frame intervals.

| Workload | Depot seed 16, before → after | Test Range seed 1, before → after |
| --- | --- | --- |
| Same valid hover | 2251/3281 → 11/15 | 3705/4126 → 7/7 |
| Same rejected hover | 4/5 → 5/6 | 4/5 → 5/6 |
| Alternate valid and rejected hover | 19660/20578 → 2941/3672 | 21149/22507 → 4416/5088 |
| Fresh valid targeted query | 2172/2375 → 2201/2448 | 3609/4379 → 3641/3996 |
| Fresh invalid query | 2091/2414 → 18/19 | 3439/4011 → 18/28 |

The invalid Depot target is known non-stoppable terrain. The invalid Range target is an absent upper-layer cell. The old repeated invalid hover silently cleared the label. The new one displays a reason. The alternating workload includes reapplying the valid preview. Before suspending the hidden rig, it still cost about 19–21 ms median. These samples show the benefit of reuse on this host. They do not guarantee a frame budget on other systems.

## Reproduction

```powershell
.\tools\run_tests.ps1 check
.\tools\run_tests.ps1 select -Test movement_readability_test,tactical_action_service_test,combat_decision_preview_test,elevation_selection_smoke,visible_elevation_picking_test -Import
$out = Join-Path (Get-Location) 'artifacts/0604/readability-capture'
godot_console --path . --rendering-method gl_compatibility --resolution 1280x720 --script tests/movement_readability_test.gd -- capture $out
godot_console --headless --path . --script docs/quality/evidence/movement-06/readability_timing.gd
```

For the timing comparison, run the same probe against an imported checkout at the baseline revision. Baseline reproduction logs, timing logs, running-command metadata, controls and Ironclad result JSON are under `artifacts/0604` in the review checkout.

## Verification results

The production change is recorded at `75371f2d3bdcfb347116078e71846a28151d60c6`. Catalog validation passed with 311 entries. The 29-test Ironclad selection passed import validation and returned 24 passes and five failures, with no timeouts or unexecuted selections. The rendered movement regression also passed in Compatibility mode. The selection included the new feedback regression, route and occupancy checks, layered picking, tactical HUD and firing previews, AI clearance reuse, Guard, reactive passenger release, contextual firing and traversal replay determinism.

All six controls from the preceding full run were executed against an archive of exact integrated main. The review branch reproduced five. Their assertions were left intact.

| Test | Integrated main → review branch | Finding |
| --- | --- | --- |
| `camera_environment_apertures_test` | Fail → fail | Contextual Firing Bay misses a shared environment camera-aperture geometry assertion. |
| `core_objectives_smoke` | Fail → pass | Previously isolated as an intermittent Rescue presentation failure involving incapacitated pose readiness. One branch pass does not resolve it. |
| `generation_retirement_test` | Fail → fail | The compact Depot default assertion predates the contextual battlefield variant selected by the current defaults. |
| `ladder_landing_test` | Fail → fail | Same four descent intersections for regular MIRA in armed and unarmed posts and rails transfers, tracked under #64. |
| `reusable_occupant_test` | Fail → fail | Same four extracted-asset parity failures for the loading-yard variants and delivery object. |
| `tactical_archetype_lab_test` | Fail → fail | The four-tab assertion predates the added Combat tab. |

The selected run ID is `20261127-170803038-556bfacc-select`. Its machine-readable results, command and completion record are under `artifacts/0604`. Another 245 ordinary tests were outside this selection and 37 tests remain explicit-only. No full suite rerun was performed for 06.04.

## Remaining scope

Feedback applies to the floor the existing picker returns. Ambiguous distant connectivity keeps the bounded generic explanation. No new camera, pointer, traversal, Guard or contextual firing rule is needed. The tests provide targeted 06.03 evidence for preview, cost and occupancy. After this review, use the existing traversal fixtures to continue verification of stair, ramp and ladder cases separately.
