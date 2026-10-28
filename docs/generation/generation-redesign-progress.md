# Generation redesign — progress ledger

Updated 2026-10-26. Baseline: `fb373e6` plus uncommitted T01/T02/T03/T04 and playtest fixes. Execution is **one task at a time**.

Current decisions: [T00 defaults](C:/Users/Blue/Documents/Codex/git/fusefire-proving-grounds/docs/generation/generation-redesign-decisions.md). Owner authorized T01 through T05 explicitly. Later tasks remain separately authorized.

## Task order and gates

| Set | Order / dependencies | Status |
| --- | --- | --- |
| A | T00 → owner acceptance of contracts/scope | Complete; owner proceeded to T01 |
| B | T01 → T02 → T03 → T04 → fresh review | T01 complete: seven selected suites passed. T02 complete: five selected suites passed. T03 complete: eight selected suites passed. T04 implemented: ten selected suites passed; Gate B source/negative-test self-review complete (not independent signoff) |
| C | T05 → T06 → T07 → usable-authoring/owner visual gate | T05 source/store implemented; T06/T07 not started |
| D | T08 → independent population proof | Implemented; technical gameplay/replay proof passed; owner playtest remains |
| E | T09 → T10 → T11 → architectural and visual/playability gate | Not started; T09 needs C; T10 also needs T08 |
| F | T12 and T13 → vertical/modular convergence gate | Not started; default sequence after E; T13 technically needs C |
| G | T14 → T15 → T16 → release/continued-opt-in decision | Not started; integrated full scope needs E/F |
| Optional | T17 analysis after accepted E or later | Not commissioned |

## T00 completion

- **Scope:** planning only. Checked task instructions, current identity/edit path, persistence versions, tactical writer, spatial reservation interface, assembly dependency resolver and proposed asset IDs/files. HEAD is unchanged from the investigation baseline.
- **Outputs:** decision record with six necessary contracts, pilot content, three owner decisions and retirement register; this ledger with dependencies and baseline evidence.
- **Verification:** documentation/reference checks only. No Godot tests or visual capture runs repeated; existing results below are reused, not new T00 passes.
- **Code/consolidation:** no production code changed; no commits, pushes or deletions. Existing untracked reports/artifacts and import sidecars preserved. Retirements are proposed, not performed.
- **Open:** owner acceptance of the three decisions; pilot dimensions beyond established examples require authoring validation. No new visual approval granted.
- **Next:** T01 once decisions are accepted and that task is requested. Recommended model/effort: Astra Medium for the identity/serialization/reference boundary; this is a project judgement, not a claim that Light cannot do it. No model switch performed.

## T01 implementation — 2026-10-26

- Shared placements now carry persistent IDs and an identity-preserving `copy()`. Capture allocates missing IDs deterministically; document reconstruction preserves them. An optional persisted allocation high-water mark prevents reuse after deletion/reload; old schema-2 envelopes/document schema-1 files remain readable without rewriting their IDs. The legacy placement importer gains IDs through initial capture and retains legacy provenance.
- Move, rotate and Apply variant preserve identities. The editor selects by ID, offers Duplicate selected, and rejects required-reference deletion transactionally. Document-level group duplication assigns fresh IDs and remaps typed internal relationship references; external parcel ownership is deliberately not cloned. Optional references to deleted objects are removed.
- Removed transform-signature identity matching from normal edits. Kept the documented one-time bridge from the existing generator's signature-based plan into document IDs; retire it when that producer's plan representation is migrated. No parallel editor identity system introduced.
- Updated existing fixture copy helpers to preserve identity; assertions retained. New `placement_identity_test.gd` exercises transform/reorder, ownership/access references, group duplication, optional/required deletion, allocator persistence, legacy import, current-format missing-ID rejection and actual editor command/load handlers through a headless harness.
- Passed (exit 0): `placement_identity_test`, `battlefield_layout_lifecycle_test`, `map_editor_layout_store_test`, `parcel_spatial_contract_test`, `parcel_functional_relationship_test`, `generation_2_replay_edited_map_test` (35/35 actions, victory), and `battlefield_layout_end_to_end_test` (industrial, mixed-service and commercial). The last suite's successful workspace run is recorded in `artifacts/t01-end-to-end-workspace.log`.
- Reproduction: set `$env:FUSEFIRE_TEST_OUTPUT_DIR = Join-Path $PWD 'artifacts'`, then `godot_console --headless --path . --log-file artifacts/t01-<name>.engine.log --script res://tests/<name>.gd`. Logs: `artifacts/t01-*.log`. `git diff --check` passed. Initial parser inference errors were corrected; the new test also exposed inadequate duplicate spacing, corrected to account for the visual envelope. The first end-to-end invocation omitted the output environment variable and failed to save under restricted `user://`; it was stopped and rerun with workspace output, without changing assertions. Existing root-certificate-store warnings persist. Initial editor import could not save user editor settings; no successful full editor scan is claimed.
- Limits: no fresh rendered UI inspection or full suite run. Headless command tests do not establish button layout or visual quality. Multi-selection UI and undo remain T06; the shared duplicate API accepts multiple IDs now. No commits/pushes; unrelated untracked work retained.
- Next: T02 only when requested. Suggested model: Astra Medium for explicit tactical merge rules; Sol is a reasonable budget-conscious implementation option against those rules. No model switch performed.

