# CharacterPresenter foundation (Task 07, package 2)

What exists, what is integrated, what is only tested, and what is still planned. Design background: [ownership and contracts](animation-ownership-contracts-2026-11-20.md) (Task 04). Navigation: [where to go](animation-where-to-go-2026-11-20.md).

**Status words.** *Implemented* = the code exists. *Integrated* = production uses it. *Tested* = an executed test pins it. *Planned* = not done.

## The new types (all in `presentation/characters/`, none import gameplay)

| Type | Home | Implemented | Integrated | Tested |
| --- | --- | --- | --- | --- |
| `PresentationTypes` (Posture, FacingMode, EquipmentState, Outcome, priority tiers) | `presenter/presentation_types.gd` | yes | used by the types below | via the tests below |
| `ActionHandle` (exactly-once settle, `is_done`, `wait()`, `when_done()`, `cancel()`, `settled()`) | `presenter/action_handle.gd` | yes | **no**: nothing in production creates one yet | `action_handle_test` (real coroutines: settled before and after observation, several waiters, re-entrancy, cancellation, timer-settled across frames; a mutation that removed the early-return in `wait()` was caught) |
| `PostureArbiter` (source-keyed, explicit priorities, deterministic ties, idempotent repeats, release, prefix release, override layer, teardown) | `presenter/posture_arbiter.gd` | yes | owned by the presenter; **cover is not routed through it** (cover behaves exactly as before) | `posture_arbiter_test` |
| `PresentationIntent` (snapshot of persistent state) | `presenter/presentation_intent.gd` | yes | built on demand by `CharacterPresenter.intent()` | `character_presenter_test` |
| `CharacterPresenter` | `presenter/character_presenter.gd` | yes | **yes, for locomotion**: `UnitVisualAdapter.presenter` is ticked once per frame | `character_presenter_test` |
| `RigInput` (typed pose input) | `rig/rig_input.gd` | yes, first subset | **yes**: `CharacterRig` hands it to `LocomotionPoseModifier.apply_input` every frame | `locomotion_*` tests, composition test |

`WeaponReadiness.Level` is reused as the readiness vocabulary; there is no second readiness enum. Five new global class names were registered (`PresentationTypes`, `ActionHandle`, `PostureArbiter`, `PresentationIntent`, `CharacterPresenter`) plus `RigInput`.

## What the presenter owns now (one owner)

* **Presentation time** (`presenter.time`). `UnitVisualAdapter._presentation_clock` is now a property that reads and writes it, so attack timelines and tests are unchanged; it is an accessor, not a second clock.
* **Reported velocity, speed and heading rate**, and **facing that follows the velocity** (`report_velocity`: the same turn-toward-velocity maths and rate that `update_locomotion` had; `update_locomotion` now delegates).
* **The "is it moving" decision** that settles the gait: the host says so when it has authority (`set_movement_authority`), otherwise it is inferred (moving for 0.15 s after the last report), exactly the previous rule.
* **Posture requests** (the arbiter), as an owned, tested component with no production writer yet.

The gait, cadence, bank, twist and pitch mathematics are **not** reimplemented: `tick()` calls `CharacterRig.update_locomotion_presentation`, and the same-frame guard that stops a double feed moved behind `CharacterRig.locomotion_fed_this_frame()`.

## Frame lifecycle

The presenter has no `_process`. The host node ticks it once per frame, from the same place and in the same order as before (`presenter.tick(delta)` replaced `_presentation_clock += delta` and `_tick_locomotion(delta)`; every other adapter call in `_process` is unchanged). Proven by test on the production visual: exactly one tick per frame, and the tick of a frame happens before that frame's modifiers (same-frame application). `delta` is used as given; `Engine.time_scale` is never read (a test ticks under a 0.25 time scale and time still equals the sum of deltas). Package 1's update-order test still passes: modifier order and "all `_process` before all modifiers" are unchanged. Idle cost against the Package 1 baseline: adapter `_process` 0.017 to 0.018 ms per character, modifier stack 0.010 ms (unchanged).

## Why the presenter is bound to the rig, not a separate node

`UnitVisualAdapter` and the workbench **are** the `CharacterRig` (inheritance). A separate `CharacterPresenter` node would have to be a child of the rig, which is processed *after* its parent, so its tick would run after the adapter's seven calls and change the order they depend on. Making the presenter a `RefCounted` component ticked from the host's existing `_process` is the smallest valid step: no order change, no second driver, no duplicated state. The conversion from inheritance to composition (where the presenter becomes the node that ticks) is **planned** and is the point where the "one driver" claim can be made. **It is not made yet.**

