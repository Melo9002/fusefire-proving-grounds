# Humanoid Character Replacement Roadmap

This roadmap replaces the prototype Beans with the 1.60 m android test dummy and the licensed AUG while preserving FuseFire's existing tactical rules, deterministic replay, AI, and debug tools. The Bean remains available as a debug model and future easter egg.

## Core technical decisions

- The current `TacticalUnit` remains the gameplay authority for tile occupancy, AP, health, visibility, shot samples, and objectives.
- The humanoid is a presentation child driven by gameplay state. Its detailed mesh never becomes tactical collision.
- Movement remains code-driven rather than animation root motion. This preserves exact grid destinations, AI simulation, action logs, and replay determinism.
- Animation may anticipate or follow an action, but it never decides whether that action succeeds.
- The rifle is attached to a named hand/socket point so later weapons can replace it without changing the character rig or animations.
- Animation events may request muzzle flashes, sounds, footsteps, and shell ejection. Damage and ammunition changes remain gameplay events.

## Production phases

| Phase | Name | Deliverable | Completion test |
| --- | --- | --- | --- |
| **26A** | Asset lock and scale | Preserve source files; use the 50k dummy and optimized 0.79 m AUG; record licenses and orientation | Dummy stands exactly 1.60 m beside a 1 m tile and the rifle appears at believable scale |
| **26B** | Topology and deformation cleanup | Repair or rebuild shoulders, elbows, hips, knees, neck, hands, and torso; retain rigid armor shells where useful | Limbs can bend through test poses without collapsing, tearing, or severe armor clipping |
| **26C** | Skeleton and skinning | One humanoid armature, stable bone names, hand sockets, weapon socket, muzzle marker, optional carry socket | Neutral, crouch, aim, kneel, and one-leg poses deform correctly; AUG follows both hands |
| **26D** | Basic locomotion | Rifle idle, run, backward movement, strafing, start, stop, and turn presentation | Unit moves one or two tiles in every direction without foot sliding becoming distracting |
| **26E** | Combat presentation | Aim, fire, recoil, return to ready, hit reaction, defend/brace, defeat | Attack timing matches the existing shot event and replay reaches the same final fingerprint |
| **26F** | Traversal and cover | Vault over low obstacle; step/climb as needed; low-cover and high-cover poses; left/right exposure | Traversal links and every cover direction play the correct pose without changing legality |
| **26G** | Rescue presentation | Pick up, carry idle, carry locomotion, extraction handoff, and release/failure recovery | Rescue carrier keeps the protected actor visually attached through movement and replay |
| **26H** | Animation state machine | Godot `AnimationTree`, locomotion blends, action states, transition rules, interruption handling | No snapping during ordinary transitions; damage/defeat can safely interrupt other states |
| **26I** | Unit visual adapter | Wrapper scene connecting `TacticalUnit` signals to the humanoid, team materials, selection outline, world-bar anchor | Player, ally, enemy, VIP, and rescue target all use the same gameplay contract |
| **26J** | Replay and battle validation | Validate authored/generated maps, elevation, AI-vs-AI, every objective, replay, and camera modes | Recorded and replayed outcomes match; no unit drifts from its authoritative tile |
| **26K** | Bean retirement | Make humanoid the default and keep Bean as a selectable debug/easter-egg visual | Match setup launches humanoids by default and a debug option can still restore Beans |

## Prototype 1 animation set

### Locomotion

- `idle_rifle`
- `move_start`
- `run_forward`
- `run_backward`
- `strafe_left`
- `strafe_right`
- `move_stop`
- `turn_left` and `turn_right`, or procedural facing blended over locomotion

A two-dimensional locomotion blend can combine forward/back and left/right movement. The controller moves the unit between tiles; the animation speed is adjusted to match the known travel duration.

### Combat

- `aim_enter`
- `aim_idle`
- `fire_single`
- `aim_exit`
- `hit_front`, with direction variants added only if testing justifies them
- `defend_enter`, `defend_idle`, `defend_exit`
- `defeat`

