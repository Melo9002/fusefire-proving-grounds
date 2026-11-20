# Exploration playground (experimental sandbox)

A small, playable, clearly experimental sandbox for walking MIRA around outside tactical combat with an over-the-shoulder camera. It is a companion to the [Task 03 research report](animation-requirements-research-2026-11-20.md) and builds on the scripted probe in `research/animation_host_probe/`, which is unchanged and still passes its 12 checks. It is **not** a gameplay mode and not a commitment to any menu layout: no `TacticalUnit`, AP, grid, mission, objective or battle exists in it.

## How to open it

Launch FuseFire, open the **Settings** tab of Match Setup, and press **Exploration** (in the Authoring tools box, under the Parcel Editor button). The scene is `research/exploration_playground/exploration_playground.tscn`; it can also be opened directly in the editor and run with F6.

## Controls

| Input | Action |
| --- | --- |
| W A S D | Move, relative to where the camera looks (diagonals are normalised) |
| Mouse | Look (yaw and pitch, pitch limited to 60 degrees down and 25 degrees up) |
| Mouse wheel | Zoom the camera (1.4 to 6 m) |
| Right mouse button (hold) | Recenter the camera behind MIRA |
| E | Interact, when the yellow ring around the chair is entered ("Press E to interact") |
| Esc | Release the mouse and show a small menu: **Resume** or **Back to Match Setup** |
| Left click (while the mouse is free) | Capture the mouse again |

The mouse starts captured. The controls are also shown on screen, together with MIRA's current presentation state and speed.

## What is in it

* The production MIRA visual (`art/characters/mira_0/runtime/mira_0_unit_visual.tscn`), driven only through its public presentation calls: `present_move`, `present_idle`, `update_locomotion` and `face_world_position`. Nothing in the rig, adapter or modifiers was changed.
* A flat 40 m floor with one-metre checker squares (so movement and foot sliding are readable), a large and a small crate, a low wall, a pillar, and a chair-shaped placeholder (one box collider; seat, back and four legs as meshes). All primitive geometry with basic collision; no new art.
* A directional light with shadows and a plain sky colour.
* A follow camera: a `SpringArm3D` (sphere probe, so it cannot clip through props or the floor), a 0.45 m shoulder offset, smoothed follow (rate 14/s), smoothed zoom, pitch limits and recentering.
* One local interaction: inside 2.4 m of the chair a prompt appears; E turns MIRA toward the chair (`face_world_position`), flips the seat colour and shows a short message.

