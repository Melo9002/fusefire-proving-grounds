# T10 — Deterministic authored-plot composition

2026-10-28. Implements selection and accepted-snapshot compilation; Gate E and owner playtesting remain outstanding.

## User workflow

In **Map Editor → Author — Plot Authoring**, open either industrial plot. After the required chunk revisions have been genuinely reviewed and registered in Chunk Authoring:

1. **Pin registered streets** explicitly assigns the current eligible street revision to the plot. It cannot register or approve anything.
2. Set **Seed** and **Budget**, then **Compose registered battlefield**.
3. Inspect the composed preview. **Save composed battlefield** writes the common layout format under `tools/map_editor/layouts/`. Saving revalidates with a fresh operation context, so an old preview cannot conceal later dependency changes.
4. **Back to plot** restores source editing. Source edits discard the accepted preview. Draft saving remains separate from accepted battlefield saving.

The production library currently has no eligible approved revisions. Generation therefore reports missing registered content or revision pins. No production approval was fabricated. Automated proof uses an isolated library under ignored `artifacts/t10-fixture-*`, with explicitly synthetic review records; those records never enter the production index.

## Selection and bounds

`AuthoredPlotComposer` consumes `EnvironmentPlotSource`, resolves only requested chunk IDs through the existing publication index, and uses `PlotFeasibility` for actual dimensions, supported rotations, required ports, frontage, street ownership and active-mission reservations. A matching label/profile cannot substitute for matching world-space geometry.

Required slots precede optional slots. Within each group, fewer feasible candidates precede larger rectangles, with stable ID as the final tie-break. Candidate ranks derive from seed + slot ID + exact candidate/revision data. Dictionary/file enumeration order does not determine selection. Adding unrelated registered content does not perturb a slot.

Depth-first search can backtrack after a failed complete compilation/population attempt. Each branch and complete evaluation consumes the explicit attempt budget: default 64, maximum 128. Exhaustion returns diagnostics and no accepted document. A required slot never becomes an empty lot. Optional omission is an explicit search alternative. This is bounded exhaustive search over the filtered choices, not a wall-clock timeout or procedural road planner.

The pilot currently has one compatible registered-content shape per required slot. Its seed variation therefore primarily comes from population; additional compatible published chunks can increase slot variety without adding code recipes. The two authored plots already produce distinct world arrangements from the same small library.

## Shared accepted snapshot and compiler

The existing `BattlefieldLayoutDocument` remains the accepted output. Its `provenance.composition` stores the versioned plot source, exact selected slot/street IDs, immutable chunk revision IDs, transforms, search count and compiler implementation fingerprint. Population records its existing exact additions and rules. No runtime random chunk selection occurs during load or replay compilation.

Composed documents use **resolution contract 2**; existing module-only documents keep contracts 0/1. Pre-T10 readers reject contract 2 instead of silently dropping chunk content. Removing composition provenance from such a document also rejects. Plot source schema 2 adds explicit T08-shaped population rules. Schema-1 plots remain readable without modification and mean no population regions; opening one does not silently rewrite it.

`PlotCompositionSnapshot` resolves and verifies each unique selected revision once per operation through the existing library. It reconstructs exact local records, applies canonical transforms, namespaces leaf identities as `chunk:<slot-or-street-id>/<local-id>`, and converts local explicit tactical declarations to world coordinates. Raw downloaded decoration keeps its frozen calibration and chunk transform; ordinary components keep the existing resolved visual records.

The shared `BattlefieldLayoutDocumentCompiler` combines all chunk/component surfaces, effects and traversal links in **one existing writer transaction**, then validates bound missions, access and the global graph. No second tactical writer, synthetic component registry or chunk-specific battle renderer was introduced. The existing presenter gained the missing raw calibrated asset branch. Changed/unapproved/stale revisions and changed composition compiler contracts reject on fresh load. Mission repair is not accepted for composed output.

