# Task 13: non-humanoid presentation boundaries (report)

Maintained guide: [`docs/animation.md`](../animation.md), section *Movement families and the presentation boundary*. This report is what was decided, built and measured. Baseline: `origin/main` at `0d09bb7`.

## Findings that shaped the design

* `CharacterPresenter` is a humanoid presenter by construction: `report_velocity` keeps only x and z (and the hosts flatten before calling it too), turns the rig toward that velocity, and the class owns postures, weapon readiness, attack, rescue and gesture holds. A drone cannot pass vertical motion through it, and facing is always "toward the velocity" unless held.
* `ActionHandle`, `PresentationTypes.Outcome` and `FacingMode` are already free of the rig and of tactical code: they are the reusable core. `PresentationIntent` mixes neutral motion fields with humanoid posture, readiness and equipment; it was left alone.
* The humanoid presenter counts a hold down only on a later engine frame than the one that armed it, so a humanoid reaction needs real frames to pass.

## Alternatives and the choice

A (separate presenters, small common contract), B (shared coordinator with family drivers), C (extend `CharacterPresenter`): compared in the guide. **A** is chosen: B's coordinator would own exactly the things that differ between families, and C makes every humanoid field optional while a drone still needs a rig-free clock and action model. A shares only the clock, the facing vocabulary, `ActionHandle` outcomes, a six-name capability question and a read-only snapshot.

## What was built

* `presentation/motion/`: `MotionRequest` (actual and intended 3D velocity, authoritative transform as a value, facing request, delta, frame id; conventions documented) and `MotionPresenter` (clock, duplicate-frame count, capabilities, refusal record, a timed `ActionHandle` for the reaction, teardown, snapshot).
* `presentation/characters/presenter/humanoid_motion_bridge.gd`: an opt-in adapter from the contract to the existing presenter (translates, delegates, ticks once). No existing humanoid file was modified, and the boundary test now asserts none of them mentions the contract.
* `research/motion_families/`: `WheeledPresenter` (wheel spin from observed forward speed, steering from observed turn rate and wheelbase), `DronePresenter` (3D velocity, rotors from vertical speed, visual yaw offset independent of travel, lean, hover bob, a hit-reaction wobble), `PrimitiveBodies` (no skeleton).
* `research/motion_families_demo/`: a scene with a humanoid (the existing exploration host, unchanged), the platform and the drone driven by one scripted context; `presentation/diagnostics/motion_readout.gd` shows any family's snapshot.
* Not implemented: quadruped, tracked platform, suspension, vehicle or flight mechanics, a multi-family workbench (assessed in the guide).

## Verification

* `motion_contract_test`: 57 checks across the request, the wheeled platform, the drone, the humanoid bridge and five negative controls (a flattened climb, a presentation that overwrites its entity's height, an overclaimed capability, a frame presented twice, cleanup). Six deliberate breakages of the code under test (a drone ignoring vertical speed, wheels spinning when stopped, time advanced twice, unsupported accepted, teardown leaving the tilt, the bridge ticking twice) were each caught, and a harmless change passed.
* Boundary test (`animation_module_boundaries_test`): the contract and the family examples may not name the rig, skeleton, animation tree, IK, humanoid solvers or tactical types (with a self-check that the pattern matches them and lets the shared vocabulary through); only the bridge knows both the contract and `CharacterPresenter`; the humanoid presenter, rig, both hosts and the workbench do not use the contract.
* Overhead (CPU, `tools/quality/motion_contract_overhead_probe.gd`): a `MotionRequest` 2.0 us; wheeled present 5.1 us; drone present 8.8 us; humanoid direct (`report_velocity` plus `tick`) 4.2 us against the bridge 8.7 us. The humanoid frame path itself is unchanged.
* Rendered with the real renderer (`tests/motion_families_capture.gd`, 1600x900): the three bodies at five times of the script; both examples read correctly (wheels turn and steer on a bend, the drone climbs with its altitude line, banks when flying sideways to its facing, hovers). Inspected stills are in `docs/claude/images/task13/`. Limits: stills do not show motion; the humanoid is small at this camera.

## Compatibility

No existing production file changed, so the 39-scenario pose trace and the 853-route trace are unaffected by construction (not re-run). Test results are listed in the issue and the final summary.

## Limits and next steps

A shared-types move (`ActionHandle`, `PresentationTypes` split into neutral and humanoid parts) and a node-based `MotionTrail` would help detachability; a workbench adapter for non-humanoid families would let Task 12's live view serve them; the real quadruped and tracked families remain designs.
