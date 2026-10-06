# OX-02 — XCOM animation inventory

**Date:** 2026-10-06

**Status:** inventory complete; visual/editor inspection remains

**Scope:** read-only study of the installed base XCOM 2 SDK

**FuseFire changes:** none

This pass maps animation packages, naming, human rig responsibilities, weapon
contacts, and animation events. It does not import XCOM assets or propose that
FuseFire adopt XCOM's grid, floor, cover, or traversal rules.

## Protected FuseFire decision

FuseFire's seamless elevation is a strength. Units can follow continuous paths
up stairs and across connected heights rather than teleporting between abstract
floors. OX-02 may borrow presentation vocabulary such as climb, vault, ladder,
drop, and landing. It must not change pathfinding, elevation, stair continuity,
or traversal legality. Any future proposal to change those rules requires a
separate discussion and explicit approval before implementation.

## Evidence and limits

Evidence came from package name tables and original UnrealScript under the local
SDK. This reliably identifies package responsibilities, named animation
families, runtime selection, socket contracts, and notify types. It does not
prove visual quality, exact bone transforms, retargeting quality, root motion,
loop seams, or how well any clip fits MIRA-0. Those require the XCOM editor and a
private visual inspection.

No package, script, mesh, animation, texture, or extracted derivative was copied
into this repository. Later experiments may use copied animations as private,
ignored local placeholders under the policy in [README.md](README.md). They must
never be committed, pushed, packaged, distributed, or released, and each one
must have a tracked replacement task and a release-safe fallback.

## Core packages

| Package | Approximate size | Observed responsibility | FuseFire relevance |
|---|---:|---|---|
| `Soldier_ANIM.upk` | 234.55 MiB | Common soldier, locomotion, weapon, cover, firing, damage, death, carry, and traversal AnimSets | Primary catalogue of action vocabulary and clip-family naming |
| `Soldier_ANIMTREE.upk` | 5.91 MiB | `AT_Soldier` animation trees, aim grids, movement/cover blending, IK-related nodes, and variation sets | Reference for context selection; too elaborate to copy directly |
| `Human_ANIM.upk` | 0.17 MiB | Shared human rig data, male/female proportion sets, physics asset references, and common sockets | Evidence that proportions can be layered around a shared contract |
| `HumanShared.upk` | 165.60 MiB | Modular human body content such as heads, torsos, arms, and legs | Useful customization reference, not needed for MIRA-0's first animation proof |

War of the Chosen depends on the base SDK content and did not contain duplicate
packages with these names in the inspected content tree. WotC-specific additions
can receive a separate inventory when a planned FuseFire feature needs them.

## Naming grammar

The package exposed 417 unique animation-like names in the principal semantic
families. Counts are inventory hints rather than exact production clip counts;
package name tables can contain references, variants, and old entries.

| Prefix | Count | Meaning inferred from source usage | Examples |
|---|---:|---|---|
| `MV_` | 65 | Movement and traversal | `MV_RunFwdA`, `MV_RunTurn90LeftA`, `MV_ClimbLowObject_UpA` |
| `NO_` | 106 | No-cover pose and weapon aim variants | `NO_IdleGunUpA`, `NO_RifleCC`, `NO_Flinch_Xcom` |
| `LL_` | 28 | Low cover, left-side context | `LL_IdleA`, `LL_Run2CoverA`, `LL_FireStartA` |
| `LR_` | 6 | Low cover, right-side context | `LR_Run2CoverA`, `LR_StepOutA` references |
| `HL_` | 122 | High cover, left-side context and many shared full-body actions | `HL_StepOutA`, `HL_ReloadA`, `HL_DeathA` |
| `HR_` | 10 | High cover, right-side context | `HR_StepOutA`, `HR_FlinchA` |
| `FF_` | 72 | Full-body firing and ability performances | `FF_FireA`, `FF_FireSuppressA`, `FF_GrenadeA` |
| `ADD_` | 8 | Additive layers or offsets | `ADD_RaiseWeapon`, `ADD_SwordSocketOffset` |