## T02 completion — explicit tactical compilation

- **Change:** replaced insertion-order mutation in the existing writer with transactional surface/effect/traversal passes. Omitted properties no longer reset other contributions; ground cannot reopen blocking cells. Conflicting same-layer claims/surface declarations and missing support/surfaces/endpoints reject explicitly. The document compiler and both generation callers propagate errors. Direct test/capture callers now report them too.
- **Contract:** [field rules and intentional behavior changes](C:/Users/Blue/Documents/Codex/git/fusefire-proving-grounds/docs/generation/tactical-compilation.md). Restrictions accumulate; implicit authored overrides are unsupported. No parallel writer. MapData, vault semantics and runtime gameplay interfaces retained. X/Z reservation defects remain T03.
- **Passed (exit 0):** `modular_environment_map_writer_test`, `modular_environment_components_test`, `coherent_asset_first_frontage_test`, `generation_2_tactical_gameplay_test`, `generation_2_replay_edited_map_test` (35/35 replay actions). The new writer suite covers all six effect permutations, missing/conflicting contributions, atomic failures and document-compiler error propagation; existing fixtures cover vertical surfaces, street rotations, missions and save/load/replay.
- **Reproduce:** set `$env:FUSEFIRE_TEST_OUTPUT_DIR = Join-Path $PWD 'artifacts'`; run `godot_console --headless --path . --log-file artifacts/t02-<name>.engine.log --script res://tests/<test>.gd`. Output logs: `artifacts/t02-writer.log`, `t02-components.log`, `t02-frontage.log`, `t02-gameplay.log`, `t02-replay.log`. `git diff --check` passed. The new test uses the `modular_` prefix for existing generation-suite discovery.
- **Diagnostics:** the first frontage run exposed a new test-message formatting error (array supplied directly to `%`); corrected and rerun without weakening assertions. Final runs retain only the existing root-certificate-store warning. No failed assertions remain in the selected suites.
- **Enxugar:** the old per-placement reset/mutation path is removed, not retained as a fallback. No new tactical data model or writer. Existing presets remain comparison fixtures as planned.
- **Limits:** no full suite or fresh visual captures/UI inspection; capture helpers were adapted but not executed. These headless passes do not certify visual quality. Prior uncommitted/untracked work preserved; no commits or pushes.
- **Next:** T03 when requested: elevation-aware spatial contracts. T04 and later scopes remain unstarted.

## Baseline evidence to reuse

At `fb373e6`, earlier independent runs passed: `coherent_geometry_contract_test`, `coherent_visual_envelope_test`, `certified_socket_assembly_test`, `battlefield_layout_document_test`, `generation_2_tactical_gameplay_test`, `generation_2_replay_edited_map_test` (35/35 replay actions), `modular_environment_components_test`, `map_editor_layout_store_test`, and `industrial_warehouse_vertical_slice_smoke`. The local root-certificate-store diagnostic did not prevent completion. These establish bounded regressions, not redesign acceptance.

