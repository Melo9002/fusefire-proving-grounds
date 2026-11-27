# Milestone 06.03B — Integrated traversal verification

## Baseline and disposition

Integrated main was `b6c1f5c044589b8dcb329303247146517b55b47c`, the merge of PR #103. Its first-parent history includes #99 through #102. Verification used a clean review checkout on `codex/traversal-verification-0603b`, separate from the owner's modified checkout. Production files and the ordinary test catalog have no changes in this review. The additions are this report, a diagnostic companion to the existing tests, and rendered evidence.

| Step | Recommendation |
| --- | --- |
| **06.03 — Route, cost and occupancy** | **Verified existing** for representative ground, diagonal, partial-cell, vertical and vault fixtures. Accept the shared tactical contract exercised here. |
| **06.05 — Stairs and ramps** | **Verified existing, tactical scope.** Accept the authored Range stair and ramp transitions, including their current carrier behavior. Stair contact and animation polish remain open. |
| **06.06 — Ladders** | **Verified existing, tactical scope.** Accept the regular ladder route, costs, occupancy, reaction boundary, AI route and replay evidence. Keep #64 and the loaded-ladder policy decision open. |
| **06.07 — Low obstacles and vault** | **Verified existing** for the current automatic low-barrier traversal family. The transit tile cannot be selected as a stop and the standard Move handles either direction. |

These recommendations apply to the exercised contracts and authored geometry. They leave general traversal presentation, unsupported variants and the rest of Milestone 06 open.

## Evidence and authority

The prior [movement audit](movement-06-step01-audit.md) and [architecture](movement-06-step01-architecture.md) describe the shared grid and continuous geometry boundary. [06.02](movement-06-step02-support-placement.md) covers recovered supported placement, compiled signatures and the corresponding deck route. [06.04](movement-06-step04-readability.md) covers Depot selection, rejection and the pinned upper-floor ghost. [06.10A](movement-06-step10a-passenger-release.md) covers Rescue ownership and replay at a lethal movement checkpoint, including fallback and historical recordings. The animation findings below use the existing [animation reference](../animation.md), [ADDA backlog](../claude/animation-backlog.md) and [Ironclad procedure](project-ironclad.md).

The compiler provides canonical standing points and authored traversal links. [MapGraphBuilder](../../systems/grid/map_graph_builder.gd) creates the graph with static swept clearance. [Pathfinder](../../systems/grid/pathfinder.gd) supplies weighted reachability and checks live body occupancy on edges. The [battle controller](../../systems/battle_controller.gd) supplies the same Move query to the inventory and destination preview. The [AI controller](../../units/ai_controller.gd) reads that inventory, scores options and submits ordinary Move. The [action service](../../systems/actions/runtime/tactical_action_service.gd) revalidates the current route before expenditure, resolves ordered reactions, then settles occupancy and publishes one receipt. The presenter consumes that result. Recorded standing points belong to logical checkpoints, while the renderer can add continuous waypoints for stairs, ramp lips, ladder transfers and vaults.

## Traversal matrix

