# Task 10: capability and ownership audit (2026-11-22)

Baseline: `main` at `f115aa1` (Task 09 plus its review fixes), in sync with `origin`; only the six historical Kenney `colormap.png.import` edits and two generated `docs/claude/images/*.svg.import` files were uncommitted, and they were left alone. Task 09's issue (#51) is open for owner sign-off only. No issue tracked Task 10.

This is the matrix the implementation was built from. It is deliberately about *ownership*: who asks, who ranks, who picks the clip, who advances time, who finishes, who interrupts.

## Matrix

Legend. **Request**: who asks. **Rank**: who decides what wins. **Clip**: who picks the clip or procedural behaviour. **Time**: who advances it. **Finish**: who decides it is over. **Interrupt**: who ends it early. **Stages**: skeletal stages it touches (`PoseOwnership.STAGE_ORDER`).

| Capability | Request | Rank | Clip | Time | Finish | Interrupt | Effect on other capabilities | Stages |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Idle, walk, jog, run | host `report_velocity` / `set_movement_authority` | presenter (`moving` inference) | host `_select_state` (exploration) or `present_idle`/`_return_from_hold` (tactical); gait blend is the rig's (speed) | `presenter.tick` feeds rig; the AnimationTree runs the clips | persistent: never | any one-shot (host cancels it) | coexists with weapon carry, crouch | Locomotion (ADD) |
| Turn, facing | host `face_*`, velocity | presenter (`facing_mode`, hold) | none (hips catch up in rig) | rig `begin_turn` | settles by easing | a newer facing request replaces | none | Locomotion twist |
| Crouch, kneel, cover | host (`set_crouched`, `enter_cover`) | `PostureArbiter` (priority then recency) | none: procedural | rig eases toward the resolved depth | persistent | released by the requester; suspended on stairs and ladders by the host | owns legs/pelvis; weapon pose adds on top | CoverCrouch (OVERRIDE legs/pelvis) |
| Weapon readiness, aim | host (`set_aiming`) / tactical aim hold | `WeaponReadiness` + `AimHold` | `aim` clip state (host) | host `_advance_aim`, rig blend | persistent | lowered by the requester | weapon follows the hand through every posture | WeaponPose, WeaponArmIK, HandGrip |
| Attack (raise, align, fire, recover) | host `fire` / `present_attack` | `AttackSequence` (cancelled by hit, defeat, newer attack) | host `AttackHost.play_shot` | presenter `advance_actions` | the sequence's `AttackHandle` | hit, defeat, a newer attack | needs a weapon; refused while carrying | WeaponPose |
| Hit reaction | host `react_hit` / `present_hit` | defeat > hit; SKIPPED while a rescue lift runs or on a ladder (tactical) | `hit` clip, host | presenter hold | hold ends (COMPLETED) | defeat; a newer hold | ends a running attack | clip only |
| Defeat | host `defeat` / `present_defeat` | terminal: outranks everything, later requests CANCELLED | `defeat` clip | presenter `begin_defeat` | clip length | removal | ends hold, aim, attack, cover, traversal, rescue | clip only |
| Rescue pickup, carry, release | host (`pick_up`, `present_pickup`) | rig `interaction_active`; pending pickup in presenter | `RescueInteraction` timeline + `pickup`/`carry_*` clips | rig `advance_rescue_clock` | timeline end (handle) | defeat, boarding, carrier falls | refuses attack, aim; coexists with walking (loaded gait) | WeaponPose, rig attachments |
| Stairs, ladders | host `begin_stairs` / `begin_climb` | host (crouch suspended while on them) | none: contacts do it | controller reports progress | host ends | defeat | legs owned by the contact stages | Traversal, TraversalLegIK, TraversalFoot |
| Inspection (exploration) | host `inspect` | one at a time (own handle) | none (crouch posture request) | presenter hold | hold ends | walking away, a newer hold, defeat | uses the posture arbiter, not a clip | CoverCrouch via posture |
| Equipped vs unarmed | scene (`weapon_scene`) | rig (`has_weapon`) | different clip states (`aim` needs a weapon) | n/a | n/a | n/a | selects readiness paths | arm stages only when equipped |

## Retained (working contracts)

* **One presenter tick per frame** from the host, `advance_actions` guarded per frame, handles settle exactly once. Everything one-shot already rides `ActionHandle`.
* **Persistent versus one-shot** is already a real separation: postures, readiness, aim, facing are idempotent requests; hits, attacks, rescue, defeat, inspection are handles. No change needed.
* **Defeat is terminal and outranks everything.** Kept exactly.
* **`PostureArbiter`** (source-keyed, priority, recency) and **`PoseOwnership`** (declared writers per stage). A gesture adds no stage and no overlap.
* **The hybrid pipeline** (AnimationTree for clips and speed blends, modifiers and IK after it, presenter for time and intent). See the pipeline decision in `docs/animation.md`.

## Actual duplicated rules

1. **"Play a clip, hold N seconds, then restore what the body was doing"** is hand-written in each place that needs it: `react_hit`, landing, pickup clip (tactical adapter, three call sites), `react_hit` and `inspect` (exploration host). The *refusal* rules around it (defeated, rescue lift active, traversal) are re-decided inline per call site, with different outcomes for the same situation (a hit during a rescue is SKIPPED, an inspect while interacting is CANCELLED).
2. **"What state does the body return to?"** has two implementations: `ExplorationCharacterHost._select_state` and `TacticalCharacterAdapter.present_idle` / `_return_from_hold`. They are not identical (the tactical one also consults cover geometry and the aim hold), but both are "persistent intent to clip", and the hold's `due` callback is where each plugs in. That is the right seam; what was missing is a *named* one-shot entry that takes it.
3. **The workbench plays one-shot clips by calling the controller directly** (keys 4 to 6), bypassing the presenter, so a bench hit has no handle, no rank and no completion.

## Undocumented interactions (now documented in `docs/animation.md`)

* `begin_hold` superseded any running hold unconditionally. That was the only rule, and it was implicit: a pickup clip's hold, a landing hold, a hit and an inspection all ended each other regardless of importance.
* `is_interacting()` on the exploration host meant "my inspection runs"; any other one-shot would have been invisible to it.
* An authored clip with no tracks for a bone leaves that bone at rest (the `RESET` track covers every bone any library clip touches). A new clip therefore must not be assumed additive.
* While a weapon is carried in the hand and not aimed, no arm stage holds the arm: the arms follow the clip and the weapon rides the hand. A clip that raises the arm raises the rifle.

## Genuine ownership conflicts

None between the owners that exist: no bone has two unordered writers, no action is advanced by two clocks. The conflicts found were *missing declarations*, not fights: hold priority (implicit) and the armed-arm rule above.

## Small reusable improvements made (Task 10)

1. `PresentationTypes.HOLD_*` ranks and `begin_hold(..., rank)`: a lower request is refused SKIPPED; equal or higher supersedes. The default rank supersedes everything, so every existing caller is unchanged.
2. `CharacterPresenter.begin_gesture(clip, restore, seconds)`: the one entry for a one-shot clip, with the one set of refusal rules.
3. `CharacterAnimationController.GESTURES`, the controller's `gesture_clip(...)` (armed twin) and `CharacterFallbackAnimationBuilder.make_gesture` recipes authored as directions in the body's frame.
4. `ExplorationCharacterHost.gesture(...)` and the workbench's `F` key.

Not done on purpose: no tactical gameplay action, AP cost or combat rule; no tactical adapter wiring (the presenter rule is shared, so wiring is one call when a tactical use exists); no replacement of the animation graph or modifier stack.
