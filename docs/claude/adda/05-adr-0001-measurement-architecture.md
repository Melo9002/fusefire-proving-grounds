# ADR-0001: ADDA's measurement architecture

Status: accepted for `review/claude-adda` (Assignment 1). Date: 2026-11-23.

## Context

The ladder investigation produced wrong geometric conclusions from a skinned mesh read outside `skeleton_updated`. Nothing in the instrument said the reading was a different pose. ADDA needs readings that carry what they are, when and from which pose, and tools that refuse to answer from a pose they cannot vouch for, without a rewrite of the existing suite and without tying the contract to FuseFire gameplay.

## Decision

1. **`Measurement`** (envelope, plain data): `kind` (JOINT_POSITION, TARGET_ERROR, REACH_FEASIBILITY, SUPPORT_CLAIM, CAPSULE_OVERLAP, VERTEX_OVERLAP, MESH_INTERSECTION, PHYSICAL_COLLISION), `status` (FRESH, STALE, UNAVAILABLE, UNSUPPORTED), `pose` (FINAL, INTENDED, BASE, UNKNOWN), space, unit, tolerance, method, limitations, character identity, scenario, frame, update, time. `establishes(kind)` is true only for the kind itself. A reading without a value carries no number (`value = null`), never zero.
2. **`PoseWitness`** (one per skeleton, reference-counted, kept in the skeleton's metadata): the only listener of `skeleton_updated` for ADDA; it counts updates and emits `final_pose`. Providers connect to `final_pose`, stamp the sample there, and judge it later (`judge()`): a stamp from another update, another witness, or taken outside `final_pose` is STALE with a reason.
3. **Providers** are the existing diagnostics, retrofitted where they feed conclusions: `LadderClearance` (self-sampling, `status()`, `vertex_evidence()`), `ContactErrorDiagnostics` (`evidence()`), `SkinnedSurface` (`has_capture()`); others keep their direct, already-correct connection and are listed as P1 to migrate.
4. **Overlays** consume a provider's last sample and never sample themselves.
5. **Evidence interface**: `Measurement.to_dict()` and the Evidence tab's `adda` block; no server, no protocol.
6. **No extraction.** The contract classes know only `Skeleton3D` (plus `CharacterRig` for the identity string); that is the future seam.

## Alternatives considered

| Alternative | Why not |
|---|---|
| A global "inside the signal" flag that tools check before reading | Measured: it cannot be cleared reliably (a deferred clear runs after the next `_process`), so it would give false confidence. |
| Wrap or monkey-patch `get_bone_global_pose` to refuse outside the signal | Cannot intercept an engine method; a GDScript wrapper would be bypassed by the next author who calls the original. A structural contract (only `final_pose` listeners get stamps) works with the engine, not against it. |
| One base class every diagnostic must extend | A rewrite of 10 working tools for no new capability; the tools have different lifecycles (pure functions, nodes, ref-counted samplers). The envelope is data, so tools adopt it one at a time. |
| Tag readings by frame number | `skeleton_updated` fires more than once per rendered frame (measured); the update counter is exact. |
| A per-frame recorder and timeline now | Valuable (P1) but it is the next assignment's subject; building it before the contract would record unlabelled numbers. |
| An MCP/LLM-facing server | Out of scope and not required: JSON export is enough for agents. |
| Renaming `pose_workbench.tscn`, the CLI arguments or the test names | Breaks scripts, captures and catalog entries for no diagnostic benefit; the name is what a person reads (title, README, panel). |

## Consequences

* A reading either is evidence (FRESH, stated pose and kind) or says why it is not. The `ladder_*` failures stay visible; they now say *which* kind of measurement they are.
* One extra listener per instrumented skeleton while a tool is on, none when all are off (`workbench_diagnostics_test` still proves no listener is left behind).
* `LadderClearance.sample()` called by hand outside `final_pose` is allowed but its readings are STALE by construction; callers must not wire their own `skeleton_updated` handler to it (three tests and two probes were migrated).
* A witness restarted between a sample and its judgment is a different witness (stamps carry its instance id), so counters resetting to zero cannot make an old sample look fresh.
* Providers not yet migrated (`HandContactDiagnostics`, `BoneHighlight`, `MotionTrail`) are sound by lifecycle but do not emit envelopes.

## Verification

`tests/adda_measurement_integrity_test.gd` (21 checks): normal case FRESH; stale (earlier update, other witness) and outside-signal readings STALE with a reason; a bar through the legs counted (clean 0 vs through-legs many); a foot plan displaced 6 cm reads as 60 mm of TARGET_ERROR against about 0 normally; a hand target 2 m beyond the shoulder is REACH_FEASIBILITY false while the real one is true; no sample / tool off is UNAVAILABLE; kinds are mutually exclusive (all 64 pairs); every control releases its witness. Controls change test state only (displacements are applied and restored inside one update); production code and data are untouched.