## Ownership: what is where

| Responsibility | Owner today |
| --- | --- |
| Presentation time, reported velocity, velocity-following facing, moving decision | **presenter** (integrated) |
| Posture requests | **presenter** (arbiter; not yet written by production) |
| Gait, cadence, bank, twist, pitch maths | rig (`update_locomotion_presentation`), unchanged by design |
| Facing changes from `face_world_position`, cover yaw, `begin_turn`, `_cover_yaw` | still `UnitVisualAdapter` / rig (compatibility path) |
| Cover posture (`_sync_cover_crouch`), aim hold, attack timeline, rescue, traversal, readiness requests, equipment/stow | still `UnitVisualAdapter` / rig |
| Weapon readiness object | the rig's `WeaponReadiness` (the presenter only reads it for the snapshot) |
| Equipment state | derived: stowed reads as `SLUNG`, otherwise `HELD`; `NONE` and changing it are **planned** |
| Workbench locomotion feed | the workbench still calls `update_locomotion_presentation` from its own `_process`. A parity test proves the presenter path gives the same gait, cadence, bank and speed as that direct feed every frame, so migrating the workbench later is safe. It was **not** migrated now: it feeds a heading rate while idle and has no movement authority, so a straight swap needed more than this package's scope |

## Duplicated state still present

* Facing: `rotation.y`, `_cover_yaw` and `character_root.rotation.y` (unchanged).
* The stow/readiness state is read, not copied, by the presenter (no new duplication).
* Two frame drivers still exist (adapter and workbench).

## Typed `RigInput`: what moved and what did not

Moved: the four situational adjustments (twist, bank, pitch, two step lifts) now reach `LocomotionPoseModifier` as a `RigInput` through `apply_input`. The modifier's public fields remain readable and writable because existing tests read and write them; `apply_input` is the only writer the rig uses.

Inventory of string-keyed accesses still left (modifier to rig): `TraversalPoseModifier` 11 `rig.get(...)`; `WeaponPoseModifier` 13 `rig.get(...)` plus 7 `rig.call(...)` (31 in all). `CoverCrouchModifier`, `HandGripModifier` and `LocomotionPoseModifier` have none. All five modifiers still implement the deprecated `_process_modification()`; migrating to `_process_modification_with_delta` is **planned**.

## Reverse dependencies and independence

`presenter/` and `rig/` import no gameplay type (`animation_module_boundaries_test` still enforces the ratchet; the two known gameplay importers are unchanged). The presenter works with no `TacticalUnit` and with no rig at all (tested). It depends on `CharacterRig` (presenter to rig, the intended direction) and on `WeaponReadiness`.

## Tests added (all `fast`)

`action_handle_test`, `posture_arbiter_test`, `character_presenter_test` (21 checks including parity and one-tick-per-frame). Targeted regression run: the animation FAST tier (16 tests), the changed-file selection (24), plus locomotion, replay determinism, ladder and stair gameplay, rescue, weapon readiness, torso frame, cover crouch, weapon pose, the exploration playground and rig-profile tests, all passing; GDScript warning audit 0 warnings. The full regression tier was not run. Headless results are not visual-quality validation.

## Recommended next package

1. Convert the **workbench** to tick a presenter (parity is already proven), and add a single `tick` entry so both hosts share it.
2. Route **cover** through `postures` (the tactical adapter keeps cover policy and supplies `set_posture(&"tactical/cover", ...)`), with `locomotion_cover_composition_test`, `cover_*` tests as the guard.
3. Then M1 (typed `RigInput` for the remaining modifiers and `_process_modification_with_delta`), then handles for attack/rescue.

## Package 3 update: shared frame driving and posture ownership

**What changed.** (1) The workbench now ticks its rig's presenter instead of calling `update_locomotion_presentation` itself. (2) Cover posture is a persistent request, not a direct write. (3) The superseded writers were removed.