Development constants are at the top of `exploration_playground.gd`; walking speed is `MOVE_SPEED` (1.4 m/s, inside the walk gait, which ends at the locomotion profile's `walk_until` of 1.6 m/s) with `ACCELERATION` for starts and stops.

## Verification

**Executed (headless, `tests/exploration_playground_test.gd`, 34 checks, 0 failures, 12.6 s):** the Exploration button exists on Match Setup, and pressing it opens the playground; no `TacticalUnit` exists and MIRA's presentation has no tactical unit; idle at the start; W moves forward along the camera direction (2.14 m in 1.6 s, speed 1.40 m/s equal to `MOVE_SPEED`); the movement clip state plays and the gait follows the real speed; MIRA faces the movement direction; the camera keeps a sensible distance while moving and stays above the floor; diagonal movement is not faster; releasing the keys returns to `rifle_idle` at speed under 0.1; the crate blocks MIRA; mouse look turns the camera and pitch respects both limits; zoom clamps at both ends; right mouse recenters behind MIRA within 6 degrees; no prompt or response far from the chair; the prompt appears near it, E changes the seat colour and shows the message, and MIRA turns to the chair within 5 degrees; Esc shows the menu and frees the mouse, MIRA does not move while it is open, Resume closes it, **Back to Match Setup** returns to Match Setup (which still offers Exploration, Parcel Editor and Start); the temporary input actions are removed on exit. Also run: `match_setup_bulwark_test`, `match_setup_smoke`, `parcel_editor_test` (all pass: existing Match Setup behaviour preserved), the original research probe (12 of 12, exit 0), and the GDScript warning audit (0 warnings).

**Visually inspected:** one short windowed run (1280 by 720, NVIDIA GPU) captured five screenshots (idle, walking, diagonal, camera orbit and zoom, interaction) that were read by eye: the character stands correctly on the floor, the camera follows from over the shoulder, orbit and zoom work, and the chair, prompt and message appear. This was automated capture, not a person playing: **feel, animation quality and foot sliding were not judged**, and real mouse capture and key input from a physical keyboard were not exercised (a headless run has no real mouse mode to read back, so the test checks what the playground requested).

**Not verified:** actual interactive play by a person, performance on other machines, gamepad input (none), and window or resolution changes.

## Limitations encountered (existing presentation, deliberately not worked around)

* **No unarmed state.** MIRA always carries the rifle in the production idle and walk poses (the rig asserts a weapon exists); the sandbox does not pretend otherwise. A slung rifle (`stow_weapon`) exists but is a carry pose, not an unarmed one, and is not used here.
* **No sitting or interaction animation.** E demonstrates the non-tactical *request* (face the object, visible response) only; the toast says so.
* **No crouch outside cover.** Not offered (a direct crouch request is overwritten each frame by the adapter's cover sync).
* **The 1 m tactical-origin offset.** The production scene hangs one metre below a unit's body centre; the sandbox undoes it by placing the visual at the character body's floor origin, locally and transparently.
* **Facing is owned by the adapter.** `update_locomotion` turns the whole body toward the velocity at 360 degrees per second; there is no separate facing intent, so strafing and backpedalling are not distinct motions (MIRA turns to face where she walks).
* **Clip states are requested by the caller** (`present_move` on starting, `present_idle` on stopping), as the research probe found.
* The "white ring" under MIRA is the production unit visual's own marker; it was left as is.

## Design notes and files

Local to the playground and meant to be thrown away: the input actions (`playground_*`, registered at run time and erased on exit, so `project.godot` is untouched), the camera, the props, the interaction. Match Setup opens the scene by path (no preload), so it does not depend on the research folder; returning uses the same `change_scene_to_file("res://ui/match_setup.tscn")` convention as the Parcel Editor.

| File | Change |
| --- | --- |
| `research/exploration_playground/exploration_playground.gd` (+ `.gd.uid`) | new: the playground controller and builder |
| `research/exploration_playground/exploration_playground.tscn` | new: one-node scene with the script |
| `ui/match_setup.gd` | modified: an `ExplorationButton` and one path constant (the only change to existing production code) |
| `tests/exploration_playground_test.gd` (+ `.gd.uid`) | new: 34 headless checks |
| `tests/catalog.json` | modified: one line registering the test (`animation`, `ui`; integration; not FAST or SMOKE) |
| `docs/claude/exploration-playground-2026-11-20.md` | new (this document) |
| `docs/claude/README.md` | modified: index row |

## Recommendations for Tasks 04 to 08

1. **Task 04 (intent interface).** The playground's whole controller is the argument for it: it hand-rolls "request a clip state, feed velocity, request a facing" with three calls and a transition detector. A typed intent interface (continuous velocity and heading, facing, transient requests) would replace that glue and make the headless test an interface test.
2. **Equipment as data (Tasks 04 and 09).** The most visible gap when playing is the rifle in every pose; unarmed idle and walk are the first thing a non-tactical context needs.
3. **Task 08 (real non-tactical proof).** Promote what worked (continuous locomotion, turning, the camera, the request-and-response interaction) and replace the local pieces (inputs, props, the interaction) with the real context controller; keep the test's structure.
4. **Facing and strafing.** Decide whether a free-facing, strafe-capable locomotion presentation is wanted before building exploration gameplay on `update_locomotion`'s turn-to-velocity behaviour.
5. **Selector note.** `research/` has no area in `tests/catalog.json`, so changed-file selection reports it as unmapped and broadens; mapping it to `tooling` (or `animation`) would make selections more precise.