Population reuses `TacticalPopulationPass`; its provenance now retains whether the immutable base was authored or generated. Both plots explicitly declare a small cargo-staging region, with bounded anchors and choices. For this pilot these are plot-owned open areas outside immutable chunk rectangles; overlapping chunk-space permission rejects conservatively. This does not yet authorize populating interior spaces within a chunk. Reservation scopes and mission cells remain protected. Arbitrary extra placements, removal of population provenance, or expanding the recorded rules beyond plot permission reject.

## Reuse and retirement

- Reused canonical rotations, shared dimensional queries, actual port/profile matching, plot feasibility, publication index/resolver, accepted document/store, tactical compiler, population policy and presenter.
- The older parcel search enumerates hardcoded recipe/frontage alternatives and does not support global backtracking. The new composer uses the same bounded deterministic principles without copying its recipe dispatch. New plot composition does not call the old assembler or template dispatcher.
- Keep `CoherentEnvironmentAssembler` and its candidate/relationship dispatch only for still-supported legacy/reference runtime presets. T11 must migrate entry-point consumers and demonstrate gameplay/replay parity before removing that adapter; T15 performs the final caller audit. No obsolete path was deleted ahead of its replacement obligation.

## Evidence and limitations

`tests/plot_composition_test.gd` exercises real registered-fixture compilation for both plots, repeat-seed snapshots, source-order independence, revision reuse, shared-store round trips, active Terminal binding, geometry rejection, budget exhaustion, backtracking, missing/altered chunks, population tampering, compatibility enforcement, and stale revision rejection for both new generation and saved output. Synthetic review input is confined to disposable test storage.

`tests/plot_composition_capture.gd` is graphics-only and explicitly excluded from the ordinary headless suite. It renders both plots through the shared presenter and labels its evidence **not owner approved**. Captures: `artifacts/t10-through_street_industrial.png` and `artifacts/t10-yard_service_access.png`.

The rendered proof shows a continuous street and sidewalks, intact warehouse frontage, rotated service/loading layouts, and additions confined to the declared staging areas. It remains sparse pilot content, not a visual-quality or tactical-balance certificate. T11 still owns normal gameplay entry integration and complete composed-map replay/playability demonstrations. Existing T08 gameplay/replay checks remain relevant regression evidence, not proof of T10 gameplay completion.

## Deferred owner playtest checklist

When you have time, ask for the T10 checklist. Start by reviewing the actual chunk revisions, then:

- Open each plot, pin eligible streets, compose and verify the warehouse doors/aprons face their intended access.
- Compare seeds 17 and 42: fixed streets and chunks remain intact; staging cover choices can vary within the declared region.
- Inspect curb/sidewalk seams, rotated props and open approaches from opposite and overhead views.
- Save the accepted battlefield, return to source editing and check that draft edits do not masquerade as changes to the saved snapshot.
- Try a too-small slot, wrong frontage target and tiny search budget; each should explain failure without producing a supposedly valid partial map.

Do not treat these planning/preview checks as completed combat or replay certification. T11 will add the appropriate gameplay checklist.
## Final verification

- Composition suite: **51 checks passed**, including namespace safety, generated-base provenance, immutable revision enforcement and resolution-contract rejection.
- T09 source checks: **33 passed**; editor workflow: **20 passed**.
- Existing T08 population/gameplay/replay suite: **0 failures**, including **47/47 replay actions** and Terminal initialization.
- Ironclad smoke: **10 passed, 0 failed, 0 skipped** (`artifacts/test-results/20261028-181635-smoke/`). An earlier run caught an editor UTF-8 error; it was corrected and the diagnostic test and complete smoke tier passed afterward.
- Final boundary probe confirms deterministic output, round-trip compilation and budget rejection after removing the redundant pre-population base compilation. Population now normalizes its own compiled base while preserving the original source signature and provenance.
- Rendered captures inspected for both plots. No composed-map combat completion, tactical balance certification or human visual approval is claimed. Existing certificate-store warnings remain.
