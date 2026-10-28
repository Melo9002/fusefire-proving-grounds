# Independent review of Generation 2 follow-through

Date: 2026-10-25. Reviewed HEAD: `fb373e6`. Consultant assessment; no production changes made.

## Executive assessment

Sol has made substantial, relevant progress against the October 20 findings. Retain the current direction: imported assets, explicit assembly contracts, parcel planning, bounded candidate search, protected access, and a shared battlefield document. A replacement generator or a general scene-grammar framework is not justified by the evidence reviewed.

However, I would not accept the final certification report's closure of contract drift without qualifications. Some certification records certify current inputs automatically, the document resolver trusts certification flags, and certification signatures omit important assembly behavior. Editor identity also remains unstable under transforms. These are architectural boundary defects, not reasons to discard the useful implementation.

The appropriate status is **a substantially improved, bounded industrial opt-in with additional hardening required before expansion**. Visual quality, broad mission coverage, and unrestricted editing remain separate acceptance questions.

## Evidence and scope

Reviewed the supplied October 20 assessment/response and the twenty subsequent reports through final architecture certification, with targeted inspection of generation, contracts, document compilation, presentation, editor integration, and gameplay/replay tests. Reports are evidence of work and claimed results, not independent certification.

Inspected Sol's saved `evidence/secondary-road-task-7.1/industrial_district-17-overhead.png`: it shows connected orthogonal roads organizing occupied plots. It is an earlier supplied capture, not a fresh rendering of this HEAD or proof across seeds. I did not independently repeat the full visual matrix or broad generation suite.

Independent test logs are under `artifacts/test-results/independent-review-2026-10-25/`. Results are recorded below. Whole-test durations include setup and validation; they are not generator benchmarks.

## What is working

- **Original geometry defects:** independent road-opening, working-face and rectangular-envelope oracles are meaningful improvements over checking the implementation against itself. Canonical logical/presentation transforms address the original source-axis and rotation discrepancies.
- **Asset-first streets:** the normal road presenter uses imported geometry; diagnostic road boxes are explicit. The remaining derived canopy is disclosed rather than being mistaken for imported content.
- **Spatial intent:** parcel ownership, exact frontage, protected mission/access regions, and role-specific relationships give placement a reason beyond non-overlap. `environment_parcel_relationship_validator.gd` is appropriately bounded to actual recipes.
- **Bounded generation:** finite candidate budgets and deterministic candidate-local choices are practical for this project. An explicit buffer/fallback is preferable to silently accepting an invalid parcel. High buffer counts still indicate limited useful content coverage.
- **Shared lifecycle:** `generation_2_battlefield_builder.gd` and `battlefield_layout_document_compiler.gd` provide a common validation/compilation boundary. Replay stores the accepted document rather than assuming that a seed will reconstruct edited content.
- **Replay evidence:** `generation_2_replay_edited_map_test.gd` runs AI-controlled gameplay, saves/reloads the recording, and checks tactical agreement after each action. This is stronger than merely loading the battle scene.

## Findings and root causes

### 1. Certification does not consistently enforce an approved baseline — high priority

**Observed:** `industrial_equipment_assembly_catalog.gd:28` and `industrial_cargo_assembly_catalog.gd:32` construct contracts using current geometry hashes and calibration signatures, then mark them certified. A newly constructed contract therefore adopts changed input revisions automatically. This differs materially from a fixed reviewed baseline.

`battlefield_layout_document.gd:839` resolves certified-library entries using `certification_state == CERTIFIED` as validity. It does not consult `technically_valid` or execute the relevant assembly validator. `initial_environment_assembly_library.gd:8` also supplies unconditional technical-validity values for the shell and pipe entries.

The document's certified-assembly signature includes identifiers, role/completeness/state and component geometry/calibration revisions, but excludes component transforms, socket definitions, clearance, approved envelope, supported rotations and tactical effects. An assembly behavior change can therefore leave that dependency signature unchanged.

**Consequence:** rejecting an old document after an asset change is useful and implemented, but it is not equivalent to rejecting a newly generated document whose assembly has never been reapproved. The final report's F4 closure conflates those guarantees. Source inspection establishes the missing enforcement; this review did not mutate production assets to demonstrate an end-to-end bypass.

**Recommendation:** store approved assembly revisions independently of current source files. Resolve each assembly once against that baseline; invoke its substantive validator and reject invalid records. Fingerprint the behavior that affects placement, tactical compilation and presentation, not just the source assets. Keep technical validity, approved revision and owner visual approval separate. Avoid inventing a new registry framework: a small explicit resolved catalog is sufficient.

### 2. Editing transforms replaces identity while preserving old references — high priority

**Observed:** `battlefield_layout_document.gd:125` recovers placement IDs by a signature containing component, origin, elevation, rotation and variation (`:835`). A moved, rotated or re-varied placement receives a new ID. Old parcels, reservations and non-assembly relationships are retained with their old references. `tools/map_editor.gd:1066` uses this path.

**Consequence:** ordinary object editing is represented as removal plus addition, even when the user intends to edit the same object. A referenced occupant can leave dangling ownership/access relationships. Marking those records for revalidation does not repair identity. The replay test's successful addition of optional furniture does not cover this case. This is a source-derived finding; interactive move/rotate behavior was not independently exercised here.

**Recommendation:** preserve placement IDs through editor operations. Distinguish move/rotate/change-variant from delete/replace. Revalidate geometry and relationships after a transform; use explicit policy for genuine removal of a required occupant. Do not silently regenerate the map or discard constraints.

