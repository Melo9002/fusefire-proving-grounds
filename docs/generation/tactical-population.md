# T08 — Tactical population over a fixed environment

2026-10-28. Strategy A implementation and technical proof. This does not register or visually approve the T07 chunks.

## Try it

Restart `tools/map_editor.tscn` (F6), then choose **Environment — Fixed Population**. Previous/Next seed or Regenerate keeps the authored environment and changes eight cover additions in three named yards. Use **Save populated battlefield**, **Reload saved seed**, **Play — Eliminate** or **Play — Terminal** in the right panel. Saved snapshots live at `tools/map_editor/layouts/population_<seed>.json`; reload compiles their recorded choices without rerunning population. Inspection transforms remain preview-only. An accepted population snapshot enforces its immutable base; use the source document to redesign that base.

The fixed source is `content/population/industrial_fixed.layout.json`; bounded rules are `content/population/industrial_population.json`. Both are editable data. The proof has two imported exterior warehouse shells, a continuous imported street, paved loading yards and a pipe/receiver assembly. Fixed deployments face the yards. The Terminal objective is in the east service area with a protected two-cell approach. Buildings remain exterior-only, and the sparse dressing is deliberately not a finished biome.

## Boundaries

`FixedEnvironmentPopulation` is the small data-loading/runtime adapter. `TacticalPopulationPass.populate(base, rules, seed, context)` is independent of chunk publication, registration, plot solving and procedural building assembly. It returns an accepted `BattlefieldLayoutDocument` and compiled `MapData`, or explicit diagnostics. The source object and its saved file are never mutated.

1. Validate and compile the authored base; reject missing mission binding or deployment repairs.
2. Read bounded regions (rectangular bounds, supported elevation, exact target count, explicit anchors and component/rotation/variant choices). No global scattering. At most 32 regions, 64 anchors and 16 choices each; the entire operation stops at 512 candidate attempts.
3. Establish mission reservations, existing spatial reservations and explicit whole-column access routes. Reuse canonical geometry/clearance queries and the reservation ledger. Apply legacy support/empty-cell/full-cover-spacing policy through the extracted shared `CoverPlacementPolicy`.
4. Seed and shuffle candidate choices deterministically, sorted by region identity. Allocate IDs from region/slot identity. Reject out-of-region footprints/envelopes, spatial conflicts, missing support and reserved access. No optional terrain/floor construction.
5. Apply candidate effects with the existing transactional `EnvironmentModuleMapWriter`. Run complete graph/mission compilation on the final document; reject failure instead of returning a partially valid map. This avoids a full graph rebuild for every candidate. Exhausted required counts reject explicitly.
6. Persist exact placements/variants/assets and dependencies in the existing document records. Population provenance stores its version, seed, rules, accepted choices, attempt count, base signature, fixed records and spatial/mission contracts. Compilation verifies this snapshot on play/replay; it does not regenerate population. Rendering consumes the existing resolved records.

The base signature includes the full source document; tests also compare fixed instance records and mission zones independently. The compiler rejects changed/missing fixed instances, changed accepted additions, changed base relationships/reservations/parcels, illegal regional choices and obstructed required routes. Population is not allowed to repair deployments after compilation. Metadata is a reproducibility/integrity contract, not a cryptographic trust boundary against an author who deliberately edits every field.

## Tactical intent and visual evidence

The two loading yards offer cargo LOS blockers and low, vaultable dumpster cover. Different seeds change positions, rotations and the mix of these behaviors. The front service region supplies an alternate lane between the fixed shells. Fixed street and side access remain open; the Terminal approach is reserved independently of nearby cover. This is a demonstrated variation mechanism, not a balance certification.

- [Seed 17 clean](../../artifacts/t08-17-clean.png), [tactical](../../artifacts/t08-17-tactical.png).
- [Seed 42 clean](../../artifacts/t08-42-clean.png), [tactical](../../artifacts/t08-42-tactical.png).
- [Editor controls](../../artifacts/t08-42-editor.png).

Tactical captures: cyan region edges, green protected routes, magenta mission/deployment cells, orange low cover and red full cover. Captures use the actual editor and shared presenter. Agent inspection observed coherent straight road alignment, intact shells and changes confined to the intended yards. The environment remains sparse; no interior, utility-network or aesthetic approval is claimed.

Measured editor rebuilds for the captured 60×50 proof were approximately 6.8–7.0 seconds on this machine, including validation and presentation. This remains a visible synchronous pause, not a solved general performance budget. Pure camera movement does not regenerate the map.

## Verification

- `tests/tactical_population_test.gd`: seeds 17, 42 and repeat 17; immutable source/fixed records; exact deterministic accepted output and tactical cells; changed tactical cover across seeds; bounded search; save/load compilation; unsupported floors, outside anchors, route and mission intrusion; modified/missing/malformed snapshot rejection.
- Actual Eliminate battle completed; saved replay reloaded and verified **47/47 actions**, including movement and combat. Terminal battle initialized with its protected objective. Terminal completion/balance was not certified.
- `tests/tactical_population_capture.gd`: two seeds, clean/tactical/editor captures and exact editor save/reload assertions; graphics-only, explicitly excluded from automated full runs.
- Shared writer, elevation, battlefield document lifecycle and chunk publication suites passed. A temporary comparison against the pre-extraction legacy generator matched cells/cover/movement/container/traversal data for 12 maps (four seeds at all three legacy sizes).
- The first smoke run found an existing stable-ID selection regression: the inspector used the custom layout even while displaying another map. Selection now resolves IDs from the displayed layout outside composition mode. The diagnostic regression retains all 11 assertions and passes.
- Final Ironclad smoke: **10 passed, 0 failed, 0 skipped**. Full exhaustive suite was not run.
- Logs are local `artifacts/t08-*.log`. Existing certificate-store and restricted editor-settings diagnostics remain environment limitations. Temporary probe scripts and logs are not production dependencies.

## Enxugar and compatibility

Extracted the reusable legacy cell/support/adjacent-cover policy; the old generator calls it too. No copied population generator, second map writer, alternate persistence layer or new asset registry. The legacy orchestration remains because its building/container/formation generation is still used by supported presets and replay paths; T08 does not replace those responsibilities. Retire it only when those consumers migrate with parity evidence. The small fixed-environment adapter should survive as an independent Strategy A entry point even when T09–T11 chunk composition arrives.

The owner accepted the authoring usability direction and explicitly commissioned T08. This authorizes progressing the independent strategy, not inventing publication approvals for the seven draft chunks. Gate D's technical proof is complete once the listed checks pass; owner playtesting and visual preferences remain separate. No poles/wire network, arbitrary stacking, plot solver, or library expansion was added.
