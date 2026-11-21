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

**Still outside the presenter** (compatibility paths for later packages): facing set by `face_world_position`, `begin_turn` and the cover yaw absorption; cover side selection, the attack plan and the held cover kind; aim hold, readiness, attack/recover timelines; rescue and carry (they requested posture from the arbiter from Package 5 on; see below); traversal state; the workbench's turn preview, which still writes the visual root's yaw itself. Whole-body overrides (the arbiter's override layer) are implemented but not used by production yet.

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
| ~~Rescue and carry write the crouch directly (`end_carry` reset and the carry sample at pickup)~~ | `character_rig.gd` (4 assignments) | **Resolved in Package 5:** they request posture from `presenter.postures` at ACTION priority and the writes are deleted |
| `traversal`, `traversal_pose`, `stair_state` and `stair_pose` dictionaries stay the rig's own state (the modifier no longer reads them) | `character_rig.gd`; read by `animation_cleanup_test`, the traversal and stair tests, the workbench | typed state objects when the traversal lifecycle moves into the presenter |
| `CoverCrouchModifier.setup(bones: Dictionary, ...)` and `LocomotionPoseModifier.setup(..., axes: Dictionary)` take dictionaries; `crouch_pose` is a solver-result dictionary | the two modifiers (3 `Dictionary.get` reads) | typed bone and axes configuration from `ResolvedRig` when the rig profile starts driving configuration |
| Modifier public fields (`twist_degrees`, `depth`, `kneel`, ...) stay writable | modifiers | tests and tools write them; convert with the private-state test migration |
| `AnimationTree.set("parameters/...")` string paths | `character_animation_controller.gd` (5) | Godot's own AnimationTree API, not rig reflection; keep |
| `RigPoseTargets` delegates to rig methods | `character_rig.gd` | the formulas stay in the rig by design (they need weapon, carry and torso state); revisit when equipment becomes data |
| Bone names still literal in the rig and in the weapon binding | rig | `ResolvedRig` roles (rig-profile adoption) |


## Package 5 update: rescue posture ownership and the first production ActionHandle

**What changed, in one paragraph.** The rescue lift (pickup, carry, release) no longer writes the crouch. It asks the posture arbiter for a body through an ACTION-priority request, and the rig applies whatever the arbiter resolves. The lift is also the first production user of `ActionHandle`: `begin_pickup`, `begin_release` and `UnitVisualAdapter.present_pickup` return one, it settles exactly once, and the tactical action presenter waits on it instead of polling the timeline. The existing `RescueInteraction` timeline, the passenger components and every offset, depth and timing were kept; nothing about the gameplay rescue (legality, occupancy, AP, objective state) was touched.

**Measured before and after**

| | Before | After |
| --- | --- | --- |
| Direct rescue crouch writers (`crouch_modifier.depth`/`kneel`) | 4 (`end_carry` reset 2, carry sample 2) | 0 (the only writers left are the two assignments in `apply_posture_target`; a ratchet in `animation_module_boundaries_test` fails on a third) |
| Independently advancing rescue timelines | 1 (`RescueInteraction`, advanced once per frame by the rig) | 1 (unchanged: no second clock was added; the presenter and adapter do not run one) |
| `ActionHandle` production integration points | 0 | producers: `begin_pickup`, `begin_release`, `present_pickup`, `reserve_rescue_handle`; observers: the adapter's post-pickup reaction, the adapter's pending-pickup cancel, `TacticalActionPresenter._wait_for_rescue_interaction` |
| Legacy rescue completion signals | 2 (`rescue_interaction_finished`: 1 production and 2 test consumers; the unused `RescueInteraction.finished`) | 0 (both removed; a ratchet fails if the name returns) |
| Duplicated rescue state | the crouch depth lived in the modifier, the rig's ramp and the rescue sample | one request (arbiter), one applied state (rig ramps); the modifier only receives it |
| Pose-trace difference against `2fdb665` | n/a | 0.000000 m on every bone, IK target and passenger anchor (passenger 0.00005 m, rotation 0.067 degrees: the run-to-run noise floor, see Equivalence) over 13 scenarios including the 4 rescue ones |

**The four writers, classified.**

| Where | What it did | Now |
| --- | --- | --- |
| `_apply_carry_posture`, 2 lines | set depth and kneel from the lift sample every frame | `_request_rescue_posture(sample)`: one ACTION request (`presentation/rescue`), exact, carrying the sample's depth and kneel blend |
| `end_carry`, 2 lines | zeroed depth and kneel when a carry ended | release of that request, then `_snap_posture_to_requests()` (the rig applies where the REMAINING requests resolve, at once) |

**Arbiter extension (shared, not rescue-specific).** A request may now carry an explicit `kneel` blend (-1 keeps the derive-from-depth behaviour cover relies on) and an `exact` flag meaning "the requester already shapes the motion; follow it without easing". Both are carried with the winner and never interpreted by the arbiter; both take part in the idempotency comparison. The rig's `apply_posture_target` follows an exact request as given and keeps its ramps where it left them, so the next ordinary request eases from there. This is what lets an authored timeline (whose crouch and kneel are independent curves) be expressed as a request without changing a single value. Priorities were not invented for the lift: it uses the existing `PRIORITY_ACTION` tier, above cover (`PRIORITY_CONTEXT`) and below `PRIORITY_FORCED`.

**Why the request is applied inside the carry update.** The host applies the resolved posture before the weapon-pose update, and the lift's sample for THIS frame is computed after it. `_request_rescue_posture` therefore applies once more with a delta of 0 (an exact request moves no ramp), so the pose this frame is this frame's sample, as before, and no ramp advances twice.

**The handle.** One handle per rescue operation (a pickup or a release); it describes the visual operation, never the gameplay result.

| Outcome | When |
| --- | --- |
| COMPLETED | the timeline ran out |
| SKIPPED | the timeline was run to its end at once (`finish_interaction_now`: the carrier walks off or boards), a release that was rejected (nobody carried, or a pickup still running) and a pickup with no place to lift from (the passenger just appears) |
| INTERRUPTED | something ended the carry under it: `end_carry` (carrier fell, hit, freed), defeat, a new pickup that supersedes a release, the character leaving the tree |
| CANCELLED | the requester called `cancel()`: a pickup leaves no passenger and the rifle back in hand, a release leaves the passenger carried |

State is derived, not mirrored: `RescueInteraction.kind` plus the handle slot give "idle / lifting / carrying / lowering / reserved". A repeated pickup or release returns the running handle (no restart); a release during a pickup is rejected. The slot is cleared BEFORE observers run, so an observer that starts a release in its callback finds a clean rig (tested), and a release's passenger is freed before its handle settles. A pickup that has to wait for its carrier to arrive reserves its handle immediately (`reserve_rescue_handle`), which the lift takes over on arrival; losing the carrier or boarding interrupts it, and a cancel stops the lift from starting. The rig settles INTERRUPTED when it leaves the tree, so a wait never outlives the character.

**Commit first, present afterwards.** Unchanged. `TacticalActionPresenter._wait_for_rescue_interaction` now takes the running handle (`rescue_presentation()`; a pickup still waiting for its carrier is not running, as before) and waits for it to settle within the same bound (lift length plus half a second). Cancelling or interrupting the handle returns the action at once and changes no result (tested through the production mission: a cancelled lift still returns `true`, the carrier still carries).

**Equivalence.** `tools/quality/pose_trace.gd` gained four rescue scenarios (pickup with the carrier then walking, a release, a pickup interrupted over a cover posture, a pickup cancelled by `end_carry`) and records the passenger's transform, the lift phase and time, and the carrier's position, so pickup start, contact, attachment, carrying, release start and completion are all compared frame by frame against `2fdb665`. Result: no bone, IK target, passenger, phase, crouch, kneel or position difference above the noise floor (two runs of unchanged code differ by 0.067 degrees and 0.00005 m on the passenger). This is a numerical result; no rendered capture was made for this package, so visual equivalence is not claimed.

**Intentional behaviour differences.** None observed in the traces. Two are by construction and covered by tests rather than traces: (1) a lift ending over a cover request now hands the body to the cover request at once instead of to standing then easing to cover (the arbiter, not the rescue, decides what follows); (2) a defeat during a lift stops the timeline and interrupts the handle (before, the lift kept running on a defeated carrier until the tactical layer's release freed the passenger).

**Temporary compatibility, with removal points**

| Mechanism | Removal point |
| --- | --- |
| The adapter holds `_pending_pickup_world`/`_pending_lying_basis` for a pickup awaiting arrival (the handle is reserved in the rig) | when movement completion becomes a presenter action the pending state is the action's own |
| ~~`_apply_carry_posture` advances the lift clock~~ | **Resolved in Package 6:** the presenter's action stage advances it for both hosts; `_apply_carry_posture` only applies the sample |
| `rig.preview_carrying` (hosts without a tactical unit) | the rig-composition package |
| ~~The no-place pickup returns to idle with `_return_to_idle_after`~~ | **Resolved in Package 6:** `presenter.begin_hold`, with a handle |

**Remaining cleanup and interruption hazards.** The tactical wait polls `handle.is_done()` once per frame (it needs a deadline; `ActionHandle.wait()` has none). A character re-added to the tree after being removed mid-lift has had its operation interrupted. The passenger node itself is still freed by `end_carry`, not by the handle. Attack, aim, hit and defeat timelines are not migrated.

**Tests.** `rescue_presentation_handle_test` (47 checks; production visual and a production mission): normal pickup and release, repeated requests, cancellation before attachment, mid-lift and mid-release, interruption after attachment, defeat during a lift and while carrying, teardown with a pending `wait()`, skipped, several observers, a re-entrant observer, cover restored when the rescue releases and the cover request never cleared by it, unrelated sources untouched, no leaked request or passenger, and the authoritative result independent of the handle (three mutations were caught: a posture never released, teardown not settling, a repeated pickup restarting). `posture_arbiter_test` gained the kneel and exact checks; `rescue_interaction_test` observes the handles instead of the retired signal; the boundary test ratchets the writer count and the retired signal.

**Validation status and caveats (Package 5).** Passed: changed-file selection 60/60; wide targeted batch 22 passed and 1 skipped (`hand_contact_capture`, an explicit-only rendered capture that was not run); animation FAST tier 22/22; catalog check. The full regression tier was not run. The warning audit (`tools/scan_script_warnings.gd`) is NOT clean: it scanned 540 scripts and printed parse errors, all from `artifacts/ai-audit-probe.gd`, a gitignored, untracked disposable probe dated 2026-11-17 (referenced in `docs/quality/ai-audit-2026-11-17.md`) that predates this package, is not loaded by production or any test, and fails to parse on an `evaluate()` argument type. No warning or error was reported for any file this package touched. The probe was left as it is.


## Package 6 update: combat action presentation and lifecycle consolidation

**One correction first.** The Package 5 rescue trace scenarios never set `preview_carrying`, so the lift clock never advanced in them and the trace compared static poses; the "identical to `2fdb665`" statement for pickup and release was not demonstrated. They are fixed (`pose_trace.gd` now sets it) and Package 5 was re-checked against its parent with the real lift running: pickup, release, cancel, cover return and carry are identical to the noise floor (one 0.0004 crouch difference on the frame the lift completes). The one real difference is the defeat during a lift, which is the intentional Package 5 interruption (a defeated carrier's lift stops; before, it ran on). That row of the Package 5 report ("none observed") was wrong for defeat.

**What moved, and what did not.** The attack lifecycle, the aim hold's state machine, the timed return of finite states (hit, landing, a pickup clip), the defeat and the rescue clock are now the character's `CharacterPresenter`'s, advanced from its own `tick` (timed states) and `advance_actions` (attack, rescue clock), once per frame, with the engine's delta and settled through `ActionHandle`s. The adapter keeps the POLICY and the body: which clip, the cover plan, the readiness request, the tactical "is it moving/carrying" reads. Nothing was copied to a second implementation; `WeaponReadiness` stays the rig's and is read.

**Inventory (before, owner, after, removal).**

| Responsibility | Before | After | Status |
| --- | --- | --- | --- |
| Attack RAISE, ALIGN, FIRE, RECOVER, RELEASE and its timeline | adapter (`_advance_attack`, `_fire_shot`, `_release_attack`, `_finish_attack_sequence`, `attack_phase`, `attack_timeline`, `_recover_left`) | `presenter.attack` (`AttackSequence`), host-driven through `AttackHost` | moved, old removed |
| Attack completion signal | `attack_sequence_ended`, `shot_fired`, `is_attack_pending()` polling | `AttackHandle` (completion) with `.shot` (the shot is shown), `presenter.attack.shot_released` | moved, old removed |
| Aim hold state and release grace | adapter (`_aim_held`, `_aim_release_left`, `AIM_RELEASE_GRACE`) | `presenter.aim` (`AimHold`); persistent, never a handle | state moved; per-frame call still the adapter's (below) |
| Hit return, landing return, pickup-clip return | scene-tree timer plus a generation counter shared by all three (`_return_to_idle_after`, `_return_generation`) | `presenter.begin_hold(seconds, due)` / `cancel_hold()`, counted by the presenter's tick; hit and the clip hold return a handle | moved, old removed |
| Hit presentation | adapter, no completion | `present_hit()` returns an `ActionHandle` (COMPLETED at the return, INTERRUPTED if superseded, SKIPPED on a ladder) | integrated |
| Defeat | adapter, clip replayed on every call | `present_defeat()` returns an `ActionHandle` (COMPLETED after the clip's own length, INTERRUPTED on removal); a repeat while it runs is the same defeat | integrated |
| Rescue clock | advanced inside `_apply_carry_posture`, called from the adapter's and the workbench's weapon-pose update | `presenter.advance_actions` calls `rig.advance_rescue_clock`; both hosts call the same stage; the rig only applies the sample | moved, old call removed |
| Presentation clock alias | `_presentation_clock` | `presenter.time` | removed |
| Facing (`face_world_position`, cover yaw absorption, `begin_turn`) | adapter | adapter | **deferred**: it needs the cover kind and the tactical moving state |
| Pending pickup (`_pending_pickup_world`, `_pending_lying_basis`) | adapter | adapter | **deferred**: it waits for the tactical unit's movement to end; the handle is reserved in the rig and settles on removal |
| Aim hold's "should it hold" read and the per-frame `update` call | adapter | adapter calls `presenter.aim.update` | **transitional**: removed when the presenter reads a typed committed-aim input instead of the adapter reading `tactical_state` |
| `WeaponReadiness` and the weapon blend | rig | rig | unchanged by design (read, not copied) |
| Clip selection, cover plan, shot-state choice | adapter | adapter | unchanged: tactical and cover policy, equipment-specific clips |

**Interruption precedence (implemented and tested).** Defeat ends everything (attack INTERRUPTED, aim hold cleared, readiness cleared, hit hold INTERRUPTED, a rescue interrupted by Package 5's path) and plays the one-shot defeat. A hit ends a running attack and the aim hold carries on underneath. A newer attack ends the running attack and any hit hold. A newer hit supersedes the running hit. Removal settles every outstanding handle INTERRUPTED and clears the hold, the defeat, the attack and the aim hold. A requester's `cancel()` on an attack withdraws it (CANCELLED, the shot handle INTERRUPTED). This keeps today's rule "the newest request wins, defeat is terminal"; it differs from the contract table (hit above carry above attack), which is deferred until a hit during a lift needs it.

**Handles settle once, observers are safe.** `AttackHandle` carries two milestones: `shot` (COMPLETED when the shot is shown, SKIPPED when forced for a character that cannot sequence, INTERRUPTED if the attack ends first) and the attack itself (COMPLETED at the end of the release, SKIPPED for a forced one, INTERRUPTED or CANCELLED). The slot is cleared before observers are told, so an observer may start the next attack from its callback (tested). The tactical presenter waits on `handle.shot` with its existing 3 s deadline; the handle never decides whether the attack succeeded (a production test cancels the handle mid-raise: the committed result, the attacker's AP and the target's HP are untouched).

**Timing.** A timed state counts down from the frame after it began, like the scene-tree timer it replaced, so the hit returns on the same frame as before (an earlier version of the countdown returned one frame early; the trace caught it). The defeat clip length is read from the animation (1.2 s), not repeated as a constant.

**Equivalence (`pose_trace.gd`, 26 scenarios, 13 new combat ones).** Against `3a5a63e` with the same trace: bone and IK target differences 0.000000 m and 0.064 degrees (the run-to-run floor) in 25 of 26 scenarios, including attack from idle, aimed, low cover, full cover and repeated; hit while idle, aiming and attacking; defeat during aim; aim release; rescue pickup, release, cancel, cover return, defeat and the hit-versus-pickup-clip timer. The attack timelines (phase list, times, fire time, end time, forced, cancelled) are identical in all 7 scenarios that record one, and so are the animation state, readiness level, attack phase and aim blend per frame. The single difference is `defeat_during_attack`: a second defeat request used to restart the defeat clip; it is now the same defeat. That is an intentional change (the contract asks for idempotent repeats), not frame-order noise. Numerical evidence only; no rendered capture was made.

**Remaining tactical-adapter responsibilities** (after, not "moved"): facing and the cover yaw absorption; the cover posture request and the cover plan; the shot-state choice and the cover side; clip selection for every state; the pending pickup; the tactical movement and carrying reads; the traversal tick; the aim hold's per-frame call; the rescue sample's application (the rig's). `preview_carrying` stays because it is a genuine non-tactical capability: a host with no tactical unit (the movement ghost, the workbench, tools and tests) declares "this character is a loaded carrier" through it, exactly as a tactical unit's `is_carrying_unit()` does for the game; it is not a compatibility path for tactical code.

**Retired.** Methods: `_advance_attack`, `_fire_shot`, `_release_attack`, `_finish_attack_sequence`, `_cancel_attack_sequence`, `_note_attack_phase`, `_return_to_idle_after`, `_retarget_aim_blend` (a no-op that tests still called), `is_attack_pending` (adapter and `TacticalUnit`). State: `attack_phase`, `attack_timeline`, `_aim_held`, `_aim_release_left`, `_attack_shot_state`, `_recover_left`, `_return_generation`, `_presentation_clock`, `AttackPhase`, `ATTACK_SOURCE`, `AIM_RELEASE_GRACE`; signals `shot_fired`, `attack_sequence_ended`. The adapter went from 867 to 781 lines. A ratchet in `animation_module_boundaries_test` fails if any of them returns, if the adapter starts a scene-tree timer, or if anything but `CharacterRig.advance_rescue_clock` advances the rescue clock.

**Tests.** `combat_presentation_lifecycle_test` (49 checks; fakes and production): the pure attack lifecycle with a recording host, the aim hold, the presenter's timed states; production attacks from idle, repeated, interrupted by a hit, a defeat, a newer attack, a cancel and removal; hit return timing; defeat idempotence and completion; defeat during a rescue; the aim hold never pending; the rescue clock through the presenter in the tactical host AND the workbench, once per frame; and the authoritative result untouched. Three mutations were caught (teardown leaving an attack, a non-idempotent defeat, a finish that skips the shot handle). Existing tests that read the retired private fields were moved to the presenter's public members (`presenter.attack`, `presenter.aim`, `presenter.time`) or to handles.


## Package 7 update: adapter boundary and facing ownership

**What changed.** The presenter now owns visual facing, the committed Aim's progression, the pending pickup and the defeat-removal floor; the tactical adapter translates tactical facts into typed requests and writes no yaw, holds no pickup state and runs no aim-hold progression. The rig only applies. Nothing about gameplay (Shield rules, AP, defeat, replay outcomes) was touched.

**Facing (typed, small).** `CharacterPresenter` gained `face_point`, `face_yaw`, `face_authoritative`, `turn_toward_yaw` (an eased node turn: a ladder's heading), `turn_root_toward` (an eased visual-root turn: the workbench's preview), `hold_facing` / `release_facing_hold`, `facing_direction()` (read-only) and `facing_mode` / `authority_yaw` for the snapshot. The cover decision stays the context's: the adapter passes `absorb_into_cover` (a tactical cover kind and "standing still"), and the rig applies the change (`apply_facing_yaw`, `apply_root_yaw`, `absorb_facing_change`, the only yaw writers in a rig with the cover-yaw ramp). Turning rates, target spaces and cover behaviour are unchanged (see Equivalence).

**Authoritative facing: decision and evidence.** The presenter shows a committed yaw exactly as supplied and reports it (`has_authority_yaw`, `authority_yaw`, FACE_YAW); a later facing request of any kind replaces it. The Shield stance is connected through that route: `present_shield` now shows `tactical_state.shield_facing` when the stance is established, and falls back to facing the threat's position otherwise. The committed direction is built from the same cell centres the units stand on, so the shown yaw is the direction toward the threat the unit used to face: the production test places five threats around a guard and measures a worst difference below 0.01 degrees, with the committed facing shown to within 0.0001 radians. The Shield does not lock the visual facing afterwards (the unit still turns to fire at another target): locking it would change what is visible and is a mechanic decision, not part of this package.

**Committed Aim.** The adapter reports `presenter.aim_committed = _aim_should_hold()` each frame (a tactical read translated into a typed input); `presenter.tick` progresses `AimHold` (engage, grace, release) in the same slot as before and emits `aim_hold_changed`, to which the adapter reacts by re-settling a quiet pose. The presenter reads no tactical type (a ratchet scans for it). The committed Aim persists through a hit; a hold in its grace period is ended by any other action, as before.

**Pending pickup.** `PendingPickup` (world position, lying basis, the reserved handle) lives in the presenter: `hold_pickup`, `has_pending_pickup`, `arrive_pickup(begin)`, `cancel_pending_pickup`. The adapter's `present_pickup` and `present_movement_end` call them; cancelling, a defeat, boarding, the target being incapacitated again and teardown all settle the reserved handle. `UnitVisualAdapter` keeps only the public query `pickup_pending()`.

**Defeat and removal.** `begin_defeat` now keeps the defeat handle for good, so a repeat (running or finished) is the same defeat and never restarts the clip, and `is_defeated()` is terminal. `TacticalUnit.finish_defeat_presentation` no longer owns a 1.25 s timer for a character with a lifecycle: it waits on `presenter.removal_handle(1.25)`, which settles when the defeat clip has finished AND 1.25 s of presentation time have passed since the request (INTERRUPTED if the character is removed), bounded by a 6 s deadline. A unit whose visual does not process keeps the plain 1.25 s floor (the one remaining timer, documented and ratcheted).

**Replay camera.** `battle_replay_player` asks `TacticalUnit.get_presentation_facing()` (the presenter's read-only horizontal facing) for a camera focus point; it no longer reads the adapter's transform. No replay outcome depends on it.

**Workbench parity.** `CoverEdgeSelector.shot_state(full_cover, plan, passive_side)` is the one decision for which shot a cover plan shows; the tactical adapter and the workbench both call it (the workbench had its own copy). The workbench's cover-target turn and square-up use `presenter.face_yaw` and its idle preview turn uses `presenter.turn_root_toward`; neither writes a yaw.

**Interruption precedence (Task 04 section 14, as implemented).** Implemented: defeat is terminal and refuses every later hit, attack and pickup (CANCELLED, no clip, no hold); a hit ends a running attack (as before); persistent aim blocks nothing and a hit never cancels it while committed. Intentional differences from the contract table, each tested:

| Contract | Implemented | Why |
| --- | --- | --- |
| hit outranks carry/release (the lift is suspended) | a hit during an active lift or release is SKIPPED: no clip, no hold, the lift carries on | a lift cannot be suspended and resumed without a design (the passenger is attached), and the rescue is already committed; by reading the code, the hit clip was overwritten by the lift's next frame and the hold's return briefly forced a carry clip |
| hit outranks attack (a newer attack waits) | a newer attack ends a running hit reaction (the hit settles INTERRUPTED) and the committed shot shows on time | reaction fire follows the hit it answers within the reaction's 0.58 s (`present_attack_impact`, then the guard return); deferring the attack would delay a committed shot and change the sequencing the tactical layer waits on |
| defeat outranks everything | as contracted, plus the defeat is terminal (later requests refused) | none |

No generic scheduler was added: precedence is a few early checks in the adapter's request methods and the presenter's existing slots.

**Equivalence.** `pose_trace.gd` gained five facing scenarios (facing from idle with repeats, in low cover, in full cover aiming then attacking, during a hit reaction, and a walk with turns then a facing change); it records the node yaw and the visual root yaw. Against the committed Package 6 code (`d171913`): 31 of 31 scenarios identical to the noise floor, including every attack, hit, defeat, rescue and facing scenario, the attack timelines and the per-frame state, readiness, aim blend, node yaw and root yaw. The ladder heading and the committed-Aim progression need a tactical unit and are covered by production tests (`traversal_ladder_gameplay_test`, `aim_hold_presentation_test`, `adapter_boundary_test`), not by the trace. There are no intentional pose or timing differences in this package; the behavioural differences are the precedence rules above, which no trace scenario exercises.

**Retired.** Adapter: `_pending_pickup_world`, `_pending_lying_basis`, `_pending_handle`, `_on_pending_pickup_settled`, `_clear_pending_pickup`, `_sync_aim_hold`, four direct yaw writes (`rotation.y` twice, the cover yaw, the visual root yaw). Workbench: five direct yaw writes and its copy of the shot decision. `TacticalUnit`: the unconditional defeat timer. Ratchets in `animation_module_boundaries_test` fail on any of them returning: no yaw write in the adapter, workbench, `TacticalUnit` or the tactical presenter; exactly five in the rig and one (velocity follow) in the presenter; no tactical read in the presenter; one remaining timer in `TacticalUnit`; no adapter-transform read in the replay player.

**Tests.** `presenter_facing_test` (32 checks: point, yaw, hold, velocity, authority, eased turns, cover absorption without a jump, the shot-decision table, the workbench, and the Shield wiring on production units) and `adapter_boundary_test` (35 checks: the committed Aim through a production unit, defeat removal timing and floor, removal mid-defeat, a non-processing visual, the precedence table, pending pickup arrival, cancellation, defeat and teardown on a production mission, and the replay facing hint). Three mutations were caught (removal floor ignored, cover absorption dropped, refusal after defeat dropped). `combat_presentation_lifecycle_test` now expects a hit after a defeat to be refused.

**Count reconciliation (Package 7 trace).** The trace file holds 31 scenarios plus a `__meta` key (the attack timelines), so its top-level key count is 32. The generator's log line printed that key count (32); the comparison script skips `__meta` and compared the 31 real scenarios, each frame by frame, plus the 31 recorded timelines. The log line now prints the scenario count.
