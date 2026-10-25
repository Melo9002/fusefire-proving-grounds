# Phase 6.4: Integrated Generation 2.0 Pipeline Certification

## Recommendation

**Opt-in ready.** The currently exposed 60×50 `industrial_district` preset is suitable for continued opt-in use with the certified Eliminate and Terminal scenarios. Its generated document, tactical compilation, asset-first presentation, edited-map path, and replay reconstruction use one validated pipeline. No blocking defect remains in that bounded configuration.

This is not a recommendation to make Generation 2.0 the default. Runtime identity coverage, complete mission-sequence coverage, vertical content, broader seed review, and final owner visual approval remain too narrow for default rollout.

## Certification baseline

- Date: 2026-10-24.
- Baseline revision: `88311eb9c02ed4c34635a81de39ba13899cfffc4` plus the Task 6.4 representative persistence-fixture refresh described below.
- Godot: `4.7.2.stable.official.ed1daf0bf`.
- Gameplay preset: opt-in `GENERATION_2_INDUSTRIAL`, `industrial_district`, 60×50 cells, explicit integer seed.
- Default: the legacy generator remains selected and follows its existing `FlatMapGenerator.generate_with_cover()` path.
- Content contract: unified layout schema 1 inside Map Editor persistence schema 2; parcel grammar `coherent_parcel_grammar_v4_bounded_search`; resolved asset geometry/calibration hashes and assembly certification signatures are pinned per document.
- Runtime missions fully exercised on Generation 2.0: Eliminate and Terminal.
- Other mission types: Reach, Rescue, Extract, Enemy Evacuation, Protect, and Survive retain existing independent gameplay regressions; Generation 2.0 reserves and validates their required zones, but this certification does not claim their full runtime sequences on this preset.

The working tree already contained untracked Ironclad output and Godot `.png.import` metadata from earlier work. They were excluded from this task and were not deleted or incorporated.

## Supported configuration matrix

| Layer | Identity / seed | Coverage | Result |
| --- | --- | --- | --- |
| Normal battle runtime | `industrial_district` / 17 | Match Setup opt-in, document build, presentation, legal deployment, Eliminate and Terminal gameplay | Certified representative configuration |
| Edited battle runtime | edited `industrial_district` / provenance seed 17 | save/load, dependency validation, normal battle, 35-action Eliminate replay | Certified representative configuration |
| Generator and Map Editor | `industrial_district` / 17 | 60×50 bounded parcel search and visual review | Valid; 8 functional parcels, no fallback |
| Generator and Map Editor | `commercial_street` / 7319 | 60×50 bounded parcel search and visual review | Valid; one explicit mission-reservation fallback after all 12 supported candidates conflict |
| Generator and Map Editor | `mixed_service` / 11027 | 60×50 bounded parcel search and visual review | Valid; intentional recipe buffers, no invalid-content fallback |

Commercial and mixed-service are supported coherent-generator/editor identities, not selectable gameplay presets. They were tested at that boundary and are not mislabeled as playable runtime certifications.

## End-to-end gameplay evidence

The Generation 2.0 tactical fixture executes the real battle scene and authoritative services.

### Eliminate

- Two player units and one enemy deploy to unique legal authored cells.
- A real movement transaction traverses open road space.
- A destination occupied by authored environment occupancy is rejected without AP or revision mutation.
- A Wait transaction advances activation normally.
- A legal attack defeats the last hostile, completes the objective, and produces Victory.

### Terminal

- The generated document contains the preplanned and reserved terminal region.
- A complete authoritative path exists from player deployment to a legal interaction approach.
- The ordinary terminal query/action activates the terminal, completes the objective, and produces Victory.

The same fixture verifies a full-cover LOS blocker, directional low-cover penalty, a required parcel access route, presentation/tactical placement agreement, and explicit `INSUFFICIENT_DEPLOYMENT` rejection. The coherent grammar currently authors no elevation links, so vertical traversal is unsupported Generation 2.0 content rather than an inferred capability.

No manual keyboard/mouse mission completion is claimed. These completions are deterministic automated playthroughs through the real scene, turn manager, action service, mission service, and battle result. Manual work in this certification was visual inspection of the rendered evidence.

## Replay and edited-map evidence

The Task 6.3 lifecycle performs:

1. deterministic seed-17 generation;
2. an independent editable copy;
3. a valid optional streetlight edit;
4. document revalidation;
5. versioned save and reload;
6. normal edited-map battle initialization;
7. a complete 35-action Eliminate battle;
8. replay JSON persistence;
9. reconstruction from the exact embedded layout document; and
10. comparison of every resolved result and post-action tactical fingerprint.

