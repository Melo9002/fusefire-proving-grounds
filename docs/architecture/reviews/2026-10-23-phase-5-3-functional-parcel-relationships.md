# Phase 5.3 — Functional Parcel Relationships

## Scope and result

Task 5.3 adds bounded functional validation to the parcel recipes already used by `CoherentEnvironmentAssembler`. It does not add a general constraint solver, new parcel grammar, building interiors, vehicle navigation, or new asset families.

A parcel now needs more than non-overlapping occupants. Applicable recipes must resolve an exact road frontage, use the correct local access edge, contain their required occupants, keep their authored access region physically clear, and retain a corresponding tactical route in compiled `MapData`.

## Recipe audit

| Existing recipe | Classification | Required relationship | Minimum frontage | Required occupants | Optional occupants |
| --- | --- | --- | ---: | --- | --- |
| `building_frontage/*` | Sealed exterior frontage | Pedestrian road-to-apron access | 2 cells | Four paving tiles and selected complete shell | Dumpster, streetlight |
| `industrial_yard_block` | Open industrial yard | Loading access | 4 cells | Paving, loading canopy, machine cluster | Cargo container |
| `loading_bay` | Open loading bay | Loading access | 4 cells | Paving and loading canopy | None |
| `equipment_compound` | Open equipment area | Service clearance | 3 cells | Paving and certified pipe receiver unit | Cargo container, fence |
| `service_alley` | Open service alley | Pedestrian access | 2 cells | Paved alley | Dumpster, barrier |
| `staging_pad` | Open staging pad | Loading access | 4 cells | Paving | Container, barrier |
| `public_forecourt` | Open forecourt | Pedestrian access | 2 cells | Paving | Streetlights |
| `district_buffer` | Intentional open buffer | None | — | None | None |

The sealed City Kit buildings remain exterior-only tactical obstacles. Their visible frontage establishes an approach apron; it does not imply a playable interior. The equipment compound retains the Phase 3 certified operator route and west-side service connection. Loading contracts remain bounded geometric approaches because FuseFire has no authored vehicle turning or navigation contract.

## Implementation

`EnvironmentParcelRelationshipValidator` owns the small recipe table and returns structured failures with parcel and relationship references. It provides:

- deterministic selection of a sufficient exact frontage span;
- recipe-specific local access direction and rotation;
- required-occupant validation;
- physical access-cell derivation;
- geometry obstruction checks;
- compiled `MapData` access and Pathfinder checks;
- compact relationship properties for layout persistence.

Complete-shell access is a two-cell corridor derived from the placed shell's canonical `+Z` frontage. It begins immediately outside the calibrated shell footprint, crosses its parcel apron, and reaches the selected road boundary. The equipment compound instead uses the certified Phase 3 operator approach. Loading and other open-space recipes use their bounded frontage approach.

The coherent assembler selects a compatible frontage before committing a candidate and derives rotation from the recipe's actual local edge. This corrected a previously hidden disagreement: complete shells and loading recipes use local south, while the certified equipment compound connects on local west. Required relationship failures reject the candidate transactionally. If an optional decoration alone blocks access, that decoration is removed and the required parcel is revalidated and committed without an orphaned placement.

Task 5.2 reservations now protect the complete authored approach rather than only the parcel boundary. Placements owned by that parcel proceed to the precise relationship validator, avoiding a false conflict between a shell's own authored frontage clearance and its access reservation. Other parcels and road furniture remain subordinate to that reservation.

After `EnvironmentModuleMapWriter` compiles tactical effects, the existing `MapGraphBuilder` and `Pathfinder` verify access in authoritative `MapData`. Geometry obstruction and tactical disconnection remain separate diagnostics. No mesh-derived rule changes traversal, cover, occupancy, or LOS.

## Document lifecycle

Generated layout documents persist:

- selected frontage identity;
- minimum supported width;
- local and expected world access directions;
- concrete access cells;
- parcel completeness classification;
- required and optional occupant relationships.

