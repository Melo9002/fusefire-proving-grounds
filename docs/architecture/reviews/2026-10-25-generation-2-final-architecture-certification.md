# Generation 2.0 final architecture certification

Date: 2026-10-25
Scope: Phase 7.3 and evidence-based review of Phases 1–7

## Readiness recommendation

**Opt-in ready.** The supported 60×50 industrial configuration is deterministic, document-driven, playable, persistent, and replayable. It is not yet a candidate for default rollout: runtime Generation 2.0 remains intentionally industrial-only, content breadth is modest, mixed-service still produces many buffer parcels, and the existing derived loading canopy remains an explicit visible-geometry exception. No blocking defect was found in the supported opt-in configuration.

This recommendation does not authorize changing the default. Legacy generation remains the default and Generation 2.0 remains an explicit Match Setup choice.

## Phase 7.3 content addition

The curated addition is the City Kit Industrial shipping-container family:

| Assembly | Imported assets | Classification | Supported use |
|---|---|---|---|
| `shipping_container_family` | `shipping-container-a`, `shipping-container-b`, `shipping-container-c` | Complete standalone tactical-obstacle family | Industrial and mixed-service yards, staging and loading parcels; rotations 0–3 |

This family was selected because generation already relied on these meshes for meaningful full-cover obstacles, yet presentation bypassed semantic approval through raw paths. Certification now pins each GLB geometry hash and calibration signature, uses catalog asset IDs, records the family dependency in layout documents, and preserves an explicitly authored 2×5 tactical footprint. It adds no candidate combinations and therefore does not expand the bounded search cost.

The three assets have confirmed `tactical_obstacle` / `complete` semantics, `+z` working faces, a measured common envelope, identical supported scale, and no invented mating sockets. Negative tests reject missing variants, stale geometry/calibration, and a false building-completeness claim. Procedurally approved semantic assets increased from 32 to 35; all 315 catalog entries remain confirmed. Approval is not treated as certification for the remaining assets.

## Resulting architecture and data flow

The recovered path is:

`seed + environment identity` → bounded coherent assembler → parcel ownership/frontages/reservations/relationships → certified modules and assemblies → versioned battlefield layout document → validation/dependency resolution → `EnvironmentModuleMapWriter` → authoritative `MapData` → shared asset-first presentation → battle/replay.

The layout document owns construction intent, identity, provenance, accepted transforms, relationships and dependency revisions. `MapData` alone owns traversal, stopping, cover, LOS, occupancy, elevations and deployment legality. Imported meshes remain presentation inputs and never silently create tactical rules.

## Certified inventory and supported composition

- Roads: imported straight, T, cross and curve geometry have orientation/opening contracts. The coherent assembler uses the certified primary route and one bounded, boundary-reaching secondary branch; unsupported interior dead ends are rejected.
- Streetscape: the bounded Phase 2 street slice certifies imported road presentation, sidewalk/curb relationships, streetlight placement and one real frontage.
- Building: `city_industrial_shell_i` is the certified sealed exterior shell. It is exterior-only and does not imply an interior.
- Measured modular installation: `pipe_receiver_unit` demonstrates deterministic machine/pipe socket attachment.
- Functional parcel: `certified_pipe_service_pad` demonstrates required equipment, termination, service/loading access and optional dressing.
- Tactical obstacles: `shipping_container_family` is now a certified three-variant imported family.
- Parcels: 10×10, 20×20, and curated 20×10 / 10×20 service strips; the elongated form is limited to compatible industrial or mixed-service loading use.
- Environment identities: industrial, mixed-service and commercial participate in deterministic editor/generator matrices. The normal runtime opt-in preset is deliberately limited to industrial.

The existing derived loading canopy is retained as a documented authored procedural exception. It is an intentionally open structure, not evidence of a certified imported canopy family. Replacing it with imported content is the highest-value remaining asset-first cleanup.

## Verification evidence

### Focused Phase 7.3 checks

- `certified_cargo_asset_family_test.gd`: passed. Real imported variants, all rotations, tactical contract, stale dependencies, false completeness, deterministic seed 17 placement, document dependencies and save/load were covered.
- `semantic_asset_catalog_test.gd`: 2,323 checks passed; 315/315 confirmed, 35 procedurally approved, no review flags.
- `coherent_parcel_size_expansion_test.gd`: passed for industrial 17, mixed-service 11027 and commercial 7319; cargo certification did not alter parcel/search counts.
- `battlefield_layout_document_test.gd`: passed, including deterministic construction and stale dependency rejection.
- `generation_2_battle_preset_test.gd`: passed. The real battle scene reached a controllable Generation 2.0 state; unsupported configuration failed without partial activation; legacy initialization remained functional.
- `generation_2_replay_edited_map_test.gd`: passed. An edited saved layout completed an Eliminate mission, recorded 35 actions, reloaded, replayed 35/35 actions, and reproduced the victory and authoritative tactical state.

