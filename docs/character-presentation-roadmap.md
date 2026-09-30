# Character Presentation Roadmap

This roadmap replaces the Bean presentation in stages while preserving FuseFire's tactical rules, deterministic replay, AI, and debug tools. Prototype 1 begins with one fixed VRoid humanoid and the existing licensed AUG. The Bean remains available as a debug model and future easter egg.

The VRoid character is a proof asset, not the foundation of the final character creator. Final customization will use original or explicitly licensed meshes, textures, clothing, and modular parts. FuseFire must eventually support multiple body families rather than assuming every actor shares one humanoid skeleton.

## Core technical decisions

- `TacticalUnit` remains authoritative for tiles, AP, health, visibility, attacks, objectives, and replay state.
- A `UnitVisualAdapter` translates gameplay presentation requests such as move, aim, fire, cover, carry, hit, and defeat into model-specific animation states.
- Detailed character meshes remain presentation children and never become tactical collision.
- Gameplay code moves actors between exact tiles. Animation contains no authoritative root motion.
- Animation events may request sounds, footsteps, muzzle flashes, and shell effects. They never decide damage or action legality.
- Weapons use stable attachment markers. The right hand owns the weapon, the support hand aligns to a foregrip target, and effects use the weapon's muzzle marker.
- The optimized AUG remains the Prototype 1 rifle and keeps its CC BY 4.0 attribution.

## Revised production phases

| Phase | Name | Deliverable | Completion test |
| --- | --- | --- | --- |
| **26A — Complete** | VRoid proof asset | Import one self-created VRoid/VRM character and inspect its contents | Source model loads in Blender with its skin, humanoid skeleton, materials, and facial shapes intact |
| **26B — Complete** | Runtime normalization | Convert to a stable GLB, normalize scale/orientation, and record bone mappings | Godot validation passes at 1.60 m with 229 bones, 3 skinned meshes, and 57 facial morphs |
| **26C — Complete** | AUG attachment and hand IK | Attach the preserved AUG to the right hand, add a support-hand target, apply two-arm `TwoBoneIK3D`, and expose its muzzle marker | Automated tests confirm both hands reach their targets and the muzzle axis survives repeated IK toggles |
| **26D — Complete** | Vertical-slice animation | Rifle idle, movement loop, sighted aim, single shot, recoil, hit, defeat, and crossfades | Human review accepted the blocking demo; regressions cover knee direction, forward stride, hand reach, and sight alignment |
| **26E — Complete** | Unit visual adapter | Connect `TacticalUnit` presentation events to the temporary humanoid without changing combat rules | Player, friendly AI, enemy AI, and replay drive the same visual interface |
| **26F — Complete** | Locomotion and transitions | Directional step blending, gradual turns, short crossfades, and speed matching | Accepted as an editable animation foundation |
| **26G — Foundation accepted** | Directional cover and traversal | Low/high cover, left/right exposure, vault, climb, descent, and landing blocking poses | Distinct poses accepted for now; polish deferred |
| **26H — Visual review** | Rescue and extraction | Pickup, carry idle/movement, cosmetic passenger, boarding, and parked transport | Objective and rescue replay checks pass; visual acceptance pending |
| **26I — Handoff ready** | Animation handoff pass | Editable clip library/workbench, grouped offsets, and documented Blender/Godot workflow | Workbench and runtime use the same saved clips; first new Blender-authored replacement still needs visual review |
| **26J** | Battle and replay validation | Run authored/generated maps, elevations, objectives, AI-vs-AI, and replay | Outcomes and state fingerprints match; visuals never drift from authoritative tiles |
| **26K** | Prototype default verification | Verify humanoid default presentation and Bean debug option | Match setup launches the proof character and a debug option restores Beans |
| **27A** | Body-family contract | Define shared presentation requests and per-family capabilities | Standard, tall, short, and quadruped adapters can report which actions they support |
| **27B** | Humanoid variants | Test height and proportion variation with retargeted humanoid animation | Tall and short humanoids keep feet planted and hands aligned after correction passes |
| **27C** | Non-humanoid proof | Add one dog-like robot or other quadruped using a separate rig | The unit obeys the same tactical and replay systems through its own animation adapter |
| **27D** | Original customization foundation | Define original modular body, face, hair, clothing, armor, and color slots | No final customization feature depends on restricted VRoid Studio meshes or presets |

## First vertical slice

Build and validate this sequence before expanding the animation library:

1. Stand in rifle idle with the AUG attached.
2. Move one tile and stop at the authoritative destination.
3. Aim at a target and fire one shot.
4. Play one hit reaction and one defeat animation.
5. Record the sequence and replay it with the same final fingerprint.