- [Independent follow-up and six-test results](C:/Users/Blue/Documents/Codex/git/fusefire-proving-grounds/docs/architecture/reviews/2026-10-25-independent-generation-2-follow-up.md).
- [Feasibility report, additional tests and limitations](C:/Users/Blue/Documents/Codex/git/fusefire-proving-grounds/docs/architecture/reviews/2026-10-25-generation-redesign-feasibility-and-plan.md).
- [Boundary diagnostic output](C:/Users/Blue/Documents/Codex/git/fusefire-proving-grounds/artifacts/architecture-redesign-research/boundary-probe.log): ground-after-obstacle clears blocking; distinct elevations conflict. Diagnostic execution success is not behavioral acceptance. Temporary artifacts may not exist in another checkout; the source findings and reproduction description are in the feasibility report.
- [Road layout baseline](C:/Users/Blue/Documents/Codex/git/fusefire-proving-grounds/docs/architecture/reviews/evidence/secondary-road-task-7.1/industrial_district-17-overhead.png).
- [Gameplay frontage baseline](C:/Users/Blue/Documents/Codex/git/fusefire-proving-grounds/docs/architecture/reviews/evidence/generation-2-tactical-gameplay-task-6.2/generation-2-seed-17-frontage.png).
- [Imported cargo baseline](C:/Users/Blue/Documents/Codex/git/fusefire-proving-grounds/docs/architecture/reviews/evidence/generation-2-final-task-7.3/shipping-container-family-oblique.png).

Captures are supplied historical evidence, not new captures or owner approval of the redesign. Existing headless tests do not establish visual correctness. Run the smallest relevant suite when implementation changes its contract; broaden at the agreed integration gates.

## Future completion-entry format

Task / baseline → behavior changed → acceptance results and exact commands → visual evidence/approval → removed or consolidated paths → retained adapters and retirement triggers → unresolved issues → next task and suggested model/effort. Keep entries short; link detailed logs instead of repeating them.

## Playtest interruption — warnings and scene teardown (2026-10-26)

- T03 remains paused; no elevation/reservation redesign was implemented. User separately authorized fixing the reported warnings and runtime errors.
- Cleaned shadowed locals/parameters, unused declarations, explicit enum conversions and intentional truncating integer divisions in the generation/document/editor paths. Persisted field names and public document methods remain unchanged. Asset Lab warnings were fixed in the preceding small patch.
- Movement presentation now checks scene membership/deletion state at asynchronous boundaries and before writing global transforms. Removed action services return `battle_unavailable` instead of dereferencing a missing SceneTree. Regression tests remove a moving actor during presentation and validate an action service before attachment and after removal; normal attached behavior and authoritative HP/AP are also checked.
- Passed (exit 0): tactical_action_presenter_test, tactical_action_service_test, action_camera_director_test, overwatch_reactions_test, placement_identity_test, battlefield_layout_document_test, modular_environment_map_writer_test, coherent_mission_reservation_test. Logs: `artifacts/warnings-*.log`. Use `godot_console --headless --path . --debug --log-file artifacts/<name>.log --script res://tests/<name>.gd`, with `FUSEFIRE_TEST_OUTPUT_DIR` pointing to repository artifacts for save tests.
- Final `--debug --check-only` checks of battle_controller, map_editor, asset_lab, placement_identity_test and modular_environment_map_writer_test emit no GDScript warnings; ordinary check-only had not exposed the warning set. No warning suppression was added. `git diff --check` passed.
- Limits: no manual reproduction of the user's exact playtest sequence or full-suite run. Root-certificate-store diagnostic remains unresolved; the existing Overwatch test itself also reports a test-local `seed` naming warning. An investigative editor scan could not save sandbox-external editor settings. No commits/pushes.


## T03 completion — elevation-aware placement (2026-10-26)