### 3. Validation repeats expensive dependency resolution — medium/high priority

**Observed:** document dependency validation (`battlefield_layout_document.gd:753`) checks assets while traversing placements, including repeated instances. `environment_assembly_contract.gd:89` reads geometry hashes from files; calibration signature construction reloads calibration/native-bound data. Each `_assembly_dependency()` constructs the initial library again, which itself builds catalogs and validates other records.

Sol's integrated report records roughly 19.8 seconds for initial generation/document/compilation and several seconds for subsequent validation or compilation. These are reported timings, not independently isolated benchmarks. This review's document and gameplay test durations also justify investigating lifecycle cost, but do not prove which operation dominates.

**Hypothesis:** repeated hashing, parsing and catalog construction contribute materially to latency. Profile before assigning percentages; search and tactical validation may also contribute.

**Recommendation:** introduce a per-operation resolved dependency snapshot. Hash and parse each unique dependency once, share results across validation/compilation, and retain invalidation when inputs change. Keep deep source/geometry certification at explicit authoring boundaries where appropriate. Do not solve latency by deleting validation or persisting an unchecked global cache.

### 4. Some test names and certification claims exceed their evidence — medium priority

**Observed:** equipment `validate()` (`industrial_equipment_assembly_catalog.gd:75`) derives socket alignment, but overlap and external termination are caller-supplied booleans. Negative tests supplying those booleans establish error propagation, not geometric detection.

The tactical gameplay test performs real actions and useful route/LOS checks, but also relocates units, increases attack range, resets action resources and sets enemy HP to one (`tests/generation_2_tactical_gameplay_test.gd:54–111`). Terminal completion relocates the actor to the approach. This is useful fixture-based integration coverage, not natural end-to-end traversal. The separate AI replay test provides genuine end-to-end evidence for its bounded Eliminate scenario.

**Recommendation:** retain these tests and describe their scope accurately. Add geometry-derived overlap/termination checks only where the contract promises them; otherwise identify those fields as authored assertions. Add at least one Terminal playthrough that reaches its objective through authoritative movement before claiming full natural mission certification.

## Architectural options and preferred direction

1. **Harden the current bounded pipeline — recommended.** Preserve the useful work and fix the trust/identity/cost boundaries. This is the lowest-risk route to a usable generator.
2. **Broaden into a hierarchical spatial grammar now.** Potentially useful for multi-building compounds, interiors and vertical composition, but adds rule authoring/debugging complexity before the current limited content set is fully enforced. Defer until concrete recipes demonstrate a need.
3. **Replace planning with a general semantic scene graph or AI-driven assembly.** Semantics can describe purpose and compatibility, but do not establish fit, support, enclosure or access. This would not independently solve the remaining defects and would add uncertainty to runtime generation.

Use a small hierarchy already compatible with the code: street network → parcels → reviewed assembly recipes → imported components. Keep explicit relationships for frontage, support, access and attachment. Let AI assist offline with proposed metadata/recipes; require deterministic validation and visual review before approval. The downloaded asset inventory should constrain which recipes are available. Missing compatible content should produce a deliberate fallback or an actionable missing-asset report, rather than improvised structures being labeled complete.

For roads, expand only with supported mesh families and reviewed transitions. The secondary boundary-reaching branch and elongated plots are useful incremental additions, not proof of a general city generator. Building orientation and access must continue to follow the street-facing contract.

## Implementation handoff to Sol

Priority order:

1. Enforce approved assembly baselines and substantive validation at the shared compiler boundary. Acceptance: change a source revision or assembly transform/socket/clearance without recertifying; both new generation and loading reject the affected certified assembly. Unchanged approved content still loads.
2. Carry stable placement IDs through edits. Acceptance: move/rotate/change variant on a referenced occupant; preserve identity, then either accept the valid arrangement or report the actual spatial violation. Deletion reports required-occupant loss explicitly. Save/reload/replay preserve the accepted result.
3. Profile cold and repeated generation, validation, compilation and battle/replay initialization separately. Deduplicate dependency work, demonstrate unchanged failure detection, and establish a practical latency target before adding more content.
4. Clarify certification/test language; add a natural Terminal traversal fixture and real geometry checks wherever those are promised.
5. Resume content growth: imported canopy replacement, another useful complete shell, and reviewed road termination/transition assets. Track functional parcel coverage and visual quality across representative seeds, not merely total approved asset count.

No general rewrite, production migration or removal of legacy mode is recommended. Keep the runtime opt-in while this work is completed. The user's alternative proposal should be compared against these concrete requirements and the substantial existing work, rather than judged by architectural elegance alone.

## Independent verification

All six selected tests completed with exit code 0:

| Test | Whole-test elapsed time |
| --- | ---: |
| `coherent_geometry_contract_test` | 10.26 s |
| `coherent_visual_envelope_test` | 0.45 s |
| `certified_socket_assembly_test` | 2.33 s |
| `battlefield_layout_document_test` | 75.19 s |
| `generation_2_tactical_gameplay_test` | 61.96 s |
| `generation_2_replay_edited_map_test` | 119.04 s |

The replay verified 35/35 actions and reproduced victory. The local Godot run emitted a root-certificate-store error; assertions and replay completion succeeded. No selected test failed or was skipped. The full suite, fresh visual matrix, interactive editor transform reproduction and production-asset mutation experiment were not run. Passing these tests does not invalidate the uncovered source-level gaps, and headless success does not establish visual correctness.
