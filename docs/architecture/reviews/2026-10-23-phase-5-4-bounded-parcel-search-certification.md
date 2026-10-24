# Phase 5.4: Bounded Parcel Search and Spatial Assembly Verification

## Scope and outcome

The coherent environment assembler now explores a fixed, deterministic set of already-supported parcel alternatives. It can try exact frontage spans, canonical assembly rotations, and a small set of authored frontage-tangent offsets before accepting an intentional buffer or reporting an explicit fallback. Every accepted functional parcel still passes the Phase 5 geometric relationship validator and the existing `MapData` tactical validation path.

This work does not add a general constraint solver, new parcel recipes, new asset families, or a gameplay entry-point migration.

## Previous selection path

The existing assembler already supplied several sound foundations:

- road-adjacent macro parcels and exact Task 5.1 frontage spans;
- shuffled, seed-deterministic recipe lists;
- clone-before-commit placement transactions;
- mission and access reservations created before occupants;
- required/optional occupant classification; and
- explicit `district_buffer` parcels for landlocked or intentionally open space.

The selection loop nevertheless considered only one frontage per recipe and one centered building placement. A compatible building could therefore be rejected against one reserved frontage even when a second measured frontage or a one-cell tangent adjustment worked. Rejections were retained mainly as strings, so budget exhaustion, proven incompatibility, and absent content were difficult to distinguish.

## Search contract

`EnvironmentParcelCandidateSearch` enumerates supported choices in this order:

1. the primary exact frontage for each candidate template;
2. additional disconnected or differently oriented frontage spans;
3. authored one-cell tangent offsets for complete imported shells when the parcel has measured margin.

The fixed initial budgets are:

| Limit | Value | Reason |
| --- | ---: | --- |
| Templates per parcel | 6 | Preserves the former bounded recipe breadth. |
| Frontages per template | 4 | Covers the current rectangular parcels without unbounded boundary exploration. |
| Tangent offsets per frontage | 3 | Center, one cell left, and one cell right; only when the shell fits. |
| Total candidates per parcel | 12 | Caps the combined work even when the Cartesian choice set is larger. |
| Optional removals per candidate | 2 | Allows blocked dressing to yield without eroding the required assembly. |

The first alternatives remain broad across recipes before refinements are attempted. Candidate-local random seeds derive from the map seed, parcel ID, template, frontage, and offset, so rejecting one candidate does not consume a shared random stream and alter later candidates.

Each candidate clones the accepted layout and reservation ledger. Required access is reserved, required and optional occupants are placed, and applicable frontage, pedestrian, loading, service, socket, envelope, and reservation contracts are validated before the clone replaces accepted state. Failed candidates leave neither placements nor reservations behind.

## Diagnostics and fallback meaning

The layout plan records structured candidate rejections, per-parcel attempts and outcomes, optional dressing failures, the configured budget, and budget exhaustion. Its deterministic signature includes the selected frontage, tangent offset, and search outcome. The unified layout document pins the `coherent_parcel_grammar_v4_bounded_search` dependency and preserves the selected choices in generated provenance and parcel relationships.

Fallbacks now distinguish:

- `NO_COMPATIBLE_CANDIDATE`: no supported specification exists;
- `PROVEN_INCOMPATIBLE_WITHIN_SUPPORTED_CHOICES`: every enumerated supported specification was tested and rejected;
- `SEARCH_BUDGET_EXHAUSTED`: supported work remained after the fixed budget ended; and
- intentional `district_buffer` outcomes selected by the recipe, which are not failures.

The Map Editor status reports functional parcels, buffers, attempts, rejections, fallbacks, and exhausted budgets. The plan overlay uses amber parcel boundaries, cyan roads, green selected frontage spans, magenta functional access reservations, and yellow mission reservations.

## Deterministic seed matrix

The comparable 50×40 matrix was generated twice per case and reconstructed through the unified document compiler. Timings are local wall-clock observations, not performance guarantees.

| Environment | Seed | Functional / buffer | Attempts / rejected | Optional failures | Fallback / exhausted | Time | Tactical quality |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| industrial district | 17 | 8 / 1 | 10 / 1 | 2 | 0 / 0 | 3266 ms | 45.7 |
| industrial district | 2208 | 5 / 4 | 10 / 1 | 0 | 0 / 0 | 2580 ms | 42.5 |
| commercial street | 7319 | 6 / 0 | 12 / 6 | 0 | 0 / 0 | 3070 ms | 53.2 |
| commercial street | 2208 | 9 / 0 | 10 / 1 | 1 | 0 / 0 | 3212 ms | 42.7 |
| mixed service | 11027 | 7 / 0 | 8 / 1 | 1 | 0 / 0 | 2815 ms | 50.1 |
| mixed service | 2208 | 5 / 4 | 10 / 1 | 0 | 0 / 0 | 2604 ms | 42.4 |

The retained pre-change probe for the same 50×40 commercial seed 7319 produced 5 functional parcels and 1 buffer after 9 attempts and 4 rejections. The bounded search rejects six alternatives blocked by the deployment reservation, then accepts the imported building on `parcel_00_frontage_01`, yielding 6 functional parcels and no buffer. Other matrix cases preserve their functional/buffer counts; their additional attempt is attributable to reservation-aware alternative evaluation. No broad historical benchmark exists, so this report does not claim an overall percentage improvement.