All 35 records verify and both executions reach Victory. Presentation signatures independently match component identity, origin, and rotation. Playback does not regenerate from the seed. Missing assets, stale dependencies, broken relationships, unsupported identity, malformed persistence, invalid deployment, dimension mismatch, missing replay document, and document-signature divergence are explicit failures.

## Geometry, assembly, and visual review

Current permanent regressions independently cover canonical quarter turns, imported road openings, rectangular and offset visual envelopes, certified sealed-shell frontage, measured machine sockets, equipment service access, exact parcel frontage spans, reservations, relationship validation, and bounded retries.

Normal and diagnostic evidence was re-inspected for:

- industrial seed 17 normal gameplay and building frontage;
- commercial seed 7319 frontage and mission-protected open space;
- mixed-service seed 11027 equipment/service area; and
- the edited seed-17 replay reconstruction.

Observed results:

- imported roads retain continuous supported openings and no duplicate procedural asphalt layer;
- inspected sidewalks and curbs remain continuous;
- certified shells face their selected frontage and remain distinct from intentionally open equipment/loading assemblies;
- service and loading regions shown in the inspected parcels remain unobstructed;
- normal and replay views preserve environment identity and placement transforms; and
- tactical overlays are supporting diagnostics, not substitutes for visual acceptance.

Reviewed evidence:

- [industrial seed 17 normal battle](evidence/generation-2-tactical-gameplay-task-6.2/generation-2-seed-17-normal.png)
- [industrial seed 17 frontage](evidence/generation-2-tactical-gameplay-task-6.2/generation-2-seed-17-frontage.png)
- [industrial seed 17 tactical overlay](evidence/generation-2-tactical-gameplay-task-6.2/generation-2-seed-17-tactical-overlay.png)
- [commercial seed 7319 frontage](evidence/bounded-parcel-search-task-5.4/commercial_street-7319-frontage.png)
- [mixed-service seed 11027 service area](evidence/bounded-parcel-search-task-5.4/mixed_service-11027-service.png)
- [edited industrial battle](evidence/generation-2-replay-edited-map-task-6.3/generation-2-edited-battle.png)
- [edited industrial replay reconstruction](evidence/generation-2-replay-edited-map-task-6.3/generation-2-edited-replay.png)

A lamp remains visually close to a secondary garage face in the seed-17 frontage view. It does not intersect the certified west access corridor or block the tested tactical route. This is recorded as a nonblocking façade-aware dressing concern, not hidden as a fully reviewed catalog-wide placement guarantee.

## Determinism and generation diagnostics

Repeated identical inputs reproduce accepted placements, selected frontages, search outcomes, relationships, compiled tactical cells and mission zones. Candidate ordering is deterministic and each attempt uses a candidate-local seed. Rejected candidates operate on cloned layouts and reservation ledgers, leaving no partial state.

The representative 60×50 matrix reports:

| Identity / seed | Functional / buffer | Attempts / rejected | Fallback / exhausted |
| --- | ---: | ---: | ---: |
| industrial / 17 | 8 / 0 | 8 / 0 | 0 / 0 |
| commercial / 7319 | 11 / 3 | 25 / 12 | 1 proven incompatibility / 0 |
| mixed service / 11027 | 9 / 8 | 17 / 0 | 0 / 0 |

The commercial fallback protects a deployment reservation; every rejected supported candidate reports `RESERVED_REGION_BLOCKED`. Mixed-service buffers are intentional recipe outcomes. No representative case exhausted the search budget. A separate synthetic regression proves that unexamined supported candidates beyond the fixed budget report `SEARCH_BUDGET_EXHAUSTED`.

## Persistence compatibility correction

The only known failing current regression from Task 6.2 was reproduced before correction. `persisted-edited-industrial-layout.json` pinned parcel grammar v3 and contained two equipment compounds that predated current frontage/service validation. Production round trips passed, while the tracked representative document correctly failed current dependency and relationship checks.

The example was regenerated through the ordinary seed-2208 coherent generator, `editable_copy()`, and `MapEditorLayoutStore.save()` path. No assertion or validation rule was weakened. The unchanged persistence test now passes all identity, provenance, relationship, dependency, deterministic reconstruction, malformed-input, and legacy-compatibility assertions.

## Runtime measurements

Measurements are local wall-clock observations on this workstation, not budgets or guarantees. The Phase 5 comparable 50×40 matrix measured coherent generation between 2,580 ms and 3,266 ms across six identity/seed cases. A fresh headless 60×50 industrial seed-17 probe measured:

| Operation | Observed time |
| --- | ---: |
| Initial generation, unified document construction, and first tactical compile | 19,767 ms |
| Dependency and assembly/parcel contract validation | 6,316 ms |
| Repeat tactical compilation of the accepted document | 8,287 ms |
| Document-driven battle initialization and presentation | 9,418 ms |
| Embedded-document replay initialization and presentation | 15,680 ms |