Reloading can wait until ammunition exists as a real rule. The AUG should still use a named magazine and muzzle attachment convention so reload and effects can be added later.

### Directional cover

- low-cover enter, idle, exit;
- low-cover expose left and expose right;
- high-cover idle;
- high-cover lean/fire left and lean/fire right;
- cover-to-cover movement can initially reuse ordinary locomotion with a shortened stance.

Cover direction comes from map metadata and the chosen target direction. A unit beside cover should face and pose relative to the blocking edge, not relative to the camera.

### Traversal

- vault approach;
- vault plant/contact;
- vault airborne passage;
- vault landing/recovery;
- optional climb-up and jump-down clips if existing traversal links require them.

The vault is treated as one logged movement action. Code follows a deterministic path curve while the animation supplies body motion. We do not simulate physical jumping for tactical movement.

### Rescue

- rescue/pickup interaction;
- carry idle;
- carry locomotion;
- extraction/release.

The protected actor can initially be hidden or represented by a simple attached proxy during carry if a full two-character animation is too expensive for Prototype 1.

## Transition design

Use a small state machine rather than direct calls scattered through gameplay code:

```text
LOCOMOTION <-> AIM -> FIRE -> AIM
LOCOMOTION <-> COVER <-> COVER_EXPOSE -> FIRE
LOCOMOTION -> VAULT -> LOCOMOTION
LOCOMOTION <-> CARRY_LOCOMOTION
ANY STATE -> HIT -> previous safe state
ANY STATE -> DEFEAT
```

Transitions have short crossfades. One-shot actions such as fire, hit, pickup, and vault report presentation markers, but gameplay waits only when explicitly designed to do so. Replay can increase playback speed without changing action results.

## Rig and attachment contract

Recommended minimum bones and markers:

- root and pelvis;
- spine chain, chest, neck, head;
- clavicles, upper arms, forearms, hands;
- thighs, shins, feet, toes;
- `weapon_socket_r` on the right hand;
- left-hand IK target for the foregrip;
- `muzzle_socket` on the rifle;
- optional `carry_socket` near the upper torso/back.

The right hand owns the AUG. Left-hand IK keeps the support hand on the foregrip despite small pose changes. Aim offset can rotate the upper body and arms after the base movement or cover animation.

## Recommended working order

Do not animate the current raw generated topology first. Complete one deformation test rig after cleanup, then make a tiny vertical slice:

1. Idle with AUG.
2. Run one tile and stop.
3. Aim and fire once.
4. Enter low cover and expose to one side.
5. Vault one obstacle.
6. Record and replay those actions.

Once that slice is stable, expand to the full animation list. This prevents producing many clips against a rig or topology that later needs replacement.

## Acceptance checklist

- Character height is 1.60 m and feet sit on the tile surface.
- Selection, hit chances, line of sight, and pathfinding behave exactly as before.
- Hands remain attached to the AUG during locomotion, aiming, firing, cover, and vaulting.
- Armor does not visibly tear at major joints.
- Movement ends exactly at the authoritative destination.
- Cover poses match all four grid directions and both exposure sides.
- Rescue carry and extraction remain functional.
- AI and manually controlled factions share the same presentation system.
- Replays reach the same state fingerprints and remain visually intelligible at increased speed.
- The Bean remains available through a debug or cosmetic visual selection.

## Current asset status

- Dummy rigged runtime: 50,000 triangles, 1.60 m, 26 bones, all 53,520 vertices weighted, hand IK controls and weapon/carry sockets present. Stress-pose deformation validation passed.
- Dummy source: 500,000 triangles and no armature.
- AUG socketed runtime: 4,562 triangles, 0.79 m long, one mesh, one material, UVs retained, with stable origin and muzzle markers.
- AUG source: 6,194 triangles across 17 mesh objects. Eight hidden cartridge/bullet objects were removed from the runtime copy.
- AUG license: CC BY 4.0. Preserve the included attribution file in distributions and release credits.
