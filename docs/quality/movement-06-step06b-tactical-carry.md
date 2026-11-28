# Milestone 06.06B — Tactical mixed carrying and loaded ladders

## Baseline and recommendation

The integrated baseline is `2a437c8a79206c0892ff01764857db8cb22b1757`, the merge of PR #105. It includes the 06.03B traversal verification and the fixes from 06.02, 06.04 and 06.10A. The tactical adoption commit is `f10f2a2835c2a906af52f4cadae3eb98d471a1b4` and the final production revision is `4c7a039d636dd9fb52d412efb13a8a4261e05342` on `codex/tactical-carry-ladder-0606b`. The owner's working checkout was left separate.

Accept the existing logical ladder contract and this tactical adoption for both current MIRA sizes. The owner can review the timing and visual playback with the commands below. The inherited unloaded descent and pickup/release contact limitations remain tracked separately.

## Identity and ownership

[ObjectiveManager](../../systems/objectives/objective_manager.gd) still unregisters the casualty from the grid, gives the carrier ownership and updates Rescue. The original actor stays hidden and disabled while it is carried. [TacticalUnit](../../units/tactical_unit.gd) now supplies a `PassengerDefinition` from that actor's resolved rig. The shared value contains the actual model scene, character ID, scale and rig profile. This also retains instance-specific configuration without relying on a new registry or on the carrier's chassis. A pickup deferred until visual arrival keeps that definition on the receiving rig. [MovementGhost](../../presentation/overlays/movement_ghost.gd) shows the same body and invalidates its cached visual if the carried actor changes.

The rig creates a passive attachment only. It owns no turn, tactical occupancy or objective. Release clears the attachment and definition and reveals the actual casualty through the existing placement policy. Boarding and extraction still use the mission actor and existing retirement timing. For a casualty without compatible humanoid data, tactical pickup and ownership still succeed. The carrier shows a stowed weapon and carry stance, with no fabricated passenger model. A compatible body paired with a rig without loaded contacts retains the existing visual fallback.

## Loaded traversal lifecycle

The [adapter](../../presentation/tactical/tactical_character_adapter.gd) opts in only on a declared ladder with a supported rig and a live passive body. It reuses PR #105's [PassengerFit and loaded carry implementation](../claude/carry-ladder-report-2026-11-27.md). Tactical approach uses the ordinary carry. The shared clock holds translation during the transfer into back carry, then follows the already authorized path. Ascent keeps the ladder pose through the upper horizontal leg and supplies deck progress to the shared restoration blend. Descent starts restoration near the floor. Move waits for restoration before ordinary movement resumes or presentation completes. Tactical ladders still use the existing height-based pose and the authored path. No new physical landing calibration was added.

The unit's presentation estimate budgets two transfer durations per remaining ladder. The existing movement timeout remains the lifetime guard and ends traversal on a timeout. The shared presenter works from its usual delta and no fixed timer is used to release a healthy transfer. No changes to the fitting solver or combat action records were needed. PR #105 measured fitting as a cached per-pairing cost. This assignment measures action duration only and does not claim a frame-time or IK performance improvement.

## Authority, reactions and replay

The shared action service still decides AP, occupancy, route, Guard order and RNG before movement is shown. A ladder has its existing logical endpoints. None of the changed pose stages add a checkpoint. A lethally interrupted Move can already have relinquished the casualty logically before its rendered approach. The adapter therefore keeps the attached body in its carry presentation until the committed impact. The reveal uses the original actor's settled tactical placement.

The new tactical test uses the Range Rescue mission at seed 1. Controlled initial placement exposes all four pairings using the actual character visual scenes. It exercises the same Rescue and Move entry points as ordinary play, including a walking approach and continuation beyond the ladder in both directions. The occupied landing control checks rejection before revision advances. Nonlethal and lethal Guard controls put one watcher at the upper endpoint. Each checks one authorized shot and one RNG draw. The survivor continues beyond the endpoint. The lethal receipt ends at that endpoint and the original VIP is revealed there. [06.10A](movement-06-step10a-passenger-release.md) supplies legal and fallback release coverage, including the no-position and archived rules. The focused suite runs those tests again.

The AI control requests an ordinary route goal on the upper floor. The normal planner chooses and commits one Move through the same presentation barrier and can subsequently extract at the mission's authorized stop. Its goal and the placement at the extraction zone are fixture-controlled. The teardown control removes the battle during the mounting transfer and checks that the pending service and passive body have been freed.

A mixed-size control compares the Move records, fingerprints and RNG with visual Move presentation enabled and suppressed. The test also round-trips an actual Rescue and two Moves through recording JSON and production playback. The fixture reapplies both its starting cells and its injected visual rigs in playback. Normal mission actors resolve their visual from the existing scene. The replay does not record arbitrary out-of-band rig replacement such as this fixture's Small MIRA override. If configurable tactical bodies later become a Match Setup feature, their authorable selection should be retained in the existing roster/configuration contract. No cosmetic replay format change is required here.

## Rendered evidence