Common suffix patterns add further context:

- `Start`, `Loop`, and `Stop` form interruptible multi-part actions.
- `Left`, `Right`, `Fwd`, `Back`, and turn angles encode direction.
- `CC/CD/CU`, `LC/LD/LU`, and `RC/RD/RU` form a 3×3 aim grid:
  horizontal center/left/right plus vertical center/down/up.
- A trailing `A`, `B`, or `C` identifies variants.
- Some names include `_F` or live in `_F` AnimSets for female variants.
- Weapon AnimSets include assault rifle, cannon, pistol, shotgun, sniper rifle,
  sword, grenade launcher, heavy weapon, medkit, and psi amp families.

### Lesson for FuseFire

Keep public animation requests semantic and short. Body and weapon profiles may
map `move`, `fire`, or `hit` to contextual variants, but gameplay code should not
construct names such as `high_cover_left_fire_up`. A human editor should see the
available mappings in one resource.

## Useful clip families

### Locomotion

- forward run and walk;
- directional run starts;
- standing and crouched run stops;
- 45°, 90°, and 180° turns;
- run-turn transitions;
- flinch while moving;
- move-to-cover transitions.

The start/loop/stop split is more useful than XCOM's floor model. FuseFire could
use it to reduce foot sliding and make direction changes readable while the grid
and path remain authoritative.

### Firing and weapon handling

- raise/lower weapon additive layers;
- enter and leave firing pose;
- 3×3 aim-direction poses for rifles, pistols, cannon/heavy, and grapple;
- single fire, multishot, suppression, grenade, underhand, heavy, melee, and
  equipment-specific full-body performances;
- reload and gun-up/gun-down idles.

This supports a layered model: locomotion/base pose, weapon stance, aim offset,
and a short action performance. FuseFire should prove this with one rifle before
generalizing it.

### Cover

- low/high and left/right idle contexts;
- run-to-cover, step-out, step-in, and peek start/loop/stop;
- targeting-peek loops;
- cover-specific fire start/stop, flinch, and turns.

FuseFire does not need the full matrix immediately. Its current `cover_low`,
`cover_high`, `shoot_left`, and `shoot_right` requests already form a smaller,
appropriate semantic foundation.

### Damage and defeat

- directional hurt and flinch reactions;
- firing deaths, melee deaths, and several general death variants;
- get-up, stunned, panic, falling, and ragdoll handoff support.

The useful principle is choosing a readable reaction from context while keeping
HP and defeat state authoritative outside animation.

### Carry and extraction

- carry pickup variants for carrier/carried body combinations;
- carry loop and put-down/stop clips;
- evacuation start;
- additive carry-body layers.

This is directly relevant to FuseFire rescue missions, but body-pair alignment
is a later experiment. OX-02 changes neither rescue rules nor carrier AI.

### Traversal

- ladder and drainpipe up/down start-loop-stop;
- climb onto low object;
- climb over one- and two-tile obstacles;
- low/high drop start and stop;
- fall start/stop/death;
- dive/jump to cover and window break-through.

These are presentation categories only. FuseFire should attach optional tags to
its own continuous path segments, not reshape its traversal graph around XCOM.

## Human skeleton and proportion findings

The shared human package exposes a conventional hierarchy with stable core names
including `Root`, `Pelvis`, `Spine1`, `Neck`, and `Head`, plus male and female
proportion AnimSets. Exact full bone hierarchy and bind transforms still need
editor inspection.

The broader lesson is more valuable than copying the skeleton: establish one
canonical FuseFire humanoid contract, then use explicit retarget/proportion
profiles for MIRA-0, MIRA-00, humans, and other compatible bodies. Different
body proportions may need corrected grips, aim offsets, and stock placement even
when they share semantic animation requests.

## Weapon and IK contract