| Contract | Evidence at this baseline | Boundary |
| --- | --- | --- |
| Cardinal, diagonal and narrow ground routes | Ordinary diagonal, route builder, action service and movement readability coverage. The Range refinement scan sampled 120 legal routes, 62 smoothed, with zero mismatches. Minimum sampled clearance was 0.500 m against a 0.320 m requirement. | A valid destination depends on the connecting route and current occupancy. |
| Partial-cell stops and multi-floor selection | Reused 06.02 deck and 06.04 hover evidence. Re-ran the ordinary surface battle/replay, floor-selection and industrial roof tests. Saved partial-cell playback verifies the quantized points and final transform. | Sampled authored sites. No new standing-point census. |
| Stairs | Range `(6,0,15) ↔ (6,3,12)`, three links, weight 3 either direction. A west approach from `(5,0,15)` turns at the lower landing and weighs 4. Preview, receipt, AP, occupancy and canonical arrival agree. The stair gameplay and alignment tests cover feet, entry and exit geometry, both directions and rig cleanup. | Tested ordinary armed tactical MIRA. Bench evidence below adds Small MIRA and the original unarmed entry reproduction. |
| Ramps | Range `(11,0,15) ↔ (11,3,12)`, weight 3. Alignment verifies both directions against the physical 45° surface and one step at the deck lip. | The geometric result does not certify independent foot contact for the gait. |
| Ladders | Range `(12,0,4) ↔ (12,3,5)`, one authored link of weight 1, both directions. The running rig test verifies facing, rifle stow/restoration and cleanup. An occupied top landing invalidates a previously legal request without expenditure, receipt, RNG or occupancy mutation. | #64 descent intersections persist. The tactical link has only its two endpoints, so Guard has no separate mid-rung rule. The forced visual interruption test exercises cleanup, not a new mid-rung tactical reaction. |
| Low obstacles | Range `(21,0,9) ↔ (21,0,11)` crosses `(21,0,10)`, weight 3. Canonical airborne checkpoint, forward/reverse landing and the overhead-blocked control are covered. Ordinary vault and vertical navigation tests exercise geometry. | A traversable obstacle is an invalid stop. Support clearance and overhead clearance are separate checks. |
| Live occupancy and route updates | The top-landing control checks exact rejection before submission. Adding a live enemy at `(21,0,9)` blocks a previously legal weight-4 route from `(21,0,8)` to `(21,0,11)`. The refreshed query returns no route within budget and submission is read-only. | The narrow corridor is a controlled derivative of the Range. The obstacle and its authored vault edge are unchanged. |
| AI ladder and vault | The existing AI planner received a route goal and selected and committed its own Move. It descended the authored ladder and crossed the vault in reverse. Receipts matched the shared targeted query, AP and live occupancy. The vault fixture disables side routes so flanking does not dominate. | This validates route evaluation and execution. It does not measure how often an autonomous squad chooses either traversal on open maps. |
| Carrier traversal | Existing loaded-carrier test passed all 12 checks. Stair and ramp routes complete, the VIP stays attached and the rifle stays stowed. Loaded stair presentation uses carry gait without stair feet. The current loaded ladder completes in about 0.8 s with no ladder contacts or leg IK. | Tactical legality is established. Whether to keep that legality and what physical presentation to require remain owner decisions. |
| Reactions and scene lifetime | Guard and Rescue suites passed. The vault control forces a nonlethal hit on checkpoint index 1, then a lethal hit at the same checkpoint. The survivor reaches the landing. The lethal receipt truncates to the airborne tile and leaves no occupied origin, checkpoint, requested landing or busy action. Stair and ladder rig cancellation and the AI scene lifetime suite cover cleanup. | Reaction opportunities occur on logical Move checkpoints after the origin. Decorative animation points add no reaction windows. Supported vault checks here use an unloaded actor. |
| Replay | The ordinary traversal replay determinism test compares action records, fingerprints, AP and destinations with presentation on and off. The new probe round-trips one up/down ladder recording and one forward/reverse vault recording through JSON and actual playback. Each verifies 2/2 actions and the final cell. | The probe reapplies its controlled initial placement before playback, as the carrier fixture does. It does not create a replay that can be launched standalone without that preparation. |

Each selected regular Move in the probe spent one AP. Weight is measured separately against a movement budget of five. The diagnostic uses a direct shot-seed control to force the tested Guard hits, without changing hit rules or reaction order. Its corridor graph rebuild restores the live-grid binding that normal battle initialization sets. Before restoring that binding, the fixture erroneously allowed a route through the injected occupant. That result came from diagnostic setup and was discarded.

## Presentation and historical issues

- **#52, steep risers and gait.** The Range's real 0.5 m risers and the sampled planner pass the tactical and contact assertions. The planner still pulls the swing foot inward by up to 84 mm ascending and 115 mm descending in the steep test, and uses each tread at speed on this geometry. The 60 fps unarmed bench and armed tactical capture cover different entry states. They do not establish a matched armed/unarmed mesh comparison or eliminate transient toe/riser clipping. [Issue #52](https://github.com/Melo9002/fusefire-proving-grounds/issues/52)
- **#65, first planted foot.** The existing ADDA-related tread probe reproduced 214.0 mm of travel against the tread for regular MIRA and 218.4 mm for Small MIRA in the first unarmed workbench stance. The turned tactical ascent checked the actual lower transition and arrival, with no matched quantitative first-stance measurement on the tactical rig. Keep the entry presentation issue open. [Issue #65](https://github.com/Melo9002/fusefire-proving-grounds/issues/65)
- **#69, lateral stair behavior.** The turned tactical route tests a direction change at the landing. Existing stance/contact tests exercise lateral placement, and the bench covered both rigs during forward ascent. Neither reproduces walking sideways on a stair or measures Small MIRA lateral drift in the specific reported span. Both concerns remain open. [Issue #69](https://github.com/Melo9002/fusefire-proving-grounds/issues/69)
- **#64, descent geometry.** The unmodified ladder landing script failed for three regular-MIRA descent cases on this run. Armed posts measured 121.6 mm, unarmed posts 117.1 mm, and unarmed rails 115.2 mm in the approximate limb-volume checks. Armed rails was also reported on previous runs. The independent mesh-clearance test passed its own thresholds. These are separate measurements. The 30 fps grip check did not fail in this run. Keep the descent issue open and its assertions intact. [Issue #64](https://github.com/Melo9002/fusefire-proving-grounds/issues/64)

## Rendered evidence

