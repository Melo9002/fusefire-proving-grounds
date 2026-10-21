# Phase 3 initial assembly library

Phase 3 establishes three small, evidence-backed examples. This is an inventory over existing contracts, not a general registry or a procedural assembly system.

## 1. `city_industrial_shell_i`

- **Role:** sealed exterior building shell.
- **Required imported asset:** `city_kit_industrial/building-i`.
- **Completeness:** complete exterior; no playable interior is implied.
- **Relationships:** normalized street frontage and protected exterior apron.
- **Orientations:** all four canonical quarter turns.
- **Tactical contract:** explicitly authored sealed occupancy; mesh geometry does not create traversal or cover.
- **Dependencies:** pinned GLB geometry hash and resolved calibration signature.
- **Evidence:** `docs/architecture/reviews/evidence/certified-building-shell-task-3.1/`.
- **Status:** technically certified; owner visual approval remains a separate decision.

## 2. `pipe_receiver_unit`

- **Role:** intentionally open machine/pipe installation.
- **Required imported assets:** `factory_kit/machine-connection-hole` and `factory_kit/pipe-large`.
- **Completeness:** complete for its declared equipment role. It is not a building or architectural shell.
- **Relationships:** one measured `factory_pipe` receiver/plug mate and one explicit external service interface.
- **Orientations:** all four canonical module rotations.
- **Tactical contract:** six explicitly authored blocking cells and two service-clearance cells.
- **Dependencies:** geometry hashes and resolved calibration signatures for both assets.
- **Evidence:** `docs/architecture/evidence/task-3.2/socket-family-audit.png`.
- **Status:** technically certified; no verified pipe cap exists in the reviewed content.

## 3. `certified_pipe_service_pad`

- **Role:** open industrial equipment/loading parcel.
- **Required elements:** imported `tile-low` paved support, certified `pipe_receiver_unit`, west boundary service connection, contiguous operator approach, loading approach, and the nested pipe termination contract.
- **Optional elements:** one imported shipping container and two construction-fence sections. Their absence or placement rejection does not invalidate the functional parcel.
- **Completeness:** intentionally open. It is neither an enclosed yard nor a canopy.
- **Configuration:** one deterministic 10×10 authored composition with all four whole-parcel road-facing rotations validated.
- **Tactical contract:** MapData receives ground and equipment occupancy through existing module writing. Access cells are separately checked for tactical walkability.
- **Dependencies:** paving, receiver, and pipe geometry/calibration dependencies. Optional dressing is not part of functional certification.
- **Evidence:** `docs/architecture/evidence/task-3.3/`.
- **Status:** technically certified; owner visual approval is intentionally recorded as false until reviewed.

## Parcel validation

The service pad rejects missing required support or equipment, missing physical termination, blocked operator access, blocked loading access, incomplete service clearance, unsupported geometry, and stale geometry or calibration dependencies. Its deterministic signature includes required and optional placements, access regions, and dependency revisions.

Socket attachment is used only for the real pipe seam. The relationship between road, paving, equipment access, loading space, container, and fence is spatial. No artificial sockets were introduced between unrelated objects.

The legacy `equipment_compound` recipe now instantiates this certified composition rather than a generic machine cluster plus an arbitrary fence. This is a bounded content improvement; parcel selection and rotation remain under the existing coherent assembler.

## Known limitations and Phase 4 readiness

- The library still lacks a certified multi-piece architectural structure. The second example remains correctly classified as equipment.
- Only one parcel configuration is certified. It does not establish generalized parcel ownership, relationship compilation, or mission reservation.
- The pipe service interface has no reviewed cap asset.
- Optional container and fence variations are deliberately narrow.
- Visual inspection covers the deterministic examples, not every procedural seed.

The three examples now share stable identities, imported dependencies, explicit transforms or placements, honest completeness classifications, authored tactical behavior, clearances, deterministic reconstruction, validation diagnostics, and certification state. That is sufficient input for Phase 4's shared layout-document design, while the limitations above must remain visible during migration.
