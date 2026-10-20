# Independent assessment: battlefield and environment generation

Date: 2026-10-20. Inspected baseline: `044fc24ceb7de293258284ee1ffd1f62be7d038f`.

Scope: imported environment assets, calibration, semantics, modules, coherent assembly, tactical translation, presentation, Map Editor and gameplay entry points. Consultation only: no production code or test assertions changed. The owner approved this report and clarified that Generation 2.0 should primarily use downloaded assets, and that semantic metadata was intended to help AI agents assemble modular parts.

## 1. Executive assessment

**Retain the tactical foundation and parcel approach; repair the geometry contract and partially replace the assembly/orchestration layer before expanding the grammar.** The failures are a mixture of reproducible implementation defects and architectural gaps. A whole-system rewrite is not justified. More metadata and more randomly selected assets will not resolve the current problems.

Three geometric defects are particularly consequential: the straight-road asset is interpreted along the wrong axis; logical and visual quarter-turn conventions disagree; and rectangular visual envelopes rotate incorrectly. Existing tests pass despite these failures. Fresh rendered output visibly contradicts claims of continuous roads.

The deeper problem is that several representations independently describe the same place: asset calibration, semantic working faces, hard-coded building profiles, module geometry, parcel recipes and presenter transforms. They are not bound by a sufficiently strong end-to-end contract. “Fits without overlapping,” “tactically reachable,” and “forms a believable place” are different properties; the implementation mainly enforces the first two.

Good work worth keeping includes explicit `MapData` authority, shared authored/procedural module translation, deterministic RNG, transactional candidate placement, separation of clearance from tactical occupancy, completeness classifications, calibrated import handling, and diagnostic captures. Hiding old component demonstrations behind engineering fixtures was appropriate. These achievements are foundations, not evidence that the rendered environment is correct.

## 2. Actual data flow

| Stage | Current implementation | Important boundary |
| --- | --- | --- |
| Import | Kenney GLBs under `art/environments/kenney`; Godot PackedScenes | Imported geometry is presentation input, not tactical authority. |
| Calibration | `tools/asset_lab/asset_catalog.gd`, `asset_calibrations.json`, `native_bounds.json` | Runtime scale, yaw, anchor and offsets resolve asset override > category > fallback. |
| Meaning | `semantic_asset_catalog.gd`, `asset_semantics.json` | Identity, completeness, context, working faces and procedural eligibility. Two machine assets also have measured mating sockets. |
| Module contracts | `IndustrialModuleCatalog`, `IndustrialBuildingCatalog`, `IndustrialBuildingPlacementProfiles` | Tactical cells, clearances, connectors and visual envelopes are authored separately, predominantly in code. |
| Planning | `CoherentEnvironmentAssembler.apply()` | One cross/T road plot, greedy 20×20 parcels, remaining 10×10 lots, bounded recipe selection. |
| Placement | `EnvironmentModuleLayout.try_add()` | Checks footprint, same-layer clearance and same-layer visual-envelope overlap; does not establish every functional relationship. |
| Tactical commit | `EnvironmentModuleMapWriter.apply()` | Writes cell effects, elevated surfaces and traversal links; coherent assembler subsequently repairs deployment cells. |
| Presentation | `GeneratedTerrainPresenter` → `ModularEnvironmentPresenter` | Recreates catalog, resolves approved visuals and current calibration, constructs meshes and derived road sections. |
| Tools/game | Map Editor uses coherent/custom layouts; `battle_level.gd:166` calls `generate_with_cover()` | Shared presenter does not mean shared generation entry point. |

The normal battle path remains the older building/cover/refinery/warehouse system. `MapBatchTester` also exercises `generate_with_cover()`. The new districts are an editor generation path, not the normal battlefield replacement.

## 3. Findings and root causes

### F1 — Confirmed: straight roads use the wrong asset axis

