# AI 2.0 Step 10 — Difficulty and encounter pacing

Baseline `11497beff352fde5d0def61e465fb4eba0a2b7a0`. Review branch `codex/ai-step10-difficulty-pacing`. All observations are automated and use the current authoritative battle rules.

## What the policy actually controls

The controller obtains legal actions from the battle, filters mandatory mission and squad constraints, then scores the remaining options. Difficulty changes target and movement preferences, the exposure tolerance for a second advance, candidate selection lapses, and whether the controller compares Move → Attack when it already has a shot. Commander doctrine composes preference weights and a small exposure tolerance adjustment. Movement profiles add context such as escort, carrier, flank or objective route. Every tier observes the same live state and uses the same costs, damage, accuracy, movement rules and action service.

| Policy | Behavior and values |
| --- | --- |
| Easy | Shoots from the current cell when a shot is available. The existing combat lapse is 22% with up to a 15-point shortlist margin. It gives less weight to finishing, cover and danger, and tolerates a modest increase in exposure for a second advance. |
| Normal | Compares repositioning with shooting immediately. Repositioning still needs sufficient AP and supply, a useful gain and an acceptable exposure result. Its combat lapse is 8% with a 12-point shortlist margin. |
| Hard | Uses the same short plans, has no random lapse, and gives more weight to finishing, cover and incoming lanes. It now discounts its wound bonus by the probability that at least one affordable shot connects. This uses the same shot forecast and AP/SP horizon as finishing probability. |

`expected_damage_weight` is an active term with the same value for all three presets. `survival_separation_weight` affects survival position scoring. `survival_cover_weight` is retained for compatibility and has no production consumer. The standalone `score_target()` and `score_path_progress()` methods are exercised by compatibility tests, while live choices use `AITargetScorer` and `AIPositionScorer`. Mission action ordering, carrier rules, hard reservations and the authoritative movement inventory can take a choice out of the scoring contest entirely.

## Failures and changes

| Controlled case | Baseline behavior | Review behavior |
| --- | --- | --- |
| One AP and two legal shots | Hard preferred the enemy on 1 HP with a 30% hit chance. Its missing-HP bonus outweighed a 100% shot dealing 25 damage to a healthier threat. | Hard values the wound bonus through attainable hits and takes the clear shot. Normal keeps its existing wounded-target preference in this setup. Existing tests retain clear finishing shots, multi-shot planning, the Easy/Hard repositioning difference, and keeping a good shot. |
| Forced Easy lapse on a required extraction route | An eligible lower-rated route destination consumed a seeded decision roll. | Legal objective travel still uses the tier, doctrine and route layer, but the movement choice does not roll a lapse. Combat target and movement alternatives retain their existing legality, score, exposure and mission-value filters. |
| Neither hostile is currently shootable and the farther one can escape | The defender walked toward the nearer hostile, away from the runner's lane. | The defender advanced toward the imminent runner. Reducing that runner's speed in the same setup kept ordinary pursuit. |

The interception priority applies to defenders with the active Stop Enemy Evacuation objective after immediate combat and reload choices. A read-only route and the runner's next full move budget identify urgent lanes. A trace explains the selected enemy, waypoint, estimated travel cost and budget. The defender uses the ordinary movement scorer and action service, including the exposure check for later advances. The estimate can miss an intercept where terrain makes the geometric prefilter misleading. It does not predict a future reaction or assume that the enemy will follow the path.

The full Step 08 and 09 squad and carrier paths remain in use. The interception move reuses the objective route profile. Default, Cautious and Aggressive leave planning capabilities, wound reliability and lapse parameters at their difficulty values. Commander behavior tests evaluate the same legal candidates with each doctrine and establish real preference reversals between protection and offense. An aggressive preference can accept exposure without making forbidden moves legal.

## Real-map experiment

The current harness ran three Generic units per side, Default doctrine, and both sides at the same difficulty. It ran Eliminate, Rescue and Enemy Evacuation across all three current sites at seed 17, plus Normal Enemy Evacuation at seed 16 on all three sites. The 30 configurations were run on the base and the review implementation. Rescue includes the existing additional friendly and casualty setup. Comparing symmetrical policies is useful for pacing and legal execution. Victory rate alone cannot rank the tiers.

```powershell
# Run at the base revision with step10-before tags, then at the review revision with step10-after tags.
foreach ($tier in @('EASY','NORMAL','HARD')) {
    godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- "tag=step10-after-$tier" "difficulty=$tier" 'mission=ELIMINATE,RESCUE,ENEMY_EVACUATION' 'seeds=17' profile-ai
}
godot_console --headless --path . --script res://tests/ai_baseline_report.gd -- tag=step10-after-evac16 difficulty=NORMAL mission=ENEMY_EVACUATION seeds=16 profile-ai
python tools/quality/ai_baseline_compare.py artifacts/ai-baseline/step10-before-NORMAL artifacts/ai-baseline/step10-after-NORMAL
```