The expected explicit rejection logged by the battle-preset test is test evidence, not an unexpected failure. Godot also reported local log/root-certificate-store warnings; these did not affect assertions or rendering.

### Deterministic matrix

| Identity / seed | Parcel result | Attempts / rejection | Fallback | Observed generation cost for two builds |
|---|---:|---:|---:|---:|
| industrial / 17 | 10 functional, 1 buffer | 12 / 1 | 0 | ~7.45 s |
| mixed-service / 11027 | 7 functional, 8 buffers | 15 / 0 | 0 | ~8.19 s |
| commercial / 7319 | 10 functional, 3 buffers | 24 / 12 | 1 mission-protected | ~11.47 s |

These are direct measurements from one bounded test run, not comparative improvement percentages. No search-budget exhaustion occurred. The commercial fallback is explicit and mission-protected rather than a concealed invalid parcel.

### Rendered inspection

New clean captures (no engineering overlays) are in `evidence/generation-2-final-task-7.3/`:

- `shipping-container-family-oblique.png`
- `shipping-container-family-overhead.png`

They show all three imported variants resting on the support plane through the production presenter. Existing reproducible evidence remains available for secondary-road seams, 10×20/20×10 parcels, the certified building shell, frontage/access relationships, playable seed 17, tactical overlays and edited-map replay. Visual inspection found no new intersection or scaling defect in the cargo family. This is bounded evidence, not catalog-wide visual approval.

## Assessment against Astra's findings

- **F1 geometry:** canonical road openings and logical connectors are regression-tested against real geometry.
- **F2 transforms:** logical quarter turns, Godot yaw, working faces and corrective asset yaw share one convention.
- **F3 envelopes:** rectangular and offset envelopes transform from corners and drive reservations correctly.
- **F4 contract drift:** certified assemblies pin geometry/calibration revisions; stale dependencies reject load/compile. The cargo family closes a remaining raw-path gap.
- **F5 relationships:** parcels retain ownership, exact frontage spans, mission/access reservations and role-specific frontage, pedestrian, loading and service requirements.
- **F6 cross-representation:** geometry, document, tactical compilation and presentation have distinct checks; tactical validity is not substituted for visual validity.
- **F7 lifecycle:** generated, edited, saved, loaded, battle and replay paths share the validated document boundary.
- **F8 asset-first presentation:** certified roads, shell, machinery and cargo use imported geometry. The derived loading canopy remains the principal explicit exception.

## Legacy compatibility

Default and explicit legacy generation still initialize, named engineering fixtures remain available, authored documents remain loadable under the versioned compatibility policy, and gameplay rules were not changed. Generation 2.0 remains opt-in. No legacy subsystem was deleted.

## Known limitations and debt

| Severity | Limitation |
|---|---|
| Medium | Derived loading-canopy boxes remain an explicit visible exception and should be replaced by a certified imported open-structure assembly. |
| Medium | Runtime opt-in is industrial-only; mixed-service and commercial have editor/generator evidence but not equivalent runtime certification. |
| Medium | Mixed-service seed 11027 contains eight intentional buffers, showing limited compatible functional content rather than a solver failure. |
| Low | Internal secondary-road dead ends remain unsupported because no certified end cap exists. |
| Low | `city_industrial_shell_i` is the only fully certified sealed building shell; other semantically understood buildings are not automatically certified. |
| Low | Curve-to-square sidewalk/curb transitions, vehicle turning contracts, interiors and general vertical composition remain unsupported. |
| Low | Street-furniture placement is contract-aware but not façade-aware enough to eliminate every aesthetically awkward lamp location. |

No known limitation above blocks the currently supported industrial opt-in configuration.

## Changed files for Phase 7.3

- Extended assembly role/completeness vocabulary for complete tactical obstacles.
- Added `industrial_cargo_assembly_catalog.gd` and registered it in the initial assembly library.
- Routed `cargo_container` presentation through certified semantic asset IDs.
- Approved the three reviewed container assets for procedural selection.
- Added permanent family certification/lifecycle tests and a rendered capture fixture.
- Added the capture to visual-test discovery and added this final assessment.

## Prioritized future work

1. Replace the derived loading canopy with a measured imported open-structure assembly.
2. Certify a road end-cap/termination and the next most useful complete industrial shell.
3. Add compatible mixed-service functional templates to reduce intentional buffer frequency.
4. Improve façade-aware street-furniture placement within the existing bounded contracts.
5. Broaden runtime/mission certification only after each identity has equivalent visual evidence.
6. Improve Asset Lab authoring for narrowly scoped family contracts and local adjacency previews.

Universal scene graphs, WFC, unrestricted grammars, automatic interiors, universal vertical composition, runtime AI assembly and catalog-wide conversion remain explicitly deferred.
