# Generation redesign — T00 decision record

2026-10-25 · Baseline `fb373e6` · **Proposed defaults, awaiting owner acceptance.**

2026-10-26 update: the owner explicitly commissioned T01, accepting D1's stable-identity implementation scope. This does not authorize later tasks or imply human visual approval of content.

Authority: the owner authorized T00 documentation, not implementation of subsequent tasks. Work remains task-by-task. This record narrows the [architecture proposal](C:/Users/Blue/Documents/Codex/git/fusefire-proving-grounds/docs/architecture/reviews/2026-10-25-generation-redesign-feasibility-and-plan.md); it does not claim the proposal is approved.

## Necessary contracts

| ID | Recommended contract | Consequence |
| --- | --- | --- |
| D1 — Stable instances | Every placement carries a document-local persistent string ID independent of transform, component variant and array order. Move/rotate preserves it; duplication creates IDs and remaps copied internal references; deletion exposes broken required relationships. Preserve valid existing IDs. Allocate missing legacy IDs deterministically once during import. Generated IDs derive from stable slot/local identity; runtime instance paths namespace nested sources. | Fixes editor/reference drift. T01 changes identity end-to-end without implementing the future chunk library. |
| D2 — Source records | Separate chunk source and plot source; share placement/reference/transform records and persistence helpers. Use versioned JSON initially. Chunk: local instances, rectangular bounds, supported rotations, ports, clearances, tactical contributions, dependency references. Plot: map extent, fixed content, slots, connectivity/frontage requirements, mission reservations and population regions. | Chunks do not carry world deployments; plots do not duplicate chunk internals. No universal document full of unrelated optional modes. |
| D3 — Accepted output | Evolve `BattlefieldLayoutDocument` into the accepted resolved snapshot: stable world instances, exact leaf definitions/visual choices, transforms, bound mission data, content/compiler revisions and provenance. Compile `MapData` plus derived presentation records from that snapshot. Resolve dependencies once per operation; rendering does not select variants again. | One construction boundary and one runtime tactical authority. Source editing remains separate from accepted runtime output. |
| D4 — Tactical composition | Compile surfaces first, then explicit occupancy/effects, then traversal, mission binding and graph/LOS validation. Missing fields contribute nothing. Ground cannot erase an occupant. Compatible independent contributions must be order-independent; incompatible authored claims reject with source IDs. Use elevation-aware occupied/clearance volumes; distinguish floor-specific and whole-column reservations. | Replaces last-writer-wins behavior and X/Z-only occupancy. Preserve current combat meanings; specify field-level merge rules in T02 with regression oracles rather than inventing a generic dictionary merge. |
| D5 — Publication | Draft saving requires structural file validity, not a playable map. Technical validity, human visual approval and generator registration are separate facts bound to an exact revision/dependency fingerprint. Edits invalidate relevant approval. Registration requires substantive validation and actual owner visual approval. | Generated drafts never auto-certify. An approved chunk may contain fixed assets that are not independently eligible for random selection. |
| D6 — Scope and compatibility | Initial chunks have variable integer rectangular bounds, supported 90-degree rotations and integer tactical elevations; no arbitrary scaling/mirroring. Retain the existing coordinate convention. Keep current runtime presets during comparison. Import supported old documents explicitly without overwriting originals or inventing approval. | Supports the pilot without unrestricted packing/stacking. Preserve current replay behavior while its path remains supported; future snapshots require compatible content/compiler revisions, not indefinite replay compatibility across all future changes. |

These are behavioral contracts, not requirements for six new subsystems. Reuse existing classes where appropriate. Schema versions must change explicitly when compatibility changes; do not preassign version numbers before inspecting the affected reader/writer pair.

### Minimal relationship model

Keep working faces (meaning/direction), geometric sockets (measured attachments) and chunk ports (boundary/access obligations) distinct. Ports need ID, role/profile, local span/cells, normal, elevation, minimum width and required/optional/terminated state. Street content owns its carriageway and bundled public sidewalk; a parcel owns its apron beyond that interface. A sealed shell's visible door does not imply a traversable interior.

Nested approved content may be referenced acyclically and flattened before runtime. Begin with one nested assembly inside a chunk; defer general nesting depth and override machinery until a concrete need exists. Population may change only declared regions, not fixed source content.

## Proof content selected for authoring

This selection is a proposed pilot, not new certification. Existing asset files and component references were checked during T00.