Observed runtime responsibilities:

1. A weapon defines a `DefaultSocket` on the character and an optional separate
   `SheathSocket`.
2. The character attaches the weapon to that socket.
3. The weapon exposes `left_hand`; the character's left-hand IK follows it.
4. The weapon exposes `gun_fire`; aiming, projectile origin, and firing effects
   use it by default.
5. Animation notifies can temporarily attach an item from one socket to another
   and enable or disable IK during a performance.

This strongly supports a FuseFire weapon scene contract with editable markers:

- `grip`: weapon placement in the dominant hand;
- `support_hand`: off-hand contact;
- `muzzle`: projectile/effect origin;
- `stock`: optional shoulder-contact reference;
- optional holster/sheath contact.

MIRA rig profiles should contain body-specific corrections. The weapon owns its
physical contacts; gameplay continues to own targeting and shot resolution.

## Animation events worth studying

| Notify | Observed purpose | Possible FuseFire equivalent |
|---|---|---|
| `AnimNotify_FireWeapon` | Trigger weapon firing from an authored frame | presentation event `fire` |
| `AnimNotify_FireWeaponVolley` | Multiple shots, interval, projectile variant, cosmetic-only flag | authored volley markers; simulation still resolves deterministically |
| `XComAnimNotify_Aim` | Enable aim profile toward a socket/bone with blend time | aim-layer enable marker |
| `AnimNotify_BlendIK` | Blend IK during a clip | hand/foot IK weight marker |
| `XComAnimNotify_ItemAttach` | Move an item between sockets | pickup, holster, or carry attachment marker |
| `RaiseWeapon` / `LowerWeapon` | Blend weapon stance at an authored moment | weapon-ready layer marker |
| `LookAt` | Blend gaze weight | head/eye tracking marker |
| `FixupBegin` / `FixupEnd` | Bound a positional correction region | optional presentation alignment window |
| `Ragdoll` | Hand off to physics with impulses | later defeat presentation marker |

For FuseFire, these events should synchronize visuals and audio. They must not
decide whether a shot hit, spend AP, move a unit, or advance the turn.

## Comparison with the current FuseFire foundation

FuseFire already has an encouraging semantic layer:

`rifle_idle`, `move`, `aim`, `shoot`, `hit`, `defeat`, `cover_low`,
`cover_high`, `shoot_left`, `shoot_right`, `vault`, `climb`, `descend`, `land`,
`pickup`, `carry_idle`, `carry_move`, and `boarding`.

This is a foundation rather than a complete animation list. Prototype 2 will
probably need additional starts/stops, directional turns, weapon-ready changes,
aim directions, reloads, contextual hit reactions, cover transitions, traversal
entrances/exits, body-pair carry alignment, and body-family variants. We should
add a semantic request when gameplay or presentation proves the need, then make
it visible in the animation profile and workbench.

The next proof does not need a replacement controller. It should make the
existing requests profile-driven, add one small event path, and test one rifle
grip on MIRA-0. XCOM's huge variant matrix is a catalogue of solved presentation
cases and potential placeholders, not FuseFire's required architecture or final
animation budget.

## Recommended follow-up experiments

1. **One-rifle contact proof:** give the AUG explicit grip, support-hand, muzzle,
   and stock markers; expose MIRA-0 correction offsets in one profile.
2. **One semantic animation profile:** map the current requests to clips without
   changing callers or tactical rules.
3. **One authored fire event:** synchronize muzzle flash/audio/camera timing while
   combat resolution remains immediate and deterministic.
4. **Private visual SDK review:** inspect representative idle, run, aim, fire,
   hit, cover, carry, and traversal clips in the editor. If useful, copy selected
   animations into ignored local research storage as temporary placeholders,
   record their replacements, and then author or license release-safe FuseFire
   animations.

OX-02 is complete when this inventory can guide those isolated proofs. It does
not require importing or shipping an XCOM animation.
