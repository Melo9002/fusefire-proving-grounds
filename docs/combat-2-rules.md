# Combat 2.0 — intended rules

Decision sheet, 2026-11-16. **Milestone 04 step 2 is defined; the step-4 geometry/LOS corrections and step-5 physical cover rules are implemented; steps 6–7 range/height, +35 Aim and fixed damage are implemented; step 8 defensive-action review and step 9 decision previews/chance colors are complete.** [Combat today](combat-current-rules.md) describes the running game. The numbers below are provisional starting values, chosen so we can build controlled examples and tune them by editing ordinary resources. They are not a claim of finished balance.

## What we take from XCOM

XCOM 2 presents low/high cover, directional flanking, shot odds and projected damage, and less accurate Overwatch fire. These are useful principles for explaining positioning before commitment. See the [official port manual, Cover and Actions](https://www.feralinteractive.com/en/manuals/xcom2/latest/steam/), consulted 2026-11-16.

The installed base-game and War of the Chosen SDKs also separate cover modifiers, weapon-specific range tables and height modifiers. Their configured low/high cover penalties are 20/40 points. The standard calculation includes angle adjustments and difficulty assistance; those are not necessary for FuseFire's starting model. Local source references are recorded below. This is a focused comparison, not a complete reconstruction of XCOM's native visibility or corner logic.

**Our choices:** keep directional protection and readable odds; use continuous height and a simple steepening range curve; retain FuseFire's AP/supply, Guard and physical Shield behavior. Do not add criticals, hidden accuracy assistance, automatic corner peeking or a new boundary-authoring workflow in this step.

## Geometry and legal shots

Legality comes before accuracy. A normal attack requires a living hostile on the playable map, a living attacker who is not carrying someone, weapon range, a clear body sample, sufficient AP/supply, and an eligible action window/stance. An invalid attack spends nothing and draws no random number. Camera visibility does not grant targeting permission.

Use the existing tactical geometry derived from assets and their transforms. Ordinary placement remains automatic. Mesh-derived boxes are approximations: an opening enclosed by one box is still blocked until its tactical representation actually has that opening. Do not compensate for bad geometry with an accuracy bonus.

Keep one firing origin and the existing five target samples: upper body, head, two shoulders and lower body. Anchor them to the actual supported surface height, including ramps and fractional elevation, rather than a rounded floor index. Use the same sample offsets for UI, AI, reactions and execution. Animation and camera fading never change this calculation. Units do not become additional environmental bullet blockers in this version.

| Setup | Expected result |
| --- | --- |
| All five rays hit a wall | Blocked; no attack, even with Aim or high ground. |
| The center ray hits a pillar but a shoulder sample is clear | Legal, with the appropriate partial-exposure penalty. A center-ray-only overlay must not disagree. |
| A real doorway clears a body sample | Legal through the opening; the surrounding wall still blocks its other rays. A painted door texture alone creates no opening. |
| Two obstacles block the same sample | Explain the first intersection along that ray, not the first cell found during iteration. Use stable coordinate ordering for exact ties. |
| Every sample is blocked by different objects | Select the blocked sample nearest the target body's center, with fixed sample order breaking ties; highlight that ray's first blocker. Clearing it may expose another blocker. |
| A target is beyond maximum range or outside the playable map | Illegal, regardless of displayed scenery, Aim or chance modifiers. |

**Corners:** preserve the existing small open-edge tolerance: a ray merely tangent to one obstacle's corner may pass; two touching solid diagonal cells must not create a zero-width shooting slit. A ray above both obstacles may pass. The existing 0.001 world-unit inset is the starting tolerance; it is numerical tolerance, not permission to shoot through a wall. No free relocation of the muzzle around a corner. Controlled fixtures must cover both travel directions, rotated parts and elevations before implementation is accepted.

## Cover, flanking and exposure

Cover is local protection from a particular attacker, not a blanket property of the target's tile. On current maps, consider actual nearby cover-bearing shapes around the target's resolved standing point, including its own cell and diagonal parts. The existing contact reach is 0.85 tile widths from that point; a distant obstacle is obstruction rather than local cover. Historical non-surface fixtures retain their cardinal-neighbor lookup. A neighboring label alone is insufficient: the ray from the firing origin to the existing lower-body sample (`0.5 × target standing_height` above its surface) must intersect that candidate's actual tactical shape before reaching the target. Apply the same corner tolerance as LOS. For compound objects, test the actual parts, not their combined empty envelope.

This lower-body check is a deliberately simple protection proxy; it does not require a crouching animation or measure exact visible mesh area. Keep the compiler's existing 1.2-tile full-cover threshold, but apply it to the precise part that actually protects the target, relative to the target's supported surface. A low part cannot inherit full cover from a taller part sharing its tile. Legacy non-precise cells retain their explicit classification. If multiple eligible surfaces protect the target, use the strongest, without adding them together. A distant intervening obstacle can obstruct a shot but does not become adjacent cover.

| Setup | Expected result |
| --- | --- |
| Low cover lies between shooter and the adjacent target and protects the lower-body sample | 20-point cover penalty, provided some body sample remains clear. |
| Full cover protects the same direction and at least one sample remains clear | 40-point cover penalty. Full cover is stronger than low cover, not immunity. |
| Shooter moves behind or beside that cover and the protection ray misses it | That surface gives no cover penalty: a flank. No extra flank accuracy or critical bonus. Other obstructions and Shield still apply. |
| Two cover faces meet at a diagonal | Test both physical shapes and use the strongest qualifying protection; no arbitrary X-axis tie preference or doubled defense. |
| An elevated shooter's protection ray passes above low cover | That surface gives no cover penalty. Re-evaluate exposure separately; elevation does not automatically remove all cover. |
| A tiny crate has a cover label, but its actual shape misses the protection ray | No local cover bonus from that crate. |

For legal shots retain the existing partial-obstruction table, based on **clear samples**, not a claimed percentage of visible character mesh:

| Clear samples | 5 | 4 | 3 | 2 | 1 | 0 |
| --- | --- | --- | --- | --- | --- | --- |
| Exposure penalty, points | 0 | 10 | 25 | 40 | 50 | Illegal |

Use `protection = max(cover penalty, exposure penalty)`. Do not charge twice for protection described by both cover and visibility. Example: full cover and two clear samples produce 40, not 80; low cover with one clear sample produces 50, not 70. This also deliberately avoids stacking distant obstruction with local cover into an excessive combined penalty.

## Accuracy, height and range

**Step-7 status:** the formula below, including **+35 Aim**, is implemented in the existing shared `systems/combat_cover_tuning.tres`. Max-range Aim is 65%, or 75% with two tiles of height advantage. Ordinary successful damage stays 25 regardless of accuracy; Shield keeps its independent reduction. Base accuracy, chance limits, Aim, Guard and hit damage now share the same editable resource. Chance colors shipped in step 9.

For a legal shot, all modifiers are **percentage points**:

```text
d = 3D distance between supported foot positions, in tactical tile widths
R = attacker's existing maximum weapon range, in the same units
safe range fraction = 0.60                    [editable; R must be positive]
t = clamp((d / R - safe range fraction) / (1 - safe range fraction), 0, 1)
range penalty = 70 × t^2                      [reject d > R before this calculation]
height bonus = clamp(5 × (shooter ground Y - target ground Y) / tile width, -20, +20)
raw chance = 100 - range penalty - protection + height bonus
             + action bonus + other explicit ability modifiers + Shield modifier
chance = floor(clamp(raw chance, 5, 100) + 0.5)
```

Retain fractional contributions until the final rounding, and use that same integer for preview and the actual roll. Reject invalid range/tuning rather than divide by zero. Height uses actual ground/support positions, not animation head height or named floor levels. Horizontal distance and vertical difference both contribute to weapon range; the height bonus is a separate advantage, not extra reach.

Owner clarification: the goal is to avoid routinely missing apparently dependable shots. Clear, level normal shots stay at **100% through the first 60% of weapon range**, then fall steeply toward its edge. Starting chances at 60/70/80/90/100% of range are 100/96/83/61/30%. This plateau followed by a quadratic falloff is a small, editable interpretation of the requested curve, not a literal exponential. The safe fraction controls where risk begins; strength 70 controls the endpoint; exponent 2 controls the bend. Validate `0 <= safe fraction < 1`, nonnegative strength and exponent greater than 1. There is no extra weapon system to author.

The plateau describes the **range contribution** for an exposed target. Cover, partial visibility, low ground, Guard and Shield can reduce accuracy even nearby. Aim and high ground can restore reliability against those penalties. High ground may have no displayed benefit when a clear shot is already capped at 100%; it still offsets penalties in difficult shots. A genuine 95% shot can still miss: we change where risk arises and communicate it honestly, rather than silently converting it into a guarantee.

| Starting value | Choice | Why |
| --- | --- | --- |
| Base accuracy | 100 | Clear short-to-medium shots are dependable; positioning and longer range introduce risk. |
| Half/full cover | 20 / 40 | A meaningful difference using familiar starting values. |
| Safe range fraction / strength / exponent | 0.60 / 70 / 2 | Guaranteed exposed shots across a broad range, followed by a steep drop. |
| Height per tile width / cap | 5 / ±20 | Ramps change accuracy gradually; extreme height cannot dominate every modifier. |
| Aim | +35 | A substantial reward for spending an AP preparing a shot. |
| Guard reaction | -15 instead of Aim | Keep the existing reaction tradeoff. |
| Shield accuracy / damage | -20 / ×0.35 within its facing arc | Keep the current capability's distinct protection. |
| Legal-shot chance limits | 5–100 inclusive | Poor legal shots retain a chance; reaching 100 is an actual guarantee. |
| Damage on ordinary hit / miss | 25 / 0 | Keep damage stable while changing accuracy. No new damage falloff. |

Apply bonuses before the final clamp. Aim can recover a difficult shot that would otherwise reach the 5% floor. A blocked shot remains illegal, not a 5% attempt. No hidden miss-streak, faction or difficulty adjustment; an explicit ability may change its documented modifiers, but cannot bypass legality unless that ability deliberately defines a different attack type.

### Numerical acceptance examples

Assume no unlisted modifiers and a legal shot. Heights below are differences in tile widths; distance is the full 3D `d/R`. The setups must keep that distance constant when comparing height alone.

| Setup | Calculation before rounding/clamp | Expected chance |
| --- | --- | --- |
| Clear, level, 20% range | 100 - 0 | 100%, guaranteed hit |
| Clear, level, 50% range | 100 - 0 | 100%, guaranteed hit |
| Clear, level, 80% range | 100 - 17.5 | 83% |
| Clear, level, maximum range | 100 - 70 | 30% |
| Same maximum-range shot with Aim | 100 - 70 + 35 | 65% |
| Same shot with Aim, shooter two tiles higher | 100 - 70 + 35 + 10 | 75% |
| Clear, 80% range, shooter two tiles higher / lower | 100 - 17.5 ± 10 | 93% / 73% |
| Low cover, four clear samples, 50% range | 100 - 0 - max(20, 10) | 80% |
| Full cover, two clear samples, 50% range | 100 - 0 - max(40, 40) | 60% |
| Flank removes that cover; all samples now clear, 50% range | 100 - 0 | 100%, guaranteed hit |
| Low cover, one clear sample, 50% range | 100 - 0 - max(20, 50) | 50% |
| Full cover, maximum range | 100 - 70 - 40 | 5% floor |
| Same full-cover shot with Aim | 100 - 70 - 40 + 35 | 25% |
| Clear, 20% range, Aim | 100 - 0 + 35 | 100%; no benefit beyond the cap |
| Clear, 50% range, Guard reaction | 100 - 0 - 15 | 85% |
| Clear, 50% range, target's Shield facing attacker | 100 - 0 - 20 | 80%; 9 damage on hit |

### Chance colors

Color the **final chance**, after all modifiers, and always keep its exact percentage visible. Use these contiguous starting bands to fill the gaps in the owner's suggested examples:

| Final chance | Color | Label |
| --- | --- | --- |
| 100% | Green | Guaranteed |
| 70–99% | Blue | Favorable, can miss |
| 40–69% | Orange | Risky |
| 0–39% | Red | Poor |
| Illegal shot | Neutral gray, with a reason | Blocked / out of range / unavailable |

Thus 95% is blue, never guaranteed-green. The red band includes 0% for presentation consistency, although legal ordinary shots currently have a planned 5% floor. Do not present an illegal shot as a legal low-chance attempt. Color is a quick cue, not the sole explanation: the number, label and calculation breakdown must remain readable. Apply the same bands to direct shots and proposed-destination shot previews when those are implemented.

## Actions and damage

Retain ordinary Attack at 1 AP + 1 supply point, fixed 25 damage on hit and zero on miss. No criticals, random damage, graze damage or hit-location multipliers in this milestone's starting model. Cover changes hit chance, not damage after a successful hit. Shield multiplies successful damage, rounded to nearest integer with minimum 1: `25 × 0.35 → 9`. It stacks with environmental protection because it is a separate active defense. Example: full cover and Shield apply `max(cover, exposure)` and then Shield's -20, not two cover penalties.

Aim costs 1 AP and adds 35 to the next normal attack; repeated Aim does not stack. Firing consumes it even on a miss. Movement, Reload, incompatible stance changes and the next own activation clear it. Thus Aim followed by moving gives no bonus at the destination. Selecting another soldier does not erase Aim.

Keep Guard's existing trigger contract: spend all remaining AP, require at least one supply point, reserve one reaction, and spend supply only if firing. Check enemy movement at existing path checkpoints; an armed target may also retaliate against its attacker if it survives. Guard uses normal geometry/range, no facing cone, -15 instead of Aim, and ends after one shot even on a miss or at the next own activation. Example: no enemy crosses a legal firing lane, so no reaction and no supply spent. Do not turn it into unlimited fire or a reaction to every enemy action.

Keep Shield's 1 AP cost and inclusive 120° front arc, using horizontal directions between actual supported positions for both facing and incoming protection. Facing is fixed rather than tracking the selected threat. Skip spends remaining AP while preserving Shield; other incompatible committed actions and the next own activation clear it. It blocks Attack/Reload while active. Movement remains allowed: existing in-route Guard checkpoints retain Shield until Move completes; the completed destination has no Shield. Example: a frontal reaction during the route can receive Shield modifiers, while the same attack after arrival does not. Show that distinction in predictions rather than silently using destination state for the whole route.

## Prediction, determinism and implementation boundary

UI, AI, Guard and execution must use the same evaluation for identical state and action context. A move preview uses the destination's real support height and the resulting AP/supply/stance, with Aim and Shield canceled as appropriate. Example: a destination may offer a geometric firing lane but leave zero AP to shoot; report both facts. Queries never temporarily mutate a live unit or consume RNG.

Only an accepted shot consumes seeded combat RNG: draw a roll in `[0,100)` and hit if `roll < chance`. A roll of 58 misses at 58%; a 100% legal shot always hits. Record the actual roll, chance, damage and existing outcome evidence. Display the exact executed chance, without secretly changing it afterwards.

Before implementing new balance, give it an explicit combat/simulation revision through the existing replay format and validate it at load. The original audit found that the header did not reject an unknown simulation version; step 4 now validates it and rejects incompatible recordings. Future tuning changes must preserve that explicit validation, rather than merely writing a new string. Old recordings must either use deliberately retained old rules or be rejected clearly before playback; do not run them under these numbers and wait for divergence. Any editable tuning used for a battle must be reconstructible from its recording or explicitly incompatible when changed.

The implemented cover/range/height scalars share one ordinary editable resource, consumed by existing CombatRules/action code. The exposure table is unchanged; Aim, Guard, base accuracy, limits and damage now come from that same resource. Keep existing per-unit range and Shield capability resources. Do not add separate UI/AI formulas, a universal combat framework, or a manual mesh-boundary workflow. The geometry-aware cover check and two editable cover values shipped in step 5; real support-height shot anchoring shipped in step 4. Existing evaluation fields separate cover, exposure and combined protection. The numerical preview reports the authoritative contribution fields and separately states damage on hit.

The [step-3 controlled examples](combat-controlled-examples.md) are now available in the existing editable range. The [step-4 geometry/LOS fixes](quality/combat-geometry-los-2026-11-16.md) are also implemented. The [step-5 cover/flanking work](quality/combat-cover-flanking-2026-11-16.md) is implemented as well. [Step 6: height and range](quality/combat-height-range-2026-11-16.md) is implemented. [Step 7: accuracy and damage](quality/combat-accuracy-damage-2026-11-17.md) implements the Aim retune, shared scalar settings and deterministic-resolution checks; [step 8 defensive-action review](combat-defensive-actions.md) is complete; [step 9 decision previews](combat-decision-previews.md) is complete; [step 10 destruction scope](combat-destructible-cover.md) is decided: defer live destruction and retain the offline crate proof; next is step 11, reliability tuning. Implement the geometry, cover, tuning and replay changes in their planned steps with focused regressions. Reuse existing scenes/assets and test both shot directions, corners, openings, fractional heights, partial exposure, modifier clamps and reaction/destination distinctions. Destructible cover is not enabled: safe live geometry replacement, occupied-point preservation and replay object state remain future work.

Documentation verification: independently calculated 17 numerical cases above (counting the two height directions separately), Shield's rounded damage, a 1,001-point monotonic range sweep, the 60% plateau, color-band boundaries and both height caps; all passed. Local documentation links and whitespace checks passed. No gameplay suite or rendered test was run for the step-2 documentation-only decision. Geometry verification subsequently shipped in step 4, linked above; the later step-6 report records executable verification for range and height; step 7 now verifies +35 Aim and fixed damage, while step 9 now implements the presentation bands.

## Comparison source locations

Read-only SDK inspection on 2026-11-16; no SDK code or assets copied into FuseFire:

- Both installed SDKs: `Development/SrcOrig/XComGame/Classes/X2AbilityToHitCalc_StandardAim.uc`. Base SDK: cover modifiers at lines 398/402, height branches 455–463, range lookup 681. War of the Chosen: cover 426/430, angle logic 435–478, height 483–491, range lookup 729; difficulty assistance in `GetModifiedHitChanceForCurrentDifficulty`.
- Base SDK `XComGame/Config/XComGameCore.ini:912` and War of the Chosen equivalent at line 1014: low/high cover 20/40.
- These are installed source snapshots, not proof of every shipping patch, mod or native visibility detail. FuseFire's formula and geometric protection proxy above are our design choices.