`asset_catalog.gd:14` describes the straight road's traffic axis as Z. `industrial_module_catalog.gd:121` authors ±Z road connectors and adds the GLB without an asset-normalization quarter-turn. The imported straight-road mesh actually runs along X: its raised edge strips lie at Z = ±0.4…±0.5 and span X = −0.5…+0.5; root and mesh transforms are identity. The investigative probe records the vertices and transforms.

The result is not merely an aesthetic disagreement. Fresh seed-17 industrial and seed-11027 mixed-service captures show transverse pavement bands interrupting intended streets. The imported road AABBs are correctly centered and 10×10, so a bounding-box seam test alone would miss the defect.

**Recommendation:** verify source-to-module orientation for straight, T, cross and curve assets independently. Normalize asset axes once; compare transformed road openings with logical connectors. Do not fix this with another calibration tweak whose effect on other consumers is unknown.

### F2 — Confirmed: logical quarter-turns and rendered yaw disagree

`EnvironmentModuleDefinition.rotate_direction()` maps local +Z to −X for rotation 1. `ModularEnvironmentPresenter._add_visual()` uses positive Godot Y yaw, which maps +Z to +X. `_rotate_point()` follows the logical convention while mesh orientation follows the opposite convention.

The probe instantiates the real `industrial_shell_i` through the presenter at all four rotations. Its reviewed front agrees with the planned frontage at rotations 0/2 and points exactly opposite it at 1/3 (direction dot product −1). This is a reproduced implementation defect, not a hypothesis about metadata quality.

**Recommendation:** define one grid-to-world placement transform and use it for cells, points, directions, sockets, mesh placement, offsets and bounds. Audit asset-local corrective yaw separately. Existing street-furniture yaw constants may compensate for the old convention: blindly reversing every yaw risks new regressions.

### F3 — Confirmed: rectangular envelope rotations shift the reservation

`EnvironmentModuleLayout.world_visual_envelope()` repeatedly applies `definition.size.y - 1` for every quarter-turn without swapping rectangular dimensions. For a 2×5 module and local envelope `(0,0,0)+(2,1,5)`, rotation 2 produces an unshrunk origin `(2,0,-1)`; the corresponding half-turn formula gives `(-1,0,-1)`. Rotation 3 is also shifted. The routine shrinks bounds by 0.01 afterward, which does not correct the error.

This means accepted/rejected visual overlaps can refer to the wrong location. **Hypothesis:** this contributes to some unnecessary candidate rejection and visible intersections; the frequency across all seeds has not been measured.

**Recommendation:** transform all corners using the same canonical placement transform, with asymmetric and offset fixtures at all rotations. Retain the intentional distinction between mesh bounds and tactical occupancy.

### F4 — Confirmed architecture gap: calibration and assembly contracts can drift

Building dimensions and working faces are duplicated in `IndustrialBuildingPlacementProfiles.PROFILES`; other envelopes are constants in `IndustrialModuleCatalog`. Rendering reads current Asset Lab calibration. Building eligibility checks that a semantic working face exists, but the actual normalization uses the separately authored profile face. Geometry revisions do not invalidate these contracts automatically.

The profile test checks module bounds against profile constants, not independently against the resolved rendered geometry. It can therefore pass when both sides share a stale assumption. Imported visuals also use fixed world scale while several derived dimensions use `cell_size`; the current editor always uses 1.0, so arbitrary cell-size support should not be assumed.

**Recommendation:** maintain one resolved, versioned asset contract per generation run. Derive visual bounds from its complete transform; keep gameplay footprints explicitly authored. A calibration/mesh revision should invalidate affected assembly certification, not silently resize gameplay. Initially enforce the supported one-unit grid rather than generalize unnecessarily.

### F5 — Confirmed architecture gap: parcels have recipes but limited relationship validation

The assembler chooses the first road-facing edge, then fixed-offset recipes. It tries different recipes, but not a general search over frontage segments, valid orientations or access relationships. `_road_edges_for_macro_rect()` records a direction if any adjoining macro cell is a road; it does not preserve the exact connected frontage interval. Road furniture is committed before parcels.

