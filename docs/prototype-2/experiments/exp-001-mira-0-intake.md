# EXP-001 — MIRA-0 asset intake and clean round-trip

**Vault ideas:** `MIRA-01`, `MIRA-02`, `MIRA-03`, `MIRA-05`  
**Owner:** Pedro + Codex  
**Branch:** `planning/prototype-2-idea-vault` during intake  
**Started:** 2026-10-03  
**Status:** active — read-only inventory  
**Baseline:** FuseFire `v1.0.0` (`43c95675d2abb5c61fa964c55aed27b51a292a9f`)

## Problem and question

**Problem:** Prototype 1's humanoid is an editable presentation foundation, but
FuseFire needs its first real MIRA and a repeatable human-friendly art workflow.

**Question:** Can MIRA-0 travel from its canonical editable source to Godot, use
one revised locomotion clip, and return for another revision without requiring
changes to unrelated gameplay code?

**Why now:** MIRA-0 and MIRA-00 already exist as partly prepared models, and the
next prototype's identity and animation work both depend on understanding their
actual structure.

## Located exports

The following source-workspace files were inspected read-only. They have not
been copied into the game repository.

| Body | Intended height | Current export | Size | Generator |
|---|---:|---|---:|---|
| MIRA-0 | approximately 1.60 m | `asset making/test dummy/references/big MIRA/Mira-0.glb` | 3,721,120 bytes | Tripo |
| MIRA-00 | approximately 1.20 m | `asset making/test dummy/references/small Mira/MIRA-00.glb` | 4,283,412 bytes | Tripo |

## Embedded structure

| Property | MIRA-0 | MIRA-00 | Implication |
|---|---:|---:|---|
| Scenes / armatures / skins | 1 / 1 / 1 | 1 / 1 / 1 | Both are simple single-character exports |
| Meshes | 1 | 1 | Easy initial import, though future material/part modularity is not represented |
| Vertices | 11,352 | 11,111 | Similar prototype complexity |
| Materials | 1 | 1 | Current exports do not yet express final surface or emissive regions |
| Skin joints | 65 | 65 | Both use the same Mixamo-style humanoid naming set |
| Animations | 22 | 22 | Enough baked material for locomotion and workflow tests |
| Exported mesh Y bounds | 0.0000–0.9995 | 0.0000–0.9995 | Intended 1.60 m / 1.20 m heights are not encoded directly in these GLBs |

Both skeletons include hips; three spine bones; neck and head; shoulders, arms,
forearms and hands; full finger chains; upper/lower legs; feet and toes. Bone
names use the `mixamorig:` prefix. This shared structure is promising for a
common skeleton contract, but identical bone names alone do not prove that the
very different body proportions can share every animation without correction.

## Available clips

### Shared useful starting clips

| Clip | Duration | Initial use |
|---|---:|---|
| `idle.001` | 15.38 s | Inspect breathing, feet, root stability, and loop seam |
| `standing_relax.001` | 17.62 s | Relaxed weapon-neutral pose reference |
| `walk.001` | 2.38 s | First round-trip candidate |
| `run.001` | 1.29 s | Speed/foot-slide comparison after walk |
| `turn.001` | 3.88 s | Facing and root-motion policy check |
| `run_upstairs.001` | 0.83 s | Later vertical traversal research |
| `shoot.001` | 9.08 s | Later weapon-contact and shoulder-stock reference |
| `climb.001`, `jump.001`, `fall.001` | varied | Later traversal library candidates |

MIRA-0 also contains `fire`, `hit_to_body_02`, `dive`, `agree`, and `box_03`.
MIRA-00 instead contains expressive clips including `heart_pose`, `laugh_02`,
`make_a_call_01`, `warm_up`, and `pitch_baseball`. These differences are content,
not yet evidence for different runtime animation architectures.

## Known unknowns

- No `.blend` file was found under the inspected `test dummy` folder, so the
  canonical editable source and current Blender cleanup state are still unknown.
- The GLB bounds suggest normalized exports. We must decide where authoritative
  physical height lives and avoid accumulating compensating scale in several nodes.
- Root animation, clip loop flags, frame rates, transforms, and foot sliding must
  be observed in Blender/Godot; names and durations cannot answer those questions.
- Skin quality around shoulders, hips, knees, wrists, and fingers needs posed review.
- The current single material does not yet prove team accents, emissive masks, or
  replaceable authored materials.
- The exports contain baked transforms for all 65 targets in every clip. We need
  one real import before deciding what should be retained, filtered, or retargeted.

## Boundaries

**Smallest honest proof:** Import MIRA-0 into an isolated character test scene,
validate its size and orientation, play `idle`, replace or revise `walk`, then
repeat the export once.

**Non-goals:** final textures, finished weapon handling, the complete animation
library, MIRA-00 production support, modular damage, and gameplay balance.

**Affected invariants:** presentation must not own movement legality; gameplay
position remains authoritative; animation names used by existing adapters must
remain stable or pass through an explicit mapping; replay must not depend on
animation timing.

**Removal path:** keep new imports, profiles, and test scenes inside an isolated
experiment area until adoption. Removing that area must restore the P1 baseline.

## Tasks

- [x] Locate and inspect both current GLB exports without modifying them.
- [x] Record mesh, skin, material, bone, animation, and scale facts.
- [ ] Locate or create the canonical editable MIRA-0 Blender source.
- [ ] Open it in Blender and inspect armature orientation, object transforms,
  actions, NLA tracks, weights, scale, and export settings.
- [ ] Decide where the authoritative 1.60 m MIRA-0 height is applied.
- [ ] Compare the 65 named bones with the P1 humanoid presentation expectations.
- [ ] Create an isolated Godot import/test scene.
- [ ] Validate `idle.001` and `walk.001`: orientation, loop, feet, root, speed,
  deformation, and transition.
- [ ] Revise or replace the walk clip and perform one complete re-export.
- [ ] Record manual steps that deserve an import preset or helper.
- [ ] Run the relevant [minimum regression checks](README.md#minimum-regression-check).
- [ ] Decide: adopt, revise, archive, or discard.

## Decision

**Outcome:** undecided  
**Current evidence:** continue. The shared skeleton and baked locomotion clips
make a contained round-trip practical; physical scale and editable-source
ownership must be resolved first.  
**Next action:** inspect the canonical Blender source together.

The animation-source shortlist and retargeting workflow are recorded in the
[Animation source survey](../animation-source-survey.md).