- **Scope:** resumed on the owner's explicit request. Shared `EnvironmentSpatialQueries` now supplies canonical points/footprints/envelopes, height intervals, volume/clearance intersections and support/headroom queries. Layout, ledger, relationship validation, document/editor acceptance and the existing writer use it. The old X/Z-only occupancy dictionaries and duplicate ledger envelope math are removed.
- **Contracts:** [Spatial placement](C:/Users/Blue/Documents/Codex/git/fusefire-proving-grounds/docs/generation/spatial-placement.md). Floor-local occupancy/clearance and explicit whole-column mission scope; supported ground/elevated surfaces; two-cell minimum floor headroom; unsupported edits reject before state mutation. Platform/walkway surface declarations no longer reserve fictitious solid columns. Legacy scope defaults preserve whole-column protection. No new approvals or publication state are inferred.
- **Intentional corrections:** moved loading-yard machinery one cell left to clear cargo access and vertical-works machinery one cell left to clear the platform. Corrected the old ledger's asymmetric visual/cell comparison to the canonical cell-centered convention. Document support validation now rejects before effect compilation; the T02 negative assertion names the earlier support error. No still-valid assertions were weakened.
- **Passed (exit 0):** `modular_elevation_spatial_test`, `modular_environment_map_writer_test`, `placement_identity_test`, `coherent_geometry_contract_test`, `coherent_visual_envelope_test`, `modular_environment_components_test`, `coherent_mission_reservation_test`, `generation_2_replay_edited_map_test` (35/35 actions). Final targeted editor/spatial debug parser checks are warning-free. `git diff --check` passed.
- **Reproduce:** set `$env:FUSEFIRE_TEST_OUTPUT_DIR = Join-Path $PWD 'artifacts'`; run `godot_console --headless --path . --log-file artifacts/t03-<name>.engine.log --script res://tests/<name>.gd`. Logs: `artifacts/t03-<test>.log`, `artifacts/t03-replay-final.log`; parser logs: `artifacts/t03-editor-parse.log`, `artifacts/t03-spatial-parse.log`. Use `--debug --check-only` for warning scans, not interactive-debug runtime tests.
- **Diagnoses during iteration:** initial modular fixture failures exposed the two genuine intersections above. A later rotated equipment-fixture failure exposed the cell-center mismatch, fixed in the shared query. The new test initially had inferred-variable parser errors; fixed with explicit types. Its debug run entered an interactive debugger loop and was stopped; subsequent checks used noninteractive runtime execution. The existing root-certificate-store diagnostic remains.
- **Limits:** no full suite or fresh rendered inspection. Existing missing envelopes are not magically measured; default one-cell occupancy is an explicit legacy reservation, not a geometry certificate. The source support lookup targets the flat-base pilot; runtime compilation checks actual MapData. General stacking/basements/polygon packing remain outside scope. Earlier uncommitted work preserved; no commits/pushes.
- **Next:** T04 when requested. Its dependency audit must include the new spatial extents and reservation semantics; then the planned Set B review after T04.


## T04 implementation - 2026-10-26

- **Contract/review:** [Revision resolution and Gate B](revision-resolution.md). Frozen compatibility revisions, per-operation resolver, substantive validation and exact presenter choices. No new human approval or automatic refresh.
- **Enxugar:** retired document/presenter live selection, flag-only document certification and live legacy-signature reconstruction. Shared identity allocator; no second registry/writer. Direct-render legacy adapter has an explicit retirement condition.
- **Verification:** ten selected suites passed, including new revision negatives and T01/T02/T03 regression oracles; replay 35/35 actions. Logs and limits in linked contract. No full-suite or visual-certification claim.
- **Intentional compatibility change:** old cargo without its current assembly binding rejects. Historical example stays unchanged; test verifies rejection and preservation. Current documents still round-trip and compile.
- **Next:** owner review, then T05 when commissioned. Gate B self-review recorded; independent signoff remains distinct. No commits/pushes.


## Playtest follow-up - placement preview and latency

Owner reported obstructed duplication and slow rotation/generation. Existing asset move/rotate/duplicate now use a cancellable mouse preview with atomic validated confirmation. No wall drawing, new content library, undo system or additional T-task scope. Per-candidate/per-parcel catalog reconstruction was removed from current generation/capture/validation paths. See [composer guide](map-editor-composer.md) for controls, measured phases, captures and six selected regression suites. Existing work remains uncommitted.