`placements_connect()` checks positioned tactical connectors and is used to establish road connectivity. Parcel acceptance does not require a loading connection, an entrance-to-sidewalk route, or a machine operator area to connect to a service path. A named `equipment_compound` recipe is paving, machinery and one fence; its name does not establish a complete enclosure. Landlocked cells become empty `district_buffer` recipes. This is explicit, but does not itself make large empty regions spatially convincing.

**Recommendation:** retain plots/parcels and add a few explicit relationships: frontage-to-street, pedestrian access, loading access, service clearance, and required versus optional occupants. Store parcel ownership and actual frontage spans. Reserve access before furniture. Allow optional dressing to fail without rejecting an otherwise valid building. Preserve meaningful rejection reasons.

### F6 — Confirmed: visual and tactical validation prove different things

Seven focused suites passed (details below), while fresh renders show broken-looking streets. The road tests check connector connectivity, fixture indices, metadata widths, mesh counts and the 2× adapter. The lamp-facing assertion checks the expected rotation integer, not the final world-space working face. Those checks protect useful contracts but do not establish rendered agreement.

`MapQualityEvaluator` measures tactical cover/routes/openness/exposure, not architectural seams or frontage. The editor's “VALID” label comes from tactical validation. It should not be read as assembly or visual certification.

**Recommendation:** distinguish tactical validity, assembly validity and visual review in diagnostics. Add cross-representation tests and a small manual render matrix; do not weaken existing assertions to accommodate fixes. Also explicitly include `semantic_district_generation_test.gd` in generation-subsystem selection: its name currently misses that runner's generation regex.

### F7 — Confirmed: tool and gameplay integration is incomplete

The editor's generated/custom paths share the module writer and presenter, which is good. But “Edit copy” copies placements, not the plan or repaired deployments. `_build_custom_map()` recreates flat deployments and does not run coherent deployment repair. The JSON store persists placements and map size, but not environment identity, generator seed, dependency revisions or parcel relationships. The presenter defaults missing plan identity to mixed-service road materials.

**Consequences:** copying/saving a layout does not guarantee preservation of all semantic, visual or deployment context. The magnitude of deployment changes was not separately reproduced in this review; the omitted data and differing paths are source-confirmed.

**Recommendation:** use a compact shared layout document for generated, authored and edited maps, with identity, seed/provenance, placements, required relationships and dependency versions. Preserve or explicitly recompute deployments through one validated path. Introduce the same input to gameplay behind an opt-in preset before replacing the default.

### F8 — Confirmed: visible fallback geometry conflicts with an asset-first direction

The road presenter always creates asphalt, sidewalk, curb and marking boxes, then adds imported road meshes. This is not a conditional fallback. Some derived curb geometry reaches 0.16 units, above the straight imported tile's measured 0.11 top; the layers cannot simply be assumed hidden. The loading canopy is also constructed from boxes. The older derived service building is appropriately restricted to engineering fixtures.

**Recommendation:** downloaded kit geometry should own normal visible surfaces. Keep derived geometry for diagnostics, invisible tactical representation, or explicitly approved gaps. If a kit cannot support an intended building, choose a supported assembly or identify the content gap rather than silently substitute a generic box structure. Do not mandate use of all 315 assets: only 32 currently have procedural approval, and approval is not proof of interchangeable dimensions or mating compatibility.

## 4. Architectural options

| Option | Benefit | Cost/risk | Assessment |
| --- | --- | --- | --- |
| Patch transforms and continue growing recipes | Fastest immediate recovery | Duplicated contracts and integration gaps persist | Necessary first step, insufficient endpoint. |
| Asset-first authored parcels with a small relationship model | Reuses existing code; predictable art and gameplay; manageable validation | Requires a curated assembly library and shared document | **Preferred.** |
| General semantic scene-graph solver | Can represent rich adjacency, ownership and function | Large search/authoring/debugging burden | Use a small relationship vocabulary, not a universal solver. |
| Full hierarchical spatial grammar | Can produce building/block variation | Requires reliable terminals, socket rules and completeness contracts first | Current plot→parcel→module hierarchy is enough initially. |
| Local socket/WFC-style adjacency solver everywhere | Useful for compatible pipes, corridors or road tiles | Local compatibility alone does not establish mission routes or believable districts | Consider only inside bounded assemblies after contracts are proven. |