| Configuration | Victories | Rounds | Decisions | Committed actions | Wait / Guard | Unchanged sample intervals |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Easy, seed 17 (9 matches) | 5 → 4 | 40 → 40 | 608 → 582 | 595 → 571 | 13 / 11 → 8 / 12 | 9 → 9 |
| Normal, seed 17 (9 matches) | 5 → 6 | 45 → 47 | 610 → 627 | 599 → 616 | 29 / 24 → 30 / 25 | 13 → 13 |
| Hard, seed 17 (9 matches) | 4 → 6 | 61 → 69 | 691 → 749 | 680 → 738 | 42 / 38 → 53 / 40 | 21 → 24 |
| Normal evacuation, seed 16 (3 matches) | 3 → 3 | 17 → 17 | 197 → 197 | 198 → 198 | 14 / 4 → 14 / 4 | 4 → 4 |

All 60 runs reached a mission result with zero rejected actions or technical stalls. Sixteen pairs were identical, including all three seed-16 controls. Median first sampled HP loss was round 3 in each group before and after. The review runs contained one direct move return, versus zero before. The sample recorded more waiting on Hard, much of it in evacuation matches that continued after the early escape was prevented. This pass improves a specific intercept decision. It does not establish uniformly faster engagements.

### Seed 17 enemy evacuation

| Site | Easy | Normal | Hard |
| --- | --- | --- | --- |
| Service Depot | Defeat → Defeat | Defeat → Defeat | Defeat → Victory |
| Freight Yard | Victory → Defeat | Defeat → Victory | Defeat → Victory |
| Fleet Station | Defeat → Defeat | Defeat → Defeat | Defeat → Defeat |

- On Normal Freight Yard, the first different decision is PlayerUnit2 advancing toward the runner at `(23, 0, 29)` instead of pursuing the other enemies at `(15, 0, 25)`. The same activation records a committed attack on EnemyUnit2. There is no Extract in the review trace and the mission concludes in round 5. Hard also opens a shot from the lane and wins in round 7.
- On Hard Depot, the first redirect sends PlayerUnit2 toward the outside lane. The squad later reaches the exit approaches, PlayerUnit3 shoots EnemyUnit2, and the mission concludes in round 7. On Normal Depot the same first redirect spends the rest of the activation approaching the exit. The runner still boards in round 3. A late approach can be legal and useful without arriving in time to prevent escape.
- On Fleet Station the runner still commits Extract on every tier. On Hard, PlayerUnit2 attacked the runner even as PlayerUnit1 redirected toward the projected lane. Those decisions did not stop the escape. The sampled traces do not establish that the opening is unwinnable or identify an earlier intercept that this policy can guarantee.
- Easy Freight Yard changed first on **an evacuee's** own mission move, before the defender applies the interception policy. Removing objective-route lapses also improves the fleeing side's consistency. This is a real outcome tradeoff in the symmetrical harness. Rescue resolves on all three Easy seeds as before, with one additional round on Freight Yard.

### What the pacing measures mean

Wait and Guard are separate decisions. Guard reserves a reaction, so a Guard count measures commitments and cannot establish how often they fired. A Wait after no useful legal support cell, such as an escort already near its carrier with no safe advance or shot, can preserve the mission. Hard's baseline Depot elimination shows another pattern. Both lines held for several activations even though there were legal movement cells. The scores show the exposure/hold threshold rejecting approaches until the existing urgency ramp increased progress value. That is an identifiable pacing pressure, with an existing recovery mechanism. The traces do not establish a better opening policy across maps, so the general defensive threshold and Guard/Shield policy were preserved.

The summary counts immediate A→B→A returns and unchanged sampled objective/HP/alive intervals separately. The latter can include normal defensive activations. First sampled HP loss is a coarse engagement measure and may miss earlier shots. The harness does not record per-shot net damage by side in its action-outcome rows. Combat event and HP samples can explain a particular engagement, without treating extraction, overkill or removal as damage totals.

## Validation and cost

- The original target/intercept fixture failed three assertions at the base. Restoring the base controller in the diagnostic checkout also failed the forced objective-lapse check. The final controlled AI suite passed 230 assertions, including the slower-runner negative control.
- Catalog validation passed with 304 scripts and 304 entries. The 25 targeted checks cover AI, commander composition and behavior, hard constraints, rescue/carrier recovery, mission AI, action authority, loaded traversal, determinism, and battle/rescue/traversal replay. The first selection passed 24 tests in 331.69 seconds and flagged an obsolete near-tie setup in the squad focus test. That fixture now uses one affordable shot and a slightly more wounded rival, retaining its original requirements that the old fixed focus penalty would choose differently and the live focus rule chooses the finisher. Its 39 assertions passed on rerun in 9.09 seconds.
- Normal Freight Yard and Hard Depot seed-17 evacuation were rerun with profiling disabled. Both matched their full decision records, committed outcomes, round samples excluding elapsed time, and final states.
- The existing movement planner's profiled work averaged about 35.5 → 37.2 ms per plan across the matrix. The highest recorded value was 164.6 → 175.9 ms. These measurements exclude frame yields and the interception route lookup, and the review batch overlapped a separate validation checkout on the same machine. They are coarse observations, without a claim about a frame budget or an end-to-end CPU regression. The three primary baseline groups took about 323 seconds and the extra seed-16 control about 41 seconds. The full review batch took 382 seconds.
- Human play and the full Ironclad suite were outside this pass. Remaining scope includes earlier lane assignment on Fleet Station, defender movement when no credible intercept exists, and the separate cost/diagnostic work of Step 11.

Recommendation for integration review. Accept the narrower targeting and interception improvements if the demonstrated Easy evacuation tradeoff is acceptable. Treat pacing beyond these cases as open and use human play to assess how the longer successful defenses feel.