This slice proves asset import, skeleton mapping, weapon alignment, animation playback, gameplay integration, and replay without requiring the complete cover and rescue library.

## Body families

| Family | Examples | Animation strategy |
| --- | --- | --- |
| Standard humanoid | Human-scale androids, soldiers, civilians, VIPs | Shared humanoid library with weapon and role layers |
| Tall/heavy humanoid | Heavy androids, armored frames | Retargeted base motion plus adjusted stride, cover, and weapon poses |
| Short humanoid | Compact androids and small characters | Retargeted motion with foot, hand, camera, and cover-height corrections |
| Quadruped | Dog-like robots | Separate skeleton and animation library behind the same visual adapter |
| Specialist machine | Drones, walkers, unusual robots | Dedicated presentation adapter implementing only relevant capabilities |

Missing capabilities must fail gracefully. A quadruped without a rescue-carry pose should use a designed alternative or be ineligible for that action rather than borrowing a broken humanoid animation.

## VRoid licensing boundary

- Fixed exported VRoid characters may be used as Prototype 1 and 2 presentation assets when every included item permits the intended use.
- Preserve the original `.vroid` file, exported `.vrm`, license notes, and a list of third-party items.
- Do not build FuseFire's distributable character creator from VRoid Studio-provided meshes, textures, or presets without a separate license from pixiv.
- Original textures and hair created from scratch remain useful references or assets according to their actual ownership and licenses.
- The final game should use original, commissioned, or explicitly character-creator-licensed modular assets.

## Animation and attachment contract

The first humanoid proof should provide mappings for root, hips, spine, chest, neck, head, arms, hands, legs, feet, and toes. FuseFire-facing markers should include:

- `weapon_socket_r` or an adapter mapping to the right hand;
- `support_hand_target` on the AUG foregrip;
- `muzzle_socket` on the AUG;
- optional `carry_socket` for rescue presentation;
- `world_bar_anchor` above the character's head.

The source rig may use different bone names. The adapter or import process owns the mapping; gameplay code does not.

## Prototype 1 acceptance checklist

- Character scale and feet align with the 1 m tactical grid.
- Selection, line of sight, hit chances, pathfinding, AP, and objectives behave exactly as before.
- AUG attachment and muzzle effects follow the animated character.
- Movement ends at the authoritative destination.
- Animation states work for player control, friendly AI, enemy AI, and AI-vs-AI.
- Cover, traversal, rescue, extraction, and defeat remain functional.
- Recorded and replayed outcomes match.
- The Bean remains available as a debug or cosmetic presentation.

## Preserved weapon asset

- Runtime AUG: `art/weapons/aug/models/aug_runtime_socketed.glb`
- Length: 0.79 m
- Runtime geometry: 4,562 triangles
- Stable markers: `WeaponOrigin` and `MuzzleSocket`
- License: CC BY 4.0; preserve `art/weapons/aug/AUG_ATTRIBUTION.md` in distribution credits

## Current status

- The generated android test dummy and its failed rigging experiments were removed from the repository; the user retains an external backup.
- The AUG and all of its source, runtime, socket, optimization, and attribution files remain in the project.
- `vroidTest.vrm` has been inspected in Blender and normalized into `models/vroid_test_runtime.glb` at exactly 1.60 m.
- Godot's automated runtime validation passes: humanoid skeleton, required bones, three skinned meshes, and 57 exported facial morphs.
- Clothing clipping is acceptable during the proof stage. Human review will concentrate on pose readability, hand placement, elbow direction, and weapon alignment.
- The AUG now exposes `WeaponOrigin`, `SupportHandTarget`, and `MuzzleSocket`; the right wrist owns the weapon and two-arm IK maintains the grip targets.
- The six-state vertical slice now runs through an `AnimationTree`: rifle idle, movement, aim, shoot with recoil and muzzle flash, hit, and defeat.
- The blocking-quality 26D animations were accepted as a foundation. Further visual refinement is documented in `docs/animation-editing-guide.md`.
- `TacticalUnit` now owns a model-independent `UnitVisualAdapter`. Player control, both AI factions, and replay drive the same move, shoot, hit, and defeat requests while the hidden capsule remains authoritative for collision.
- **26F/26G** are accepted as animation foundations. **26H** adds the cosmetic rescue passenger, carry/boarding clips, stowed weapons while carrying, and escort priorities. The transport occupies blocking full-cover tiles inside the map where safe placement is available, with an off-grid visual fallback. After the required VIPs board, remaining units can evacuate or the player can confirm departure and leave them behind; replay includes departure. Review the demo and a rescue/extraction mission before moving to **26I**.