These are engineering options, not claims that a named procedural technique will automatically produce good environments. No external algorithm benchmark was performed.

## 5. Preferred design and AI-agent authoring

Use the following flow:

`imported asset + calibration + reviewed semantics → resolved asset contract → certified assembly → plot/parcel relationships → validated placements → MapData + presentation`

Keep a single placement document as input to both tactical compilation and rendering; `MapData` remains the sole authority during gameplay. Visual geometry must agree with authored gameplay intent, but should not infer walkability or cover automatically from arbitrary meshes.

Semantics should be retained. It answers “what is this and where is it appropriate?” A geometric assembly interface answers “where and how can it connect?” The existing two measured machine/pipe socket records are useful prototypes; general module connectors already provide tactical positions/directions. Extend those ideas rather than create another independent catalog.

For a small initial kit, record:

- Stable asset ID and geometry/calibration revision; canonical asset-to-module transform and units.
- Named visual mating sockets with position, normal, tangent/up reference, compatible family, seam dimensions, allowed rotation and tolerance. Keep these distinct from tactical access connectors where their purposes differ.
- Required versus optional sockets; explicit end-cap/termination rules; visual envelope and service/access clearances.
- Assembly roles such as complete shell, open shelter or equipment unit, plus authored tactical footprint and permitted contexts.

Agents should work through operations equivalent to **list compatible pieces**, **attach socket to socket**, **validate assembly**, **render inspection views**, and **save approved template**. Return concrete failures such as socket separation, incompatible pitch, blocked entrance, missing cap or stale calibration. A socket normal alone cannot determine roll; prose such as “factory pipe” cannot determine a mating transform.

Use AI during authoring to propose compositions. Let deterministic geometry and tactical checks reject invalid proposals, then let the owner approve their visual quality. Runtime generation selects and varies certified templates. This avoids requiring the runtime generator—or each agent—to rediscover how the vendor's kit fits together.

## 6. Incremental migration and implementation handoff

1. **Restore geometric trust.** Reproduce F1–F3 as permanent focused regressions. Establish canonical transforms and independently inspect every road terminal and one asymmetric building in all four rotations. Do not expand road topology yet.
2. **Certify one asset-first street slice.** Two straight segments, a T/cross, a curve if supported, sidewalk transitions, lights and one building frontage. Use imported visible surfaces; expose derived surfaces only in diagnostics. Verify actual openings, height seams and fixture facing. Select tactical dimensions that accommodate the kit at a deliberate shared scale.
3. **Certify a small assembly library.** One sealed shell frontage, one genuinely supported modular structure, one equipment/loading parcel. Use the existing machine socket examples. Permit an intentionally open yard if the kit cannot yet supply a coherent canopy; document the limitation. Avoid a catalog-wide reauthoring campaign.
4. **Introduce the shared layout document.** Preserve generated identity/provenance through edit-copy and save/reload; resolve contracts once per build; report unsupported/missing assets as validation failures instead of presenting invisible structures.
5. **Add relationships and mission reservations.** Reserve deployment/objective/access regions before committing parcels. Retain existing tactical validation as the final guard. Introduce local retries over supported frontage choices and optional decoration, with a fixed search budget.
6. **Prove gameplay integration.** Opt-in battle preset uses the same document, compiler and presenter as the editor. Verify mission completion, pathfinding, LOS, replay and edited-map loading. Preserve old generators as named legacy fixtures until replacement behavior is demonstrated.
7. **Expand only after that slice passes.** Add secondary roads, more parcel sizes and additional kit families based on content/gameplay need. Defer a general solver, automatic interiors and universal vertical composition.