## T05 implementation - 2026-10-26

- **Scope:** [Local chunk sources and named drafts](chunk-source-drafts.md). Stable shared placement records, rectangular/vertical bounds, ports, explicit tactical declarations, clearances and dependency pins; no battlefield mission binding. Structurally sound incomplete/stale drafts save/load independently of publication/play gates.
- **Enxugar:** shared `GenerationJsonStore` parsing/read/temporary-write infrastructure now serves both stores. Shared placement serialization and allocator; no second tactical compiler or approval registry.
- **Import:** explicit, diagnostic and non-destructive. Preserve existing IDs/pins; deterministically assign only missing legacy IDs. No auto migration, source rewrite or approval.
- **Verification:** chunk source/store tests, map-store compatibility, identity and revision negatives passed; parser checks and diff check passed. Replay passed with 35/35 actions verified. Root-certificate-store and restricted user editor-settings diagnostics remain environment issues.
- **Boundary:** T05 has no named-draft UI yet; T06 owns that integration. T07 owns full local contribution/port compilation and publication validation. No commits/pushes.

## T06 implementation - 2026-10-27

- **Scope:** [Chunk authoring editor](chunk-authoring-editor.md). Existing Map Editor gains a distinct chunk workspace backed by a stable-ID session: undo/redo, duplicate/delete, snapped transforms/elevation, named drafts, searchable component/downloaded-asset/draft gallery and rendered previews, bounds/ports, shared geometry diagnostics and spatial overlays.
- **Draft boundary:** incomplete/overlapping sources remain editable/saveable; raw assets do not acquire tactical behavior or approval. Saved draft insertion is an independent flattened copy. Broken references/conflicting dependency pins reject insertion explicitly; failed open preserves session state. No publication or runtime certification added.
- **Enxugar:** authoring selection/history never use placement-array indices; source persistence, identity allocation, asset calibration, module transforms, spatial checks and visual resolution are shared with existing services. No separate app, calibration catalog, tactical writer or registration system. Existing battlefield composer stays only for the current runtime migration/comparison path, with its controls hidden in chunk authoring.
- **Verification:** new session and actual UI workflow suites passed; rendered captures inspected. Existing chunk-store, map-store, pending-preview, identity and resolution-context suites passed. Actual Map Editor scene startup passed in a graphics run. Evidence/limits and owner playtest steps are in the guide. No full-suite or aesthetic-certification claim.
- **Environment:** initial debugger-exit crash followed a script parse failure; script errors were fixed and final checks ran without the debugger. Existing certificate-store diagnostic persists. No production gameplay changes, commits or pushes in this task.
- **Next:** owner hands-on authoring check; T07 only when commissioned. Raw-asset tactical/dependency resolution and full contribution/port publication validation remain explicit T07 work.

## T06 playtest follow-up — chunk duplication (2026-10-27)

The owner reported duplication was unusable in chunk authoring. Copies were created at the same position with no explicit success guidance; activated buttons retained focus and could consume arrow keys as UI navigation. Duplicate/Delete now sit near the top of the scroll panel. Duplicate identifies the new selected copy and explains how to move it; no-selection attempts give an actionable message. Button activation and gallery/instance selection return keyboard focus to construction controls. The existing battlefield layout was not modified.

The workflow regression now focuses the actual Duplicate button, activates it, sends a viewport arrow-key event, and verifies only the copy moves. Headless and rendered runs passed (`artifacts/t06-duplicate-focus.log`, `artifacts/t06-duplicate-rendered.log`); updated capture inspected. Existing certificate-store diagnostic remains.

## T06 usability follow-up — mouse construction (2026-10-27)

- Replaced immediate-copy UI with shared mouse previews for adding, moving and duplicating. Click/Enter places; Escape/Cancel preserves source. Rotation/height buttons and shortcuts apply to the preview; precise fields reflect preview coordinates. Confirmation uses stable-ID commands; duplication plus positioning is one undo step.
- Browse / Selected / Chunk details tabs separate common placement from dimensions/ports. Raw downloaded assets remain available; no wall-drawing or publication scope added.
- Session and workflow regressions passed, including mouse motion, cancelled move/duplicate, preview-only rotation/elevation, stable identity and undo/redo. Rendered capture inspected (`artifacts/t06-mouse-preview.png`). See updated authoring guide for controls and test limits. Graphics run logged a shader-cache write error as well as the existing certificate-store diagnostic; neither is claimed fixed.