The actual 60×50 Map Editor matrix also passed functional, tactical, budget, and document-reconstruction checks:

| Environment | Seed | Functional / buffer | Attempts / rejected | Explicit result |
| --- | ---: | ---: | ---: | --- |
| industrial district | 17 | 8 / 0 | 8 / 0 | No fallback. |
| commercial street | 7319 | 11 / 3 | 25 / 12 | One proven-incompatible fallback; all 12 alternatives conflict with the required deployment reservation. |
| mixed service | 11027 | 9 / 8 | 17 / 0 | All buffers are intentional recipe outcomes. |

The commercial fallback is therefore protected mission space, not a hidden search failure. No matrix case exhausted its search budget. A focused synthetic case verifies that unexamined supported candidates beyond attempt 12 report `SEARCH_BUDGET_EXHAUSTED`.

## Visual inspection

The capture command is:

```powershell
godot_console --path . --resolution 1600x900 --script res://tests/coherent_parcel_retry_capture.gd -- docs/architecture/reviews/evidence/bounded-parcel-search-task-5.4
```

Normal presentation views were inspected with engineering overlays disabled; diagnostic views were inspected separately.

- [Industrial seed 17 overhead](evidence/bounded-parcel-search-task-5.4/industrial_district-17-overhead.png) and [loading frontage](evidence/bounded-parcel-search-task-5.4/industrial_district-17-loading.png): continuous imported roads and sidewalks, an honestly open loading canopy, clear approaches, and no fallback parcel.
- [Commercial seed 7319 overhead](evidence/bounded-parcel-search-task-5.4/commercial_street-7319-overhead.png) and [building frontage](evidence/bounded-parcel-search-task-5.4/commercial_street-7319-frontage.png): imported sealed shell, road-facing frontage, and explicit mission-protected open space.
- [Mixed-service seed 11027 overhead](evidence/bounded-parcel-search-task-5.4/mixed_service-11027-overhead.png) and [equipment service area](evidence/bounded-parcel-search-task-5.4/mixed_service-11027-service.png): imported socket-connected equipment, clear service approach, and intentional buffers.
- [Industrial diagnostics](evidence/bounded-parcel-search-task-5.4/industrial_district-17-diagnostic.png), [commercial diagnostics](evidence/bounded-parcel-search-task-5.4/commercial_street-7319-diagnostic.png), and [mixed-service diagnostics](evidence/bounded-parcel-search-task-5.4/mixed_service-11027-diagnostic.png) show selected frontages and reservations independently of normal presentation.

Visual review found no new road discontinuity, blocked required entrance, loading obstruction, or service-clearance intersection in these bounded examples. This is representative evidence, not catalog-wide visual certification.

## Verification

Focused automated coverage verifies:

- deterministic candidate ordering and candidate-local random streams;
- multiple disconnected frontage choices and supported one-cell offsets;
- fixed-budget exhaustion reporting;
- actionable wrong-frontage rejection;
- placement and reservation rollback after rejection;
- exact selected-frontage and offset persistence;
- functional relationship validation before acceptance;
- deterministic generation and document reconstruction;
- `MapValidator`, deployment legality, route availability, and existing tactical-quality metrics; and
- both the 50×40 comparison matrix and the real 60×50 editor matrix.

The relevant Phase 1–5 contract suites pass, including canonical geometry, roads, certified building/socket/equipment assemblies, layout documents, mission reservations, exact parcel spatial contracts, functional parcel relationships, and coherent layout assembly. The final broad command was:

```powershell
.\tools\run_tests.ps1 subsystem -Subsystem generation
```

It completed with `PASS=31`, `FAIL=0`, `SKIP=13` in 1,008.80 seconds. The 13 skips are the runner's documented explicit-only rendered captures and extended stress workflows; the Task 5.4 capture was run separately and inspected as described above. Godot emitted existing environment warnings when it could not write sandboxed `user://logs` or read the Windows root certificate store during direct focused runs; every invoked test process still exited successfully.

## Remaining limits and Phase 6 readiness

- Search remains local to one parcel. It does not revise previously accepted neighbors or globally optimize district composition.
- Only complete-building templates receive tangent offsets; other recipes still use their existing authored placements.
- The current candidates use canonical quarter turns and do not introduce mirroring or arbitrary rotations.
- Intentional buffer frequency still reflects the existing recipe grammar and landlocked parcel policy.
- A valid required mission reservation may deliberately prevent otherwise attractive parcel content.
- Generation timings scale with the number of actually attempted candidates; the fixed cap keeps the upper bound predictable, but no formal CI performance threshold exists.
- The evidence matrix does not establish comprehensive seed quality.

The coherent assembler is ready for Phase 6 integration work in the architectural sense: its accepted parcels are document-preserving, relationship-valid, reservation-aware, deterministic, and bounded. Normal gameplay generation remains unchanged until that later migration is explicitly undertaken.
