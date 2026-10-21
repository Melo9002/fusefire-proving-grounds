# Certified socket assembly

Phase 3.2 certifies one small imported Factory Kit equipment assembly: `pipe_receiver_unit`. It joins `factory_kit/machine-connection-hole` to `factory_kit/pipe-large` at the receiver's measured top seam. This is an intentionally open equipment unit, not a sealed building or an architectural shell. The pipe's free end is recorded as an external service interface because the reviewed catalog contains no verified matching cap.

## Geometric contract

Visual mating sockets use a complete local frame: origin, outward normal (+Z), tangent (+X), and the remaining up reference (+Y). Family, receiver/plug role, seam dimensions, supported roll, positional tolerance, and angular tolerance are explicit. The attachment transform reverses the mating normal while retaining a deterministic tangent. Tactical connectors remain separate.

The receiver socket is at native local `(0, 1.293, 0.36)`. The pipe's mating socket is at native local `(-0.5, 0.5, 0)`. Solving the frames places the pipe at `(0.5, 1.793, 0.36)` with the expected quarter turn around Z. The shared reviewed Factory Kit scale of 1.5 is applied only during presentation.

`IndustrialEquipmentAssemblyCatalog` exposes the reusable module, its two component transforms, its assembly certification record, and validation. `EnvironmentGeometricSocket` is deliberately a bounded deterministic helper rather than a general solver. The production presenter consumes the solved component transforms and applies the canonical module rotation for all four supported orientations.

## Tactical and certification boundaries

The module authors its six blocked tactical cells, cover, LOS behavior, visual envelope, and service-side clearance explicitly. Imported mesh geometry does not author gameplay state. Certification records both source geometry hashes and resolved calibration signatures; either dependency changing requires validation again.

Validation rejects incompatible families and roles, seam-size mismatch, unsupported roll, positional or angular misalignment, a missing required component, an unaccounted pipe termination, invalid overlap, and stale geometry or calibration dependencies. Failures are named for future authoring diagnostics.

## Content limitation

The reviewed Factory Kit machine/pipe family supports a truthful equipment assembly. It does not establish a modular architectural building kit. Generic machines, pistons, and cogs were inspected but lack verified physical sockets; they remain unavailable to this attachment contract. A later architectural task needs measured wall/corner/roof seams and suitable terminations before it can certify a multi-piece structure.