## T07 implementation - 2026-10-27

- **Status:** implementation and seven data proof candidates ready for review; **Gate C pending owner hands-on acceptance and explicit content approval**. Zero production approvals/registrations.
- **Contracts/UI:** [Publication guide](chunk-publication.md). Separate saved-source validation, immutable revision/evidence, explicit owner review and registration. Exact resolved visuals; stale source/dependencies/evidence exclude eligibility. No automatic approval.
- **Content:** frontage, loading yard, service yard, alley connector, straight/T/cross streets using downloaded assets. Rectangular dimensions and measured port profiles; tactical lanes/cover are intentions, not combat certification. [Review evidence](../architecture/reviews/2026-10-27-industrial-chunk-publication-review.md).
- **Enxugar:** proof compositions are JSON, shared writer handles explicit contributions, shared presenter renders resolved review records. Keep coherent runtime recipes and legacy composer only until T09-T11/T15 migrate their consumers; no premature deletion or parallel tactical writer. Immutable historical records remain auditable.
- **Verification:** publication negatives and seven candidates, rendered owner-workflow fixture, 21 current captures, writer/elevation/source-store/session/editor regressions passed. Replay 35/35 verified actions. No full-suite claim. Root-certificate/editor-settings environment warnings remain. Initial test-selection defect and UI sizing/reference-cycle defects corrected; final rendered workflow zero failures.
- **Next:** owner exercises Gate C. Plan utility corridors and post-assembly poles/wiring with plot/composition work; not an unrequested T07 network/drawing implementation. Existing chunk eligibility API is ready for later generator integration; current runtime generator has not silently migrated.


## T07 owner follow-up: discoverable saved chunks

Added top-level Browse saved chunks, category filters, natural-name matching, empty-result guidance and hidden-selection clearing. Saved chunk selection previews without arming placement; opening versus inserting remains explicit. Default drafts stay listed when editing industrial examples. Headless workflow regression passed, including four new browser checks and existing placement/history/persistence checks. Rendered evidence: artifacts/chunk-browser-saved.png. No publication approvals changed.


## Owner follow-up: discard confirmation

Open name, Open selected draft and New now share a discard confirmation for unsaved work or an active placement preview. Keep editing preserves the session; confirmation uses the originally requested destination. Invalid loads remain transactional even after consent: current work is retained. Saved files are never deleted by discard. Focused workflow tests cover cancel, confirm, failed destination and New, alongside existing authoring checks.


## T08 implementation — 2026-10-28

- **Scope:** [Independent tactical population](tactical-population.md). Immutable authored document + bounded regional choices → existing accepted document/compiler. Fixed industrial data proof, exact seeded additions, mission/access/support protection, explicit exhausted/rejected output. Editor preset with save/reload and Eliminate/Terminal play entry points.
- **Evidence:** deterministic seeds 17/42/repeat17, source invariance, negative contracts, round-trip, real combat and 47/47 replay actions passed. Two clean/tactical capture sets inspected. Terminal initializes; terminal completion and balance are not certified.
- **Enxugar:** extracted cover placement policy used by legacy and new strategies. No second compiler/persistence/registry. Retain legacy orchestration until its distinct supported presets and replay obligations migrate. Fixed source data is authoritative, not the investigative builder under artifacts.
- **Gate:** owner usability feedback and explicit T08 commission authorize Strategy A progress. No T07 content approval was fabricated. Gate D technical strategy proof demonstrated independently of chunk generation; owner playtesting remains.
- **Pre-push follow-up:** smoke identified an inspector regression from stable-ID migration; fixed displayed-layout selection and preserved all diagnostic assertions. Temporary evidence/probe outputs and external reference downloads stay local; source, authored content and original review captures are versioned.

Final pre-push Ironclad smoke: **10 passed, 0 failed, 0 skipped** (2026-10-28); original failure diagnosed and fixed, not waived.