Document validation reconstructs owned placements and reruns bounded geometry validation. Editing retains required relationships and marks them `requires_revalidation`. Successful shared compilation marks functional relationships and parcel records validated again. Invalid edits remain explicit failures; required relationships are never silently removed. Schema-2 save/load preserves the records deterministically, with JSON numeric normalization accounted for by the regression oracle.

## Diagnostics

The validator emits focused codes, including:

- `MISSING_REQUIRED_FRONTAGE`
- `INSUFFICIENT_FRONTAGE_WIDTH`
- `INVALID_FRONTAGE_ORIENTATION`
- `BLOCKED_PEDESTRIAN_APPROACH`
- `MISSING_TACTICAL_ACCESS`
- `BLOCKED_LOADING_CLEARANCE`
- `MISSING_SERVICE_CLEARANCE`
- `INVALID_SERVICE_CONNECTION`
- `MISSING_REQUIRED_OCCUPANT`
- `MISSING_REQUIRED_RELATIONSHIP`
- `INVALID_FRONTAGE_REFERENCE`

Each failure carries its parcel ID plus the relevant frontage, placement, cell, or relationship reference.

## Regression coverage

`parcel_functional_relationship_test.gd` covers:

- valid and insufficient frontage spans;
- incorrect building frontage rotation;
- valid and physically blocked pedestrian approaches;
- physical access with a deliberately disconnected tactical cell;
- valid and blocked loading approaches;
- valid and obstructed certified equipment service access;
- missing required equipment;
- optional dressing omission;
- explicit open-yard classification;
- edit invalidation and successful revalidation;
- deterministic relationship persistence.

The generation-subsystem run completed 30 automated suites in 845.34 seconds. Twenty-nine passed initially; `coherent_road_streetscape_test.gd` exposed one obsolete assumption that every optional fixture must survive placement even after required parcel access is known. The production path now records an exact diagnostic for every rejected fixture, and the regression requires either the reviewed asset at its authored slot or that explicit rejection. Its focused rerun passed with zero failures. The Task 5.3 suite also passed all 19 assertions after the correction, and a final headless project parse passed. Twelve GPU or stress checks remained correctly classified as explicit-only by Ironclad.

The broad run otherwise passed the existing Task 5.1 ownership tests, Task 5.2 reservation tests, Phase 1 geometry tests, Phase 3 assembly tests, Phase 4 document/lifecycle tests, coherent generation tests, semantic district generation, and legacy generation smoke tests. No existing assertion was deleted or weakened to conceal a defect; the streetscape contract now verifies the intentional required-access priority and makes skipped optional content traceable.

## Rendered inspection

The repeatable command is:

```powershell
godot_console --path . --resolution 1600x900 --script res://tests/parcel_functional_relationship_capture.gd -- docs/architecture/reviews/evidence/parcel-functional-relationships-task-5.3
```

Evidence:

- `parcel-relationships-accepted-overhead.png` — seed 2208 district overview with overlays disabled.
- `parcel-relationships-accepted-frontage.png` — complete imported shell and unobstructed street frontage.
- `parcel-relationships-accepted-service.png` — imported pipe receiver unit and its service area.
- `parcel-relationships-rejected-blocked-frontage.png` — diagnostic fixture using the real shell and shipping container, with the container visibly occupying the double-door approach. This fixture is presentation evidence only; the automated geometry test performs the rejection.

Manual inspection found the accepted frontage and equipment approach clear. The rejected fixture makes the obstruction visually unambiguous. These captures establish the reviewed examples, not universal visual certification of every seed.

## Remaining limits for Task 5.4

- Candidate selection attempts a bounded existing list; it does not search alternative frontage intervals and occupant transforms combinatorially.
- Complete-shell access uses the reviewed centered frontage corridor. Per-door aperture records would be needed if future custom building assets place entrances away from that corridor.
- Loading access validates alignment, width, clearance, and tactical surface continuity. It does not model vehicle length or turning radius.
- Service alleys and forecourts have bounded pedestrian access but no public/private circulation taxonomy.
- No new retries, repair orchestration, parcel grammar, or gameplay entry point was introduced.