**Frame driving.** `presenter` moved from `UnitVisualAdapter` to `CharacterRig`, so both hosts (tactical visual, workbench) have one. Both call `presenter.tick(delta)` once per frame from their own `_process`, at the same position as before. The workbench uses `set_scripted_motion(speed, heading_rate)`, which feeds authored preview motion exactly as given (including a heading rate while idle) and replaces the movement inference; the adapter keeps the authority/inference path. `presentation_frame_driver_test` proves on both hosts: exactly one tick per frame, before that frame's modifiers, identical elapsed presentation time, and the idle heading rate preserved. Text-level ratchets in `animation_module_boundaries_test` fail if any host calls the locomotion feed or writes the crouch ramps directly. Both hosts still ARE the rig, so this is **one shared driver implementation, not yet the single node-level driver**.

**Cover posture.** `UnitVisualAdapter._sync_cover_crouch` is now only cover POLICY: it computes what the cover asks (depth request, yaw offset, kneel or crouch) and calls `presenter.postures.set_posture(&"tactical/cover", ..., PRIORITY_CONTEXT, yaw_offset, depth)` (or `release`), then `presenter.apply_posture(delta, cover_profile)`. The arbiter resolves; `CharacterRig.apply_posture_target` is the only writer of the crouch depth, kneel blend and body yaw ramps (profile speeds, shortest-way yaw). `PostureArbiter` gained a `depth` field (metres of lowering the requester wants; carried, never interpreted); identical repeats stay no-ops. Cover-edge selection, the target-aware attack plan and the held-cover-through-hit rule stay in the adapter. The workbench's cover demo (`workbench/cover`, CONTEXT) and diagnostic pose preset (`workbench/pose_preset`, BASE) use the same two calls, so a demo outranks a preset and releasing either returns to the other or to standing. `posture_ownership_test` pins request flow, idempotence, arbitration, ramp continuity, kneel, and release on leaving cover, defeat and teardown.