The normal-speed capture uses the real tactical viewport at 1280×720 with Godot 4.7.2 Compatibility and an RTX 5060. Initial positions, actions and camera angle come from the automated fixture. The capture run passed all 124 checks. It samples pickup, transfer into back carry, vertical movement, upper and lower departure with the restored shoulder carry, and release. The attached body keeps its proportions. The rifle is stowed throughout the loaded move and is available again after release. The existing HUD spends AP at commit and holds the Move controls while the longer presentation is shown. The under-deck shadow and selection silhouette obscure some hand detail. Human play and independent contact certification are outside this capture.

The Range's ladder rises 3 m. The tested leg includes one ordinary approach segment and one ordinary departure segment. The shared profile's transfer is 0.9 s in each direction, with some restoration overlapping the authorized top step or lower descent. Timings are measured from action submission to presentation completion.

| Carrier / passenger | Ascent with approach and exit | Descent with approach and exit | Mid-ascent frame |
| --- | ---: | ---: | --- |
| Regular / Regular | 5.793 s | 5.690 s | [Capture](evidence/movement-0606b/regular-regular-up.png) |
| Regular / Small | 5.777 s | 5.688 s | [Capture](evidence/movement-0606b/regular-small-up.png) |
| Small / Regular | 5.785 s | 5.692 s | [Capture](evidence/movement-0606b/small-regular-up.png) |
| Small / Small | 5.772 s | 5.689 s | [Capture](evidence/movement-0606b/small-small-up.png) |

On the authored Parking Garage ladder from `(8,0,7)` to `(8,4,8)`, a separate real-time headless probe measured a Regular / Regular carry at 6.551 s up and 6.623 s down. This is a 4 m lift with endpoint-to-endpoint Move. Its timings exclude the extra approach and exit legs in the Range runs.

[Ordinary carry after pickup](evidence/movement-0606b/small-regular-ordinary.png) · [Mount transfer](evidence/movement-0606b/regular-small-mount-transfer.png) · [Top restoration](evidence/movement-0606b/small-regular-top-restore.png) · [Descent](evidence/movement-0606b/regular-small-down.png) · [Lower carry restored](evidence/movement-0606b/regular-small-ground-after.png) · [Original actor released](evidence/movement-0606b/small-regular-release.png)

## Verification and reproduction

```powershell
.\tools\run_tests.ps1 check
.\tools\run_tests.ps1 select -Test tactical_mixed_carry_ladder_test,traversal_loaded_carrier_test,reactive_passenger_release_test,overwatch_reactions_test,rescue_battle_replay_smoke,ai_scene_lifetime_test -Import
$out = Join-Path (Get-Location) 'artifacts/0606b/tactical-capture'
godot_console --path . --rendering-method gl_compatibility --resolution 1280x720 --script tests/tactical_mixed_carry_ladder_test.gd -- capture $out
godot_console --headless --path . --script docs/quality/evidence/movement-0606b/garage_ladder_timing.gd
```

The full verification command, process metadata, per-script logs and result JSON are under `artifacts/0606b` in the review checkout. This integration gates only movement presentation and does not change general validation, action receipts or tactical simulation. The regression selection expands over that presentation surface, Rescue and shared animation contracts.

Catalog validation passed with 318 entries. Import passed. Ironclad selection `20261127-210935133-57245ded-select` ran 26 scripts with 24 passes, two failures, zero timeouts and zero selected omissions. After the lifecycle correction, its failing lifecycle test passed and the final tactical pairing test passed all 107 checks, including extraction, scene teardown, unsupported visual fallback and three verified replay actions. The inherited ladder landing diagnostic remains the only unresolved failure observed. A full ordinary rerun was outside this presentation-focused selection. Another 253 ordinary and 39 explicit-only entries were outside it.

The dependency run exposed one new regression. A passive model could keep the standalone adapter's pickup clock running after its preview flag was cleared. Carry continuity now uses the attached model only while a real tactical unit owns the adapter. The unmodified lifecycle test passes all 52 checks after the fix.

| Inherited test | Evidence |
| --- | --- |
| `ladder_landing_test` | The 06.06B selection reproduced four unloaded Regular MIRA descent intersections, 119.6–120.9 mm under #64. |
| `adapter_boundary_test` | Passed this run. PR #105 reproduced its intermittent timing failure on baseline. |
| `core_objectives_smoke` | Previous intermittent VIP incapacitated pose failure. Outside this selection. |
| `camera_environment_apertures_test`, `reusable_occupant_test` | Previously reproduced camera fixture and extracted-asset parity failures. Outside this selection. |
| `generation_retirement_test`, `tactical_archetype_lab_test` | Outstanding default-map and setup-tab assertions. Outside this selection. |

## Retained limitations

- #64 remains the inherited unloaded regular-MIRA ladder descent finding. #68 remains the pickup and release reach issue.
- PR #105's chest displacement at landing, loose passenger arm and hand poses and the near-contact toe measurement for Small carrying Regular remain applicable visual concerns. The tactical stills do not measure penetration or resolve those findings.
- No new reactions, loaded-ladder restrictions, equipment rules or interaction mechanics are part of this review.
