# Task 7.2 — Supported Parcel-Size Expansion

## Result

Generation 2.0 now supports one additional curated parcel configuration: an
elongated industrial loading/service strip authored at 20x10 cells and supported
in its canonical 10x20 quarter-turned form. The extension preserves the existing
plot -> parcel -> module hierarchy and does not introduce arbitrary subdivision.

The strip is deliberately classified as an open loading/service area. It uses two
reviewed `paved_courtyard` modules, the certified open
`industrial_loading_canopy`, and optional imported cargo/barrier dressing. It is
not a sealed building and does not claim vehicle-navigation behavior.

## Assumptions audit

- Parcel derivation previously selected non-overlapping 20x20 building parcels,
  then emitted every remaining macro cell as a 10x10 lot.
- Exact frontage spans, parcel ownership, reservations, document persistence,
  and bounded candidate retries were already size-independent.
- Building fitting already uses real profile dimensions; no mesh or tactical
  footprint needed resizing.
- Recipe rotation was square-dependent: `_rotate_into_parcel()` used the target
  parcel depth for every turn. Task 7.2 now transforms against the authored
  recipe extent, which is required for 20x10 <-> 10x20 placement.
- The candidate frontage list previously had no need to reject rotations whose
  rotated recipe dimensions differ from the parcel. The strip now does so
  explicitly.

## Bounded generation policy

- Industrial and mixed-service 60x50 layouts may select at most one elongated
  parcel after 20x20 building parcels are reserved and before remaining 10x10
  lots are emitted.
- Candidate pairs must be unused, non-road, outside required mission
  reservations, road-adjacent on a compatible long boundary, and expose at
  least four contiguous frontage cells.
- Selection is ordered by a stable seed-derived score. Existing per-parcel
  limits remain unchanged: 12 candidate attempts and two optional removals.
- Commercial layouts remain an unchanged control because the new composition is
  industrial content, not a generic storefront substitute.
- The parcel grammar revision is
  `coherent_parcel_grammar_v5_elongated_service`; the tracked persistence example
  was revalidated against that revision.

## Functional contract

`loading_service_strip` requires paving and the open canopy, records optional
cargo/barrier occupants separately, and reserves a centered four-cell-wide
loading approach from the exact selected frontage through four rows of the
parcel. Unsupported parcel dimensions and frontage rotations are rejected.
Mission reservations win before parcel selection, while failed candidates leave
the accepted layout and reservation ledger unchanged.

The unified layout document now records `configuration_id` for each parcel.
`elongated_loading_service` is validated against 20x10/10x20 bounds and is
preserved through edit-copy, save/load, and reconstruction.

## Deterministic matrix

| Environment / seed | Parcel sizes | Functional / buffer | Attempts / rejects | Fallback | Result |
| --- | --- | ---: | ---: | ---: | --- |
| industrial_district / 17 | 8x 10x10, 1x 10x20, 2x 20x20 | 10 / 1 | 12 / 1 | 0 | Valid |
| mixed_service / 11027 | 12x 10x10, 1x 20x10, 2x 20x20 | 7 / 8 | 15 / 0 | 0 | Valid |
| commercial_street / 7319 | 11x 10x10, 2x 20x20 | 10 / 3 | 24 / 12 | 1 mission-protected buffer | Valid control |

Two complete generations took approximately 10.4 s, 9.9 s, and 13.9 s for the
three cases on the development machine. Candidate work remained bounded; no
comparable pre-change timing baseline was retained, so no performance-improvement
claim is made.

## Verification

Focused automated coverage in
`tests/coherent_parcel_size_expansion_test.gd` verifies:

- all four supported quarter turns and independent rectangular bounds;
- existing 10x10 and 20x20 parcel retention;
- exact frontage and four-cell-deep loading access;
- required/optional occupants and blocked-access rejection;
- reservation conflict rollback and unsupported size rejection;
- deterministic generation, tactical validity, persistence, and reconstruction.

Passing compatibility checks:

- `parcel_functional_relationship_test.gd`
- `parcel_spatial_contract_test.gd`
- `coherent_layout_assembly_test.gd`
- `coherent_parcel_retry_test.gd`
- `coherent_secondary_road_test.gd`
- `battlefield_layout_document_test.gd`
- `map_editor_layout_store_test.gd`
- `generation_2_tactical_gameplay_test.gd`
- `generation_2_replay_edited_map_test.gd`

The first direct persistence run lacked the runner's writable output directory
and failed its file-write checks; rerunning with `FUSEFIRE_TEST_OUTPUT_DIR` passed
all persistence assertions. The ordinary Windows Godot certificate/log warnings
were non-test environment messages. The full Generation subsystem tier was not
repeated after the user requested a focused finish.

## Rendered inspection

Evidence is under
`docs/architecture/reviews/evidence/parcel-size-expansion-task-7.2/`.

- Industrial seed 17 shows the 10x20 form with a clear central approach, canopy
  supports outside the approach, optional container at the rear, and continuous
  street/sidewalk frontage.
- Mixed-service seed 11027 shows the 20x10 form as a readable open service lot.
- Diagnostic views confirm the loading reservation (magenta), selected frontage
  (green), parcel boundary, and road ownership align.
- Commercial seed 7319 remains the no-new-configuration control.

## Remaining limits / Task 7.3 input

- Only one elongated service parcel is selected per supported layout.
- The new configuration is limited to industrial and mixed-service 60x50 maps.
- No vehicle turning radius, automatic interior, arbitrary parcel size, or new
  asset family is implied.
- Buffer frequency is still driven by available certified content and mission
  reservations; mixed-service seed 11027 intentionally retains eight buffers.
- Future variety should add a genuinely certified content family, not more
  dimensions using the same recipe.

Task 7.2 is complete. No Task 7.3 work was started.
