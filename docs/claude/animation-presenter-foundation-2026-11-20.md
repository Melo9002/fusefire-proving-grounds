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
