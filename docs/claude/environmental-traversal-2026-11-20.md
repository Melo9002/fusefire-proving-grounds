# Environmental traversal animation: ladder (gameplay), vault / step-over / mantle (prototype)

## 1. Capability audit (what the tactical layer really allows)

| Action | Legal in gameplay today? | How it is represented | Presentation before this work |
| --- | --- | --- | --- |
| Ladder climb / descent | **Yes.** Authored `ladder_local_bottom/top` metadata becomes a bidirectional `TraversalLinkData`; the normal Move action paths over it at the usual one-step cost. | `SurfaceNavigation.traversal_route(from, to)` = `[from, (low.xz, high.y), to]`: a vertical rise at the lower cell, then a level step onto the deck (reversed going down). | the same static crouch clip (`climb` / `descend`, then `land`) for the whole route |
| Short ledge climb (1 m links in the test range) | **Yes** (same link type, rise 1 m). | same route shape | same clips |
| Vault over low cover | **Yes** (a low-cover cell is a vault transit). | 4-point route `[from, up, across, down]` at the obstacle's height | `vault` clip |
| Step-over | **No distinct action.** Low obstacles are the vault route or ordinary walking. | none | none |
| Mantle (tall obstacle) | **No.** Nothing makes a tall obstacle climbable; the 1 m ledge links are the nearest thing. | none | none |
| Jump | No. | none | none |
| Carrying a passenger over any of these | Not excluded by the rules, never exercised. | n/a | placeholder clips |

How movement works: a unit walks its waypoint list at one constant `movement_speed` (5 m/s). Cells, AP and the replay record are decided by the action layer; the walk itself is presentation, so the position along the route is a faithful animation clock. Replay playback scales `movement_speed`.
Interruptions: the presentation can be cut by a hit (reaction shots), a defeat, or a new move; the tactical state is already committed. Nothing in combat can represent a unit "on a ladder".

## 2. What was built

* **`TraversalProfile`** (resource, exported on `CharacterRig.traversal_profile`): every ladder, mount/dismount, speed and obstacle number.
* **`TraversalSolver`** (pure, `RefCounted`): `ladder_pose(profile, climbed, length, direction)` gives hand, foot and pelvis targets, trunk lean, head pitch, the mount/dismount weight and per-limb rung state; `vault_pose(...)` is the hand-supported vault prototype. No time, no state, no randomness.
* **`TraversalPoseModifier`** + a two-bone **`TraversalLegIK`** (new skeleton modifiers, between CoverCrouch and WeaponPose): pelvis and leg IK. The arms use the rescue system's *carry-contact* path: WeaponPose puts the wrists on the rung targets and `HandGrip` orients the fingers (`CharacterRig.apply_traversal_hand_targets`).
* **Gameplay hookup** (`UnitVisualAdapter.note_segment`, `TacticalUnit`): a vertical climb/descend segment of at least `ladder_min_rise` (1.8 m) is a ladder; the unit's tactical height above the ladder's bottom floor drives the pose every frame; the level step onto or off the deck is ordinary walking.
* **Workbench**: Environmental traversal section (climb/descend 4 m or 3 m, pause, hold at mount / mid / top-out, height slider, contact markers, readout) and a rendered capture script.

## 3. Ladder design

