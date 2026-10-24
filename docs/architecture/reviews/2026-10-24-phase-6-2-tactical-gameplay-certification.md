# Phase 6.2: Generation 2.0 Tactical Gameplay Certification

## Outcome

Generation 2.0 industrial seed `17` now has permanent gameplay-level evidence, rather than initialization evidence alone. Two representative missions reach legitimate victories through the normal battle scene and authoritative action service:

- **Eliminate, 2 players versus 1 enemy:** a player moves, an invalid obstacle destination is rejected, a Wait action advances activation, and a legal guaranteed attack defeats the final enemy and completes the objective.
- **Terminal, 1 player versus 1 enemy:** the deployment has a complete tactical path to a legal terminal approach, and the normal terminal action activates the terminal and completes the mission.

The same fixture verifies deployment legality, road movement, blocked destinations, full-cover LOS blocking, directional low cover, parcel access, presentation/tactical placement agreement, and safe rejection of an unsatisfiable deployment requirement. `MapData` remains the authority for every tactical assertion.

## Integration defect corrected

Task 6.1 compiled the coherent layout document before `BattleController` selected objective zones. Deployment cells were reserved before parcel placement, but Reach, extraction, rescue, and terminal space was not. Runtime then created mission zones that were absent from the document and had never participated in the reservation ledger.

`Generation2BattlefieldBuilder` now builds the ordinary flat-map graph and calls the existing `MissionZonePlanner` before coherent assembly. The assembler therefore protects all five established objective regions from structures and optional furniture, and `BattlefieldLayoutDocument.from_generated()` preserves the exact zones and reservations. `BattleController` recognizes a complete preplanned zone set and preserves it. Legacy and authored maps without that complete set continue through the existing runtime planner.

This is a lifecycle correction at the Generation 2.0 boundary. It does not change mission scoring, pathfinding, cover, LOS, combat, objective rules, or legacy generation.

## Supported gameplay matrix

| Mission | Generation 2.0 evidence in this task | Status |
|---|---|---|
| Eliminate | Real battle scene, movement, activation progression, combat transaction, objective completion, victory | Certified representative completion |
| Terminal | Real battle scene, deployment-to-approach path, terminal query/action, objective completion, victory | Certified representative completion |
| Reach | Preserved and reserved zone; authoritative path from player deployment | Spatially validated; full mission sequence not certified here |
| Rescue | Preserved rescue spawn; authoritative path from player deployment | Spatially validated; carry/extraction sequence remains covered by existing mission suites |
| Extract | Preserved friendly extraction zone; authoritative path from player deployment | Spatially validated; full extraction sequence not certified here |
| Enemy Evacuation | Preserved enemy extraction zone; authoritative path from enemy deployment | Spatially validated; full outcome sequence not certified here |
| Protect | Uses normal legal deployments and Eliminate combat rules | Available through the shared preset; VIP outcome not replayed here |
| Survive | Uses normal deployment, combat, and round progression | Available through the shared preset; three-round completion not replayed here |

The narrower statuses are deliberate. Existing mission suites continue to protect Rescue, extraction, evacuation, survival, and VIP rules independently, but this task did not pretend that those full sequences were replayed on the Generation 2.0 map.

## Tactical and spatial evidence

The automated fixture derives evidence from the compiled seed rather than constructing a separate navigation model:

- Every spawned unit occupies a unique, walkable, stoppable cell from its faction's preserved deployment zone.
- A real `TacticalActionService.submit_move()` transaction traverses the generated road network and updates authoritative occupancy.
- A destination occupied by authored building/obstacle geometry is rejected without spending AP or advancing the state revision.
- A real full-cover cell between two legal positions blocks an attack and identifies the expected `MapCellData` blocker.
- A real low-cover cell produces directional cover and the existing accuracy penalty.
- A required parcel access region is walkable, stoppable, and reachable from player deployment.
- One certified imported building uses the same placement identity, origin, rotation, authored cell effects, and presented module node.
- Reach, rescue, friendly extraction, and enemy extraction regions have authoritative routes from their relevant deployment factions.
- The current coherent industrial grammar produces no traversal links. Elevation is therefore **not** claimed as Generation 2.0 content; existing authored/legacy vertical traversal tests remain the applicable coverage.
- Reducing the preserved player deployment to one cell while requesting two units returns `INSUFFICIENT_DEPLOYMENT` before battle activation.

