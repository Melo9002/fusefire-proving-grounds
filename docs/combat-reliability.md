# Combat reliability — provisional balance baseline

Milestone 04 step 11, 2026-11-17. **Retain the current numbers for prototype playtesting.** The measured outcomes support distinct positioning and action tradeoffs; they do not justify a numerical change yet. This is an intentional retain decision, not a claim that balance or human playtesting is finished. Destruction remains deferred.

## What we measured

The [controlled check](../tests/combat_reliability_test.gd) uses actual CombatRules queries, TacticalActionService commits, physical compiled cover and real Guard retaliation. Each setup receives the same fixed seed range. Trials reset HP/AP/ammo and stance so the condition stays comparable; they are independent attacks, not a full simulated battle. Aim pays its real AP cost and is re-established for each aimed trial. Guard pays its remaining AP and consumes its reservation and one SP on hit or miss.

Ordinary hits remain **25 damage** and misses **0**. Step 12 additionally fixes the inclusive random endpoint so a displayed 100% cannot miss, with a new simulation identity; the balance scalars stay the same. No hidden rerolls, luck correction or accuracy-scaled damage were introduced. Modifier stacking remains strongest of cover/exposure, then range, actual height and explicit bonuses, with one final clamp/round.

The short-target cover fixtures include resolved within-cell standing points. Full cover still allows visible shoulder samples; a completely blocked shot remains illegal. Height examples hold total 3D weapon distance constant to separate elevation from range.

## Practical action tradeoffs

Aim is **+35 for the next shot only**, at 1 AP. With 3 AP, Aim → Attack → Attack gives one boosted shot and one ordinary shot. It does not give two boosted shots.

| Situation | Ordinary chance | Aimed chance | Expected damage: 3 ordinary shots | Expected damage: Aim + 2 shots |
| --- | --- | --- | --- | --- |
| Close, exposed | 100% | 100% | 75 | 50 |
| Close, low cover | 80% | 100% | 60 | 45 |
| Close, full cover in this fixture | 60% | 95% | 45 | 38.75 |
| Exposed, maximum range | 30% | 65% | 22.5 | 23.75 |

These expectations use the queried chances and 25 on hit; they assume no intervening kill/reaction, enough ammo and an unchanged target. Aim is especially useful for a crucial shot and ammo economy, rather than always being the best damage per activation. Against a target needing one hit, with 2 AP left, two ordinary 60% shots give an 84% chance of at least one hit; one aimed shot gives 95% and uses one SP instead of two. A 95% shot can still miss.

Guard has a **−15-point** reaction modifier and one reaction per reservation. At close exposed range that is 85%, or 21.25 expected damage per eligible opportunity. Blocked or absent opportunities produce no shot. Spending one otherwise-unused AP late in an activation differs greatly from spending all three AP immediately.

Shield reduces a frontal close exposed shot to **80% and 9 damage on hit**, or 7.2 expected incoming damage versus 25 unprotected. It is deliberately strong: 100 HP requires 12 such hits instead of four ordinary hits. Its fixed 120° arc, expiry and Attack/Reload restrictions matter. Rear fire remains 100%/25 in the same setup. Keep Shield strength on the real-map watchlist rather than weakening it based only on stationary frontal trials.

## How to test the retained settings

Use Match Setup → **Tactical Test Range — Test map**, population off. Inspect a close exposed target, the low crate, the full crate’s visible sides, and a flank. Compare the preview before and after Aim. Use the ramp/gallery to compare shots at similar total distance from different actual heights. At long range, moving closer should recover reliability; Aim should help without permitting a blocked shot.

For a Shieldbearer, face an enemy, Skip, then compare frontal and rear incoming attacks. Guard should explain its eligible opportunity and spend one SP even when it misses. Use the combat log and saved replay to check the sequence. An isolated bad roll below 100% is expected, not evidence that prediction is wrong.

Edit [the shared tuning resource](../systems/combat_cover_tuning.tres) for range, height, cover, Aim, Guard and ordinary damage. Shield values remain in its capability resource. Changing a setting must preserve the query/commit contract and replay compatibility checks; update the provisional numerical baselines deliberately. Do not change seeds or assertions merely to make distributions look nicer.

The [measurement report](quality/combat-reliability-2026-11-17.md) records exact results, the native test-shutdown failure and verification limits. [Step 12 prototype closure](quality/combat-closure-2026-11-17.md) now records the rendered real-map checks, replay matrix, query cost and green broad run. Human frustration, encounter difficulty and AI doctrine remain unproven by these measurements.