| Proof | Existing material | Acceptance purpose |
| --- | --- | --- |
| Warehouse frontage | `city_kit_industrial/building-i`; module `industrial_shell_i`, assembly `city_industrial_shell_i`; reviewed paving | Exterior-only shell, facing and protected apron; start with a 20×20 allocation, confirm actual bounds/clearance during authoring. |
| Open cargo yard | `shipping-container-a/b/c` through `cargo_container`, reviewed paving | Fixed composition plus bounded cargo population; 20×10 candidate allocation. No derived canopy needed. |
| Machinery/service yard | `factory_pipe_receiver_unit`: `factory_kit/machine-connection-hole` and `pipe-large` | Service access and nested measured assembly; later regenerate it as an editable draft. |
| Pedestrian connection | Existing alley/paving vocabulary and reviewed furniture | Two usable access points; choose one content-driven rectangle outside the 10-cell road pitch. Exact dimensions depend on asset fit; do not stretch geometry. |
| Street family | `road_straight`, `road_intersection_t`, `road_crossroad` and their City Roads GLBs | Existing 10-cell street profile, sidewalk ownership and seam matching. Boundary exits only initially; no uncertified curves/end caps. |
| Vertical proof, later T12 | Existing industrial warehouse layout, surfaces, platform, roof and traversal content | Reuse at another origin/rotation; tactical access and per-building camera/floor behavior. |

Use two authored plots: a through-street industrial block and a yard/service-access arrangement. Start at 60×50 to isolate architecture changes from runtime-size expansion. Use one fixed authored environment for independent population. Initial mission proofs: Eliminate and Terminal. Reuse five fixed seeds per plot plus five holdout seeds for visual review; this is bounded evidence, not all-seed certification.

**Asset default:** imported geometry for the new pilot's visible structures/props. Existing calibrated adapters remain explicit. Base terrain and debug overlays are permitted; new substitute buildings/canopies are not silently fabricated. Legacy derived content stays available only in its existing compatibility/reference paths until migrated. An unavailable compatible asset changes or blocks the recipe.

## Unnecessary for the initial proof

Defer procedural road-graph planning (T17 decision only), general spatial grammars/WFC, polygon packing, unrestricted multistorey stacking, automatic interiors/roofs, arbitrary chunk overrides, a separate editor application and remote content services. Do not expand the asset library merely to fill a numeric quota.

## Retirement register — remove by proven replacement

| Current path / duplication | Intended survivor | Retirement condition |
| --- | --- | --- |
| Transform-signature identity reconstruction | Persistent placement IDs | T01 migrates edit/serialization callers; inference remains only where needed for old import. |
| Order-dependent `EnvironmentModuleMapWriter` mutation | Shared explicit compilation passes | Retired in T02: transactional shared writer; permutation/conflict, modular/frontage, gameplay and replay tests passed. See `tactical-compilation.md`. No second tactical writer. |
| Repeated spatial calculations and X/Z-only occupant reservations | Shared elevation-aware spatial queries | Retired in T03: shared geometry/support queries and explicit reservation scopes; intentional whole-column mission policy retained. See `spatial-placement.md`. |
| Live repeated asset/assembly resolution; flag-only certification | Frozen revisions and shared resolved context | T04 implemented: substantive validation, changed-content rejection and exact presenter records. See `revision-resolution.md`. Legacy render adapter retires after fixture migration. No new human approval. |
| Editor array-index identity and duplicated inspection/edit state | Stable-ID editor commands/session | T06 history/persistence and visual controls demonstrate parity. |
| Code-authored coherent recipes and central assembler orchestration | Published chunks, authored plots and bounded composition | T10–T11 equivalent content/gameplay/replay evidence; preserve useful recipes only as draft producers or small fixtures. |
| Legacy population orchestration | Population over an immutable established environment | T08 behavior parity plus compatibility review; do not copy the whole generator. |
| Warehouse-specific production constants/presenter branches | Reusable vertical content and common presentation | T12 access/camera/replay parity; preserve focused regression fixtures. |
| Temporary import/adaptation paths | Explicit supported compatibility boundary | T15 examines real callers, saves, resources and export references before removal. |

Do not delete downloaded assets, user saves, historical evidence or useful tests as generic cleanup. A temporary adapter needs a retirement trigger, not a permanent promise. Consolidation means fewer authorities and special cases, not a deletion target.

## Decisions needed before Set B

All remain **proposed**:

1. **Accept D1–D5 as the shared contracts.** Recommended: yes. Alternative: revising identity, authority or publication later risks rewriting editor and library work.
2. **Accept D6 and the bounded industrial pilot.** Recommended: yes—authored plots/chunks first, imported-first visible content, vertical proof later. Broader sizes/interiors/procedural roads add dependencies before the central workflow is demonstrated.
3. **Accept staged compatibility and retirement.** Recommended: retain current paths until parity, explicit imports without silent rewriting, no indefinite cross-version replay guarantee. Immediate removal risks regressions; permanent parallel paths defeat consolidation.

Acceptance of these defaults settles the planning gate only. The next task remains **T01**, requested separately; T00 does not authorize all of Set B.