**Removed.** The adapter's `_crouch_depth`/`_kneel`/`_cover_yaw` ramp writer and constants (`CROUCH_SPEED`, `KNEEL_SPEED`), the unused `_cover_crouch_target`, and the workbench's direct ramps and locomotion call. The ramp state (`_crouch_depth`, `_kneel`, and `_cover_yaw` as an accessor of the visual root's yaw) now lives in the rig under the same names, so existing tests that read them are unchanged.

**Still outside the presenter** (compatibility paths for later packages): facing set by `face_world_position`, `begin_turn` and the cover yaw absorption; cover side selection, the attack plan and the held cover kind; aim hold, readiness, attack/recover timelines; rescue and carry, which still write the crouch directly (`character_rig.gd` `end_carry` and the carry sample); traversal state; the workbench's turn preview, which still writes the visual root's yaw itself. Whole-body overrides (the arbiter's override layer) are implemented but not used by production yet.

**Measured.** Idle adapter `_process` 0.018 to 0.020 ms per character against the Package 2 numbers (the per-frame request bookkeeping); modifier stack unchanged. Rendered cover poses (low 0.9 m, full 2.0 m, kneel 0.4 m, standing) are pixel-identical to the previous commit's; the aiming and idle captures differ from run to run on the same code, so they could not be compared.

## Package 4 update: typed modifier inputs, supported callback, pose ownership

**Measured before and after** (actual counts, not estimates)

| | Before | After |
| --- | --- | --- |
| String-keyed modifier-to-rig accesses | 32 (11 in Traversal, 13 `rig.get` and 7 `rig.call` in WeaponPose, plus one nested `anchor_world` call on the passenger) | 0 (a text ratchet in `animation_module_boundaries_test` fails if one returns) |
| Modifiers using the deprecated `_process_modification()` | 5 | 0 (all five implement `_process_modification_with_delta`) |
| Modifiers that know `CharacterRig`, the presenter or gameplay | 2 (held a `rig` reference) | 0 (ratchet) |
| Declared pose-write overlaps / undeclared conflicts | none declared (unknown) / not detectable | 4 declared / 0 (validated; see `PoseOwnership`) |
| Pose-trace difference against the previous commit | n/a | 0.000000 m on every bone and IK target and 0.064 degrees of rotation noise (the run-to-run floor of the comparison) over 9 scenarios, 1,350 frames |
| Idle cost per character (adapter / stack) | 0.018 to 0.020 ms / 0.010 ms | 0.019 to 0.020 ms / 0.010 ms (unchanged) |

**The boundary.** Each access was classified and given the interface that fits it, instead of one large input object:

| Kind | Examples | Now |
| --- | --- | --- |
| Persistent configuration | skeleton, bone names, character root, arm IK, support target, crouch modifier | `WeaponPoseBinding` (built once; wiring, never per-frame) and `TraversalPoseModifier.setup` / `bind_legs` arguments |
| Live tuning | support protraction limit, comfort angle, solve iterations | `WeaponPoseSettings`, shared by reference; the rig's inspector properties read and write it (tests that retune them keep working, nothing is copied) |
| Per-frame presentation input | the traversal and stair pose | `TraversalPoseInput`, published by the rig whenever the traversal or stair state changes (ladder over stairs, exactly as before) |
| Operations needing the same-pass shoulder and chest | place carry, weapon and traversal-hand targets, torso frame, elbow guidance | `PoseTargetPlacer` (7 typed methods). The modifier owns WHEN and supplies the same-pass poses; the rig (`RigPoseTargets`) owns the formulas and the targets. A recording fake replaces it in `modifier_boundary_test`, so the weapon-pose modifier is now testable without a rig |
| Contact or IK target nodes | foot targets, knee poles | injected once (`bind_legs`), written by the modifier |
| Derived skeletal information | chest-in-root, same-pass shoulder | measured inside the pass by the modifier and passed as arguments |

Why this is simpler than before: a modifier names exactly what it needs in one typed place; renaming a rig member no longer silently breaks a string at run time; the dependency points one way (the rig builds and feeds modifiers; modifiers import neither the rig nor the presenter). The new types are small and single-purpose, and `RigInput` was not grown.

**Callbacks (Godot 4.7.2).** All five modifiers now use `_process_modification_with_delta(delta)`. Verified by tests: the delta handed on is exactly the engine's frame delta, also under `Engine.time_scale = 0.5` (a mutation that scaled it again was caught); influence is applied once by the engine (the locomotion twist at influence 0.5 is half the turn at 1.0); every modifier runs at delta 0; the modifier order and update-order tests are unchanged. WeaponPose is the only stage that used the delta; it now gets it as an argument instead of `get_process_delta_time()`.

**Pose ownership.** `PoseOwnership` (`presentation/characters/rig/pose_ownership.gd`) declares the stage order, each stage's writes (ADD, REPLACE_COMPONENT, OVERRIDE, TARGET) and the four intended ordered overrides (pelvis position CoverCrouch then Traversal; thigh and shin Locomotion, CoverCrouch, leg IK; support clavicle CoverCrouch then WeaponPose). `validate()` fails on an undeclared conflict, a declared overlap out of modifier order, a stale overlap, an IK target with no later solver, or a table that disagrees with the skeleton's real modifier order. The runtime half of `pose_ownership_test` runs each stage alone against a control and fails on any bone the stage has not declared (a deliberate undeclaration was caught). It is not a one-writer rule: additive writes, the F-04 component replacement and declared overrides are allowed. Locomotion twist plus crouch (spine: additive twist, replaced flexion) and traversal hips plus posture are declared cases.

**Remaining legacy inventory, with removal points**

| Item | Where | Removal point |
| --- | --- | --- |
| Rescue and carry write the crouch directly (`end_carry` reset and the carry sample at pickup) | `character_rig.gd` (4 assignments) | **An ownership violation, recorded:** the rescue/action package should route them through `presenter.postures` (an ACTION-priority source) and delete the writes |
| `traversal`, `traversal_pose`, `stair_state` and `stair_pose` dictionaries stay the rig's own state (the modifier no longer reads them) | `character_rig.gd`; read by `animation_cleanup_test`, the traversal and stair tests, the workbench | typed state objects when the traversal lifecycle moves into the presenter |
| `CoverCrouchModifier.setup(bones: Dictionary, ...)` and `LocomotionPoseModifier.setup(..., axes: Dictionary)` take dictionaries; `crouch_pose` is a solver-result dictionary | the two modifiers (3 `Dictionary.get` reads) | typed bone and axes configuration from `ResolvedRig` when the rig profile starts driving configuration |
| Modifier public fields (`twist_degrees`, `depth`, `kneel`, ...) stay writable | modifiers | tests and tools write them; convert with the private-state test migration |
| `AnimationTree.set("parameters/...")` string paths | `character_animation_controller.gd` (5) | Godot's own AnimationTree API, not rig reflection; keep |
| `RigPoseTargets` delegates to rig methods | `character_rig.gd` | the formulas stay in the rig by design (they need weapon, carry and torso state); revisit when equipment becomes data |
| Bone names still literal in the rig and in the weapon binding | rig | `ResolvedRig` roles (rig-profile adoption) |