**The pose is a pure function of height** (`climbed` = the character's floor level above the ladder's bottom floor). Rung `k` is at `(first_rung + k * spacing)`, scaled by `rise / reference_rise` for ladders scaled by the parcel (the test range's 3 m ladders are the 4 m asset at 0.75). The route's rise is the only ladder fact the map exposes.

* **Contralateral four-point climb.** Left hand and right foot share one rung parity, right hand and left foot the other. A limb is planted on its rung while that rung is inside its reach window; it is picked up at the low end (reaching up two rungs) and travels over `swing_fraction` of the window with a small lift. Going down, limbs are picked up at the high end: descent is not the ascent reversed in place.
* **Windows come from the body**: this android's arm is only about 0.46 m and its legs about 0.84 m, so the hand window (0.82 m above the floor level, 0.66 wide) and the pelvis standoff (0.30 m behind the rung plane, trunk leaning 20 degrees) were tuned until every planted contact is reachable and the knees stay between about 40 and 110 degrees; measured by `traversal_rig_test`.
* **Mount (bottom)**: the weight rises over `mount_length` (0.5 m of climb): pelvis and leg IK blend in, the trunk leans in, the hands take the rungs, the rifle travels to the sling. The unit also turns to face the deck-side direction of the route over the same stretch (the `rotate_toward` at the usual turn rate, so no snap).
* **Top-out**: near the top the rungs run out; the hands blend to the deck edge (`deck_handhold_*`) and let go once the shoulders are more than an arm's length above the deck (`hand_release_*`); the legs stay on the last rungs until the dismount weight takes them off, then the level step is ordinary walking and the rifle returns to the hand.
* **Descent top**: the unit walks backward onto the ladder (it faces the ladder, not the walking direction) and the same weights ramp in as the height drops.

## 4. Weapon handling and ownership

The rifle is **slung** (the rig's existing `stow_weapon()` chest anchor, reused from the rescue carry; nothing is drawn or added) while ladder hands hold: `_stow_blend` follows the mount weight, so it travels rather than jumps. Ladder contacts take priority over the rifle grips for as long as they hold: WeaponPose places the weapon targets as usual and then overrides the two hand targets by the hand weight; the sling means no hand holds both.

| Owner while a ladder is climbed | |
| --- | --- |
| tactical layer | the route, speed, cells, AP, occupancy |
| `UnitVisualAdapter` | the ladder state, facing, the progress (height) it feeds the rig |
| `TraversalPoseModifier` / `TraversalLegIK` | pelvis position, legs |
| `CharacterRig` | trunk lean request (through the crouch modifier's measured axis), sling blend, hand contacts |
| `WeaponPoseModifier` / `WeaponArmIK` / `HandGrip` | arms and finger orientation, on the rung targets |
| animation clip | `rifle_idle` underneath, nothing of its own |

Modifier order is now Locomotion, CoverCrouch, Traversal, TraversalLegIK, WeaponPose, WeaponArmIK, HandGrip (five existing tests assert it and were updated; the traversal layers do nothing when no traversal is active).

## 5. Timing, replay, interruptions

* **Position-driven**: the pose is evaluated from the unit's tactical height, so it is identical at any frame rate, replay speed or paused/seeked position (the replay player already scales `movement_speed`).
* **Presentation speed (a decision to confirm).** At the route speed a 4 m ladder takes 0.8 s, 17 rungs a second. With `slow_ladder_enabled` (default on) a ladder segment is presented at `climb_speed` 0.85 m/s / `descend_speed` 0.75 m/s (scaled by `movement_speed / 5` so replay speeds still apply). Cells, AP, positions and the replay record are untouched; a 3 m ladder move now takes about 3.8 s to show. Turn the flag off to restore the old duration.
* **Interruption**: a new move, the end of movement, or a defeat clear the ladder state (`end_traversal`): leg IK off, lean and hand grip cleared, rifle back in the hand. A reaction-shot hit on a climbing unit shows no hit clip (the climb continues; a hit-on-ladder reaction is not designed). Mission end or replay seek rebuild the unit's presentation; nothing is held across that.
* **Loaded carriers**: unsupported. The adapter keeps the old placeholder clips for a carrier on a ladder and does not apply ladder contacts (the passenger's contacts and the rungs would compete for the hands).

## 6. Vault, step-over, mantle: not integrated

`TraversalSolver.vault_pose` computes deterministic hand contacts on the obstacle top, torso lean and a tucked leg path for the three-segment vault route, with tests, but **it is not wired to the rig or gameplay**: the legal vault route is rectilinear (up 1.1 m, across, down) at constant speed, and a believable vault needs the leg/IK integration and a presentation speed decision like the ladder's. Step-over and mantle have no tactical action and no implementation beyond the parameters in `TraversalProfile` (`step_over_max_height`, `vault_max_height`, `mantle_pull_height`). Do not read them as working features.

## 7. Environment and gameplay prerequisites (not done, need owner decisions)

* Rung positions, ladder plane and width are not exposed by `MapData`; they are inferred from the asset convention (4 m asset, scaled by rise). The authored ladder sits 5 cm behind the cell centre, so the body hangs 0.30 m back inside the cell.
* A ledge climb (1 m) and a ladder share one link type; only the rise (>= 1.8 m) separates them here.
* Hit reaction on a ladder, a loaded carrier on a ladder, and ladder occupancy are not modelled by the tactical rules.
* Vault/mantle timing, a step-over action and mantle eligibility are gameplay decisions.

## 8. Tests

`traversal_solver_test` (19: determinism, rung contacts, alternation, continuity, weights, descent, vault), `traversal_rig_test` (14: reach, joint limits, sling, modifier order, interruption cleanup), `traversal_ladder_gameplay_test` (15: the real Move action up and down the test range's 3 m ladder, height-driven pose, cost, cleanup, defeat mid-ladder). All three run in the movement suite (the runner matches "traversal"). Capture: `tests/traversal_ladder_capture.gd` (explicit-only), image `docs/claude/images/traversal-ladder-climb.png`.

## 9. Known limitations

No start/stop foot placement on the deck, no foot orientation on rungs, no body sway beyond a small shift, head pitch is computed but not applied to the neck, the hand grip is an approximation (fingers up, palm toward the ladder), the top-out hand placement is a blend rather than a pushing motion, no hit-on-ladder reaction, no non-uniform rung layouts.