## Reproducible rendered review

Run:

```powershell
godot_console --path . --resolution 1600x900 --script res://tests/generation_2_tactical_gameplay_capture.gd -- docs/architecture/reviews/evidence/generation-2-tactical-gameplay-task-6.2
```

The capture set contains:

- [normal battle view](evidence/generation-2-tactical-gameplay-task-6.2/generation-2-seed-17-normal.png), showing the active Terminal mission, imported roads, sidewalks, buildings, street furniture, and combatants without engineering overlays;
- [building frontage view](evidence/generation-2-tactical-gameplay-task-6.2/generation-2-seed-17-frontage.png), showing the inspected sealed shell and surrounding pedestrian surface; and
- [tactical overlay view](evidence/generation-2-tactical-gameplay-task-6.2/generation-2-seed-17-tactical-overlay.png), showing mission zones and authored cover edges over the same presentation.

The normal and frontage captures were visually inspected. Roads and sidewalks remain continuous in the inspected area, the sealed shell is correctly grounded, and tactical markers agree with the expected authored cells. The close view also shows a lamp near a secondary garage face. It does not occupy the shell's certified west-facing access corridor and does not contradict the tested tactical route, but broader façade-aware street-furniture composition remains a visual-quality concern rather than a certified gameplay property.

## Verification

Focused commands:

```powershell
godot_console --headless --path . --script res://tests/generation_2_tactical_gameplay_test.gd
godot_console --headless --path . --script res://tests/generation_2_battle_preset_test.gd
```

Results on Godot `4.7.2.stable`:

- Both focused Generation 2.0 scripts completed with `0 failure(s)`.
- Project Ironclad missions: `17 passed, 0 failed, 0 skipped`.
- Project Ironclad movement: `13 passed, 0 failed, 0 skipped`.
- Project Ironclad smoke: `10 passed, 0 failed, 0 skipped`.
- The selected Phase 1–5 contract sweep completed with `0 failure(s)` for geometry, visual envelopes, road streetscapes, the three certified assembly examples, layout lifecycle, mission reservations, functional parcel relationships, and bounded parcel retries across the industrial, commercial, and mixed-service seed matrix.
- Project Ironclad combat reported `25 passed, 1 failed, 1 explicit-only skipped`. The single failure is the pre-existing `map_editor_layout_store_test.gd` persisted-example mismatch: `persisted-edited-industrial-layout.json` still pins parcel grammar revision `coherent_parcel_grammar_v3`, while Task 5.4 production now requires `coherent_parcel_grammar_v4_bounded_search`; two old equipment-compound placements also fail the current frontage/service contracts. Task 6.2 does not alter that example or those contracts. Combat, LOS, cover, actions, and mission tests in the tier passed.
- The rendered capture command completed successfully. It is explicit-only and intentionally excluded from automated headless tiers.

Headless runs also emitted non-fatal host-environment warnings while opening `user://logs` and reading the Windows root certificate store. They did not affect test outcomes.

## Remaining limits and Task 6.3 readiness

- The runtime preset remains the opt-in 60×50 industrial identity; commercial and mixed-service gameplay presets are not exposed.
- Full Generation 2.0 mission sequences are certified for Eliminate and Terminal. Other mission mechanics retain their existing independent regressions and the spatial readiness listed above.
- The procedural industrial grammar currently has no elevation modules, so Generation 2.0 vertical traversal is unsupported rather than silently simulated.
- This task records normal replay output while completing both missions, but does not certify Generation 2.0 replay playback or historical reconstruction. That remains Task 6.3.
- The same seed and current dependency revisions reproduce the tested document. A seed alone is not a historical content-version guarantee.

The shared document now owns the mission space that gameplay consumes, representative missions complete through existing authoritative APIs, and the boundary is ready for replay-specific validation.