Sol should have freedom over helper names and serialization details. The required boundaries are one transform convention, one resolved contract per build, explicit relationships, asset-first presentation, and preserved tactical authority. Do not flatten every legacy subsystem into a new mega-generator or replace working pathfinding/LOS to solve presentation problems.

## 7. Acceptance criteria

- A real asymmetric asset's transformed working face agrees with its planned face at rotations 0–3; no test merely repeats the yaw formula under test.
- Rectangular/offset envelopes match independently transformed corners; rendered variants fit their approved bounds and required clearances.
- Every road opening coincides with its logical connector. Straight/T/cross joins remain visually continuous in all allowed rotations, with no duplicate visible road layer. Inspect close, overhead and oblique views with diagnostic overlays disabled.
- Assembly validation rejects incompatible socket pitch, unsupported open seams, missing required structure and blocked access. Intentionally open shelters and sealed exterior shells retain different contracts.
- A calibration change invalidates dependent certification or triggers revalidation. It never silently changes tactical occupancy.
- Generated → edit-copy → save/load preserves identity and placements, and preserves or explicitly revalidates deployment/access behavior. Missing dependencies fail visibly.
- Same seed, configuration and content revisions reproduce the same result. A small seed matrix covers all three identities; fallback and rejection counts remain visible.
- The integrated opt-in battlefield completes representative missions and replays deterministically before default rollout. Tactical metrics supplement actual play/visual review.
- Normal visible buildings, roads and equipment come from downloaded assets or approved assemblies of them. Every procedural visible-geometry exception is documented and deliberate.

## 8. Verification and limits

Executed on installed Godot 4.7.2:

| Test | Result |
| --- | --- |
| `asset_calibration_test.gd` | Pass, exit 0; 3,461 checks |
| `semantic_asset_catalog_test.gd` | Pass, exit 0; 2,323 checks; 315 confirmed, 32 procedural |
| `modular_environment_components_test.gd` | Pass, exit 0 |
| `structural_building_assembly_test.gd` | Pass, exit 0 |
| `coherent_layout_assembly_test.gd` | Pass, exit 0 |
| `coherent_road_streetscape_test.gd` | Pass, exit 0 |
| `semantic_district_generation_test.gd` | Pass, exit 0 |
| `coherent_layout_capture.gd` | Exit 0; produced 30 fresh captures over six identity/seed cases |
| Investigative spatial probe | Final run exit 0; reproduced F1–F3 measurements |

Visually inspected industrial seed 17 overhead/intersection and mixed-service seed 11027 overhead. The remaining captures were generated, not exhaustively reviewed. No full suite, stress batch, gameplay mission playthrough or performance benchmark was run; they would not resolve the present geometric findings. Performance concerns about repeated catalog construction/loading are hypotheses until profiled.

Godot emitted certificate-store errors. Initial test log paths also produced user-directory creation errors; captured stdout still contains completion summaries and all seven scripts returned 0. Subsequent probe/capture logs used absolute workspace paths. An intermediate revision of the investigative probe failed GDScript type inference; the probe was corrected and rerun. These were environment/diagnostic issues, not altered production tests.

Evidence retained beside this report:

- [Industrial seed 17 overhead](evidence/environment-2026-10-20/industrial_district-17-overhead.png)
- [Industrial seed 17 intersection](evidence/environment-2026-10-20/industrial_district-17-intersection.png)
- [Mixed-service seed 11027 overhead](evidence/environment-2026-10-20/mixed_service-11027-overhead.png)
- [Reproducible diagnostic script](evidence/environment-2026-10-20/spatial_probe.gd)
- [Final diagnostic output](evidence/environment-2026-10-20/spatial-probe-output.txt)

Run the diagnostic from the repository root with `godot_console --headless --path . --script res://docs/architecture/reviews/evidence/environment-2026-10-20/spatial_probe.gd`. It prints measurements; it is investigative evidence, not a replacement regression suite.