The presenter instantiated 62 component nodes. Godot's static-memory monitor reported 94,099,486 bytes before generation, 105,617,730 bytes after repeated compilation, and 138,237,947 bytes after the battle scene and presentation were initialized. These are three in-process snapshots, not peak-memory or leak measurements.

The measurements include Godot process and test-fixture overhead where the current architecture does not expose a narrower timer. No unsupported improvement percentage is claimed. Static memory is sampled only where practical and is not treated as a leak or peak-memory proof.

## Legacy compatibility

- Match Setup defaults to Legacy.
- Named legacy generation and special-map behavior remain present.
- Legacy battle initialization does not require a unified Generation 2.0 document.
- Schema-1 Map Editor files require an explicit `legacy_compatibility` identity and report information loss.
- Existing schema-3 non-Generation-2.0 replays remain valid without an embedded layout document.
- The legacy replay smoke and normal battle smoke continue to exercise their established paths.
- No gameplay entry point or default was changed in this task.

## Verification commands and final results

Focused and broad commands:

```powershell
godot_console --headless --path . --script res://tests/map_editor_layout_store_test.gd
godot_console --headless --path . --script res://tests/generation_2_battle_preset_test.gd
godot_console --headless --path . --script res://tests/generation_2_tactical_gameplay_test.gd
godot_console --headless --path . --script res://tests/generation_2_replay_edited_map_test.gd
godot_console --headless --path . --script res://tests/coherent_parcel_retry_test.gd
.\tools\run_tests.ps1 subsystem -Subsystem generation
.\tools\run_tests.ps1 subsystem -Subsystem combat
.\tools\run_tests.ps1 subsystem -Subsystem missions
.\tools\run_tests.ps1 subsystem -Subsystem movement
.\tools\run_tests.ps1 subsystem -Subsystem replay
.\tools\run_tests.ps1 smoke
```

Final certification results:

- Generation subsystem: **PASS=34, FAIL=0, SKIP=16** in 1,284.30 seconds. Skips are the documented explicit GPU captures and extended stress/quality workflows.
- The generation tier includes the actual opt-in BattleLevel, both representative Generation 2.0 mission completions, the complete edited-map/replay lifecycle, the three-identity bounded-search matrix, geometry, roads, assemblies, documents, reservations, relationships, legacy flat generation, and tactical validation.
- Map Editor persistence after refreshing the tracked representative document: **0 failures** with all original assertions retained.
- Combat subsystem after the compatibility correction: **PASS=27, FAIL=0, SKIP=2** in 329.10 seconds. Skips are the explicit replay capture and extended map-quality workflow.
- Missions subsystem: **PASS=17, FAIL=0, SKIP=0** in 225.35 seconds.
- Movement subsystem: **PASS=13, FAIL=0, SKIP=0** in 70.18 seconds.
- Task 6.3 replay subsystem on the same production revision: **PASS=10, FAIL=0, SKIP=1**; the skip is its explicit GPU capture.
- Task 6.3 smoke tier on the same production revision: **PASS=10, FAIL=0, SKIP=0**.

Explicit GPU captures remain outside headless pass/fail tiers and were reviewed separately.

## Issue classification

### Blocking issues

None discovered for the recommended industrial seed-17 Eliminate/Terminal and edited-map replay configurations.

### Nonblocking follow-up

- Only industrial 60×50 is a runtime preset.
- Full Generation 2.0 mission completion is certified only for Eliminate and Terminal.
- The current coherent grammar has no elevation modules.
- Broader seed and catalog-wide visual quality are not established by this bounded matrix.
- Commercial seed 7319 deliberately leaves mission-protected open space after supported candidates conflict.
- Mixed-service seed 11027 contains intentional buffers under the current recipe grammar.
- Façade-aware optional furniture can be improved around secondary faces.
- Replay files are larger because they embed the accepted layout document.
- Historical replay across arbitrary future asset or simulation revisions is intentionally unsupported without compatible pinned dependencies.
- No formal CI performance or memory threshold exists.

## Changed files

- `docs/architecture/examples/persisted-edited-industrial-layout.json`: refreshed through current validated generation/edit/persistence contracts.
- `docs/architecture/reviews/2026-10-24-phase-6-4-integrated-pipeline-certification.md`: this certification record.

No production gameplay, generation, replay, tactical, or presentation code changed during Task 6.4.

## Rollout boundary

Continue Generation 2.0 as an explicit opt-in. Limited expansion should next certify another runtime identity or complete additional mission sequences using the existing shared pipeline. Do not enable it by default yet.

Final visual approval and any default-rollout decision belong to the project owner. Phase 7 was not started.