The authored Tactical Test Range ran with the normal tactical scene and Compatibility renderer at 1280×720 on Godot 4.7.2 and an RTX 5060. The existing capture sets camera and starting cells, then executes real Moves at normal speed. All four recorded actions arrived. The vault capture uses a real camera ray through the viewport to obtain its landing. Its probe calls the same hover handler and game action after scripted placement. This is automated rendered inspection. Prior 06.04 footage and the re-run floor tests cover the upper-floor picker. No human playthrough or alternate-renderer check was performed here.

The frames show feet following the stair profile, the actor riding the ramp, and the stowed rifle during ladder transfer. The vault reads as a raised step with the rifle held, and its arrival lands on the previewed side. Contact quality and mesh penetration require the separate measurements described above.

[Stair ascent](evidence/movement-06/images/0603b-stairs-up.png) · [Ramp descent](evidence/movement-06/images/0603b-ramp-down.png) · [Ladder top transfer](evidence/movement-06/images/0603b-ladder-top.png) · [Ladder descent](evidence/movement-06/images/0603b-ladder-down.png)

[Vault preview](evidence/movement-06/images/0603b-vault-preview.png) · [Crossing](evidence/movement-06/images/0603b-vault-crossing.png) · [Arrival](evidence/movement-06/images/0603b-vault-arrival.png)

## Ironclad and reproduction

Catalog validation passed with 311 scripts. Run `20261127-172920256-5e416fed-select` passed import and reported 28 passes and one inherited ladder failure. Supplement `20261127-173652590-617dd84d-select` passed all five checks. Across both selections, 34 distinct scripts ran with zero timeouts and zero selected scripts omitted. The other 240 ordinary scripts and 37 explicit-only scripts were outside the matrix. There was no full suite run. The rendered companion probe passed all 71 checks. Plans, runner PIDs, completion records, raw stdout/stderr and result JSON were saved under `artifacts/0603b`.

| Inherited inventory | Status |
| --- | --- |
| `ladder_landing_test` | Reproduced on exact integrated main during this assignment. |
| `camera_environment_apertures_test`, `reusable_occupant_test` | Inherited shared camera geometry and asset extraction parity failures from the 06.04 exact-main controls. Outside this selection. |
| `generation_retirement_test`, `tactical_archetype_lab_test` | Previously reproduced obsolete expectations for the default Depot variant and four setup tabs. Assertions remain outstanding. |
| `core_objectives_smoke` | Intermittent incapacitated VIP pose assertion. Exact main failed in the 06.04 control. Its review branch passed that run. Outside this selection. |

```powershell
.\tools\run_tests.ps1 check
$tests = 'movement_readability_test,tactical_action_service_test,diagonal_movement_test,tactical_route_builder_test,surface_navigation_test,surface_vertical_traversal_test,traversal_path_gameplay_test,traversal_stair_gameplay_test,traversal_surface_alignment_test,traversal_stair_feet_test,stair_contact_test,traversal_timing_contract_test,traversal_ladder_gameplay_test,ladder_climb_test,ladder_interrupt_test,ladder_landing_test,ladder_mesh_clearance_test,traversal_loaded_carrier_test,surface_vault_test,vault_smoke,elevation_selection_smoke,ai_movement_profile_test,ai_hard_constraints_test,overwatch_reactions_test,reactive_passenger_release_test,rescue_carrier_loss_test,traversal_replay_determinism_test,surface_battle_replay_test,rescue_battle_replay_smoke'
.\tools\run_tests.ps1 select -Test ($tests -split ',') -Import -TimeoutSeconds 180 -LogDirectory artifacts/0603b/ironclad
.\tools\run_tests.ps1 select -Test traversal_classification_test,traversal_stair_gait_test,ai_scene_lifetime_test,presentation_authority_test,industrial_roof_movement_test -TimeoutSeconds 180 -LogDirectory artifacts/0603b/supplement
$probe = 'res://docs/quality/evidence/movement-06'
$out = Join-Path (Get-Location) 'artifacts/0603b'
godot_console --headless --path . --script "$probe/traversal_acceptance_probe.gd"
godot_console --path . --rendering-method gl_compatibility --resolution 1280x720 --script "$probe/rendered_traversal_probe.gd" -- "$out/render"
godot_console --path . --rendering-method gl_compatibility --resolution 1280x720 --script "$probe/traversal_acceptance_probe.gd" -- "$out/vault"
foreach ($rig in 'mira_0','small_mira_0') {
    godot_console --headless --fixed-fps 60 --path . --script res://tools/quality/stair_tread_probe.gd -- $rig 5
}
```

## Open owner decisions

Decide whether loaded ladder traversal remains legal and what would constitute acceptable presentation. Decide whether the descent intersections block visual approval. Keep the issue-specific stair entry and lateral reproduction for animation review. This work supplies no approval for new interaction mechanics or for the open 06.10 presentation timing.
