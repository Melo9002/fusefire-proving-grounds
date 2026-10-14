# Scoring and priority reference

## Hard constraints versus soft preferences

Hard constraints remove an action or candidate entirely. They include authoritative action validation, AP/SP costs, actor defeat, action-service busy/stale state, faction hostility, range, line of sight, occupancy, movement budget, traversal, sealed diagonal rules, objective ownership, terminal/rescue/extraction rules, Shield/Guard restrictions, Jammed Aim restriction, reserved carrier corridors, and the safe-second-advance exposure gate.

Soft preferences compare candidates that survived those constraints. They include target scores, position scores, hold thresholds, recent-cell penalties, survival separation, escort spacing, crowding penalties, and difficulty lapses.

The top-level action ladder is neither a hard legality rule nor a utility score. It is policy priority: an earlier successful branch prevents later branches from being considered on that iteration.

## Position score

`AIPositionScorer.evaluate()` returns:

```text
total = progress + cover + exposure + firing + danger + squad
```

All components below are multiplied by the matching difficulty-policy weight.

### Progress

```text
progress = route_progress * (8 if objective route else 4)
         + (distance(start, goal) - distance(candidate, goal)) * 1.5
```

Both terms use `movement_progress_weight`. `route_progress` is the reduction in weighted path cost from the complete route, except maximum-urgency occupied-origin recovery may use geometric distance improvement.

### Cover and incoming exposure

For each living hostile in its attack range from the candidate:

| Fact | Raw adjustment |
| --- | ---: |
| Low directional cover toward hostile | cover `+4` |
| Full directional cover toward hostile | cover `+7` |
| Hostile has LOS, no cover | exposure `-14` |
| Hostile has LOS, low cover | exposure `-9` |
| Hostile has LOS, full cover | exposure `-5` |

The cover reward applies when the hostile is in range even if LOS is blocked; exposure applies only with LOS. This overlap intentionally rewards a defensive edge while separately pricing the actual firing lane.

### Firing opportunities and danger

For each living hostile:

| Fact | Raw adjustment |
| --- | ---: |
| Actor could fire from candidate and target has cover | firing `+6` |
| Actor could fire and target has no cover | firing `+10` |
| Hostile within distance 2 | danger `-8` |
| Two or more incoming LOS lanes | danger additional `-9 × (lanes - 1)` |

Carriers receive no firing reward. For objective-route travel, firing is set to zero, exposure is multiplied by `1.5`, and cover by `1.25`. For carriers, exposure is further multiplied by `2.5`, danger by `2`, and cover by `1.5`.

### Squad, revisits, and acceptance

- A destination or carrier corridor reserved by another unit returns `-INF` and is rejected.
- A candidate within distance 1 of another reserved destination receives raw squad adjustment `-12`.
- Recent origins receive `-6 × (history index + 1)` for each match in the four-entry history. Because older entries have lower indices, newer entries receive larger penalties.
- Ordinary movement must score strictly above `hold_score + 1 - urgency_bonus`.
- Carrier movement bypasses that threshold and later prefers positive-progress options.

Ordinary urgency begins after 3 consecutive low-value actions, rises by 3 per further action, and caps at 18. Escort urgency rises by 6 beginning with its first preceding low-value action and also caps at 18. Every three low-value actions widens the route corridor from 2 by 1, to a maximum of 4.

### Safe second advance

Exposure is recomputed as a positive risk count:

| Incoming legal range+LOS lane | Exposure |
| --- | ---: |
| Full cover | `+0.35` |
| Low cover | `+0.65` |
| No cover | `+1.0` |
| Hostile within distance 2 | additional `+0.5` |

A second Move is allowed only if:

```text
candidate exposure <= current exposure + safe_advance_exposure_tolerance
```

Normal and Hard tolerance is `0.01`; Easy is `0.4`.

## Survival and escort additions

Survival scoring starts with the normal position total, then applies:

```text
- 0.15 * distance(start, candidate)
+ min(distance_to_nearest_hostile, 12) * 1.5 * survival_separation_weight
- distance_to_nearest_extract_cell * 0.2
```

Escort positions must be 2–5 cells from the carrier and avoid its route. Their score subtracts:

```text
abs(distance_to_carrier - 3) * 2
```

Route-clearing positions subtract candidate distance to the carrier; an off-route candidate is preferred to a bottleneck-advance fallback.

## Target score

`AITargetScorer.evaluate()` returns:

```text
total = vulnerability + focus + vip + threat + mission
```

### Vulnerability and focus

```text
vulnerability = missing_hp * wounded_target_weight
              + (20 * finishing_bonus_weight if current_hp <= 25 else 0)

focus = -15 * number_of_other_allies_intending_this_target
        * focus_penalty_weight
```

A hostile VIP adds `25 * target_vip_weight`.

### Threat

For every living friendly the target can legally attack:

```text
threat += 8 * hit_chance / 100
threat += 4 if that friendly has <= 25 HP
```

Raw threat is capped at 28, then multiplied by `target_threat_weight`.

### Mission relevance

Raw mission bonuses are additive, then multiplied by `target_mission_weight`:

| Situation | Raw bonus |
| --- | ---: |
| Target carries a rescued unit | `+25` |
| Enemy-evacuation target within 2 of its exit | `+30` |
| Enemy-evacuation target within 5 of its exit | `+18` |
| Target can legally threaten protected actor | `+22` |
| Target within distance 3 of rescue target | `+10` |
| Target can legally threaten extraction carrier | `+22` |
| Target within 2 of extraction zone | `+8` |
| Target occupies Reach zone | `+16` |

Hit chance and expected damage are included in diagnostic records but do not add to `total`. This means a high-value legal 5% shot can outrank a lower-value 100% shot.

## Difficulty values

Unlisted values are `1.0` on every tier. Normal uses all `1.0` weights, lapse chance `0.08`, lapse margin `12`, and exposure tolerance `0.01`.

| Parameter | Easy | Normal | Hard |
| --- | ---: | ---: | ---: |
| lapse chance | 0.22 | 0.08 | 0 |
| lapse margin | 15 | 12 | 12, unused |
| wounded target | 0.35 | 1 | 1.3 |
| finishing bonus | 0.25 | 1 | 1.5 |
| focus penalty | 0.25 | 1 | 0.7 |
| movement progress | 1.1 | 1 | 1 |
| crowding penalty | 0.5 | 1 | 1.2 |
| survival cover | 0.6 | 1 | 1.35 |
| survival separation | 0.6 | 1 | 1.2 |
| second-advance exposure tolerance | 0.4 | 0.01 | 0.01 |
| position cover | 0.6 | 1 | 1.3 |
| position exposure | 0.55 | 1 | 1.35 |
| position firing | 0.7 | 1 | 1.25 |
| position danger | 0.6 | 1 | 1.4 |
| VIP target | 0.6 | 1 | 1.2 |
| target threat | 0.55 | 1 | 1.35 |
| target mission | 0.6 | 1 | 1.4 |

`survival_cover_weight` is configured and tested as a difficulty property but is not read by `_survival_position_score()` or `AIPositionScorer`. This is a confirmed inactive tuning parameter.

Easy and Normal may select a lower-ranked option only when it lies within the lapse margin. Movement additionally requires progress no worse than top minus 8, exposure no worse than top minus 4, and danger no worse than top minus 3. Target lapses require mission score no worse than top minus 8. Hard always selects index 0.

## Tie behavior

- Shield threats explicitly break equal hit chance by lexical tactical ID.
- Terminal approach cells break equal path size lexicographically by x, then y, then z.
- Reachable Move cells are sorted lexicographically by Pathfinder.
- Several other `score > best_score` comparisons retain the first candidate encountered.
- Target and movement option arrays sort only by score; an explicit secondary key is not supplied for equal scores.
- Nearest-hostile equality retains roster order.

The current fixtures are deterministic, but some equal-score outcomes rely on stable upstream iteration rather than a documented universal tie-break contract.

## Representative decisions

These examples are direct walkthroughs of implemented branches and constants. They are not claims that a particular unrecorded match produced them.

### 1. Guard after an unproductive activation

A unit reaches the late defensive portion of `_run_activation()` only after no mission step, legal attack, useful reload, first approach, or safe second advance succeeds. Shield is tried first only when exactly 1 AP remains and a legal incoming threat exists. Guard then requires:

```text
query_overwatch(unit).is_legal()
consecutive_low_value_actions == 0
and at least one hostile either:
    is legally attackable now, or
    is within attack_range + hostile.speed
```

There is no Guard utility number. If these predicates pass, Guard consumes all remaining AP and reserves one reaction. When several units independently reach this branch in the same round, they can form the apparent coordinated trap observed in playtests.

### 2. Normal target selection

For a normal-difficulty 100-maximum-HP target currently at 25 HP, before VIP, threat, mission, or focus adjustments:

```text
missing HP = 75
finishing bonus = 20
vulnerability = 75 + 20 = 95
```

A healthy 100/100 target starts at 0 vulnerability. One ally already intending the wounded target changes its total by `-15`, leaving a net 80-point advantage from these two components. Legal-shot geometry is a hard prerequisite, but hit chance does not change this score. The focused target-scoring test verifies the wounded/finisher increase and allied focus reduction.

### 3. Terminal objective on the final AP

With a terminal intent, the unit first queries the exact terminal action. If it is not adjacent, it finds the shortest legal adjacent approach cell, moves toward it through the scored objective-route movement path, then queries the terminal again immediately. If the Move spent the final AP, interaction can still succeed because terminal activation costs zero AP. The focused ability integration fixture verifies two ordered authoritative transactions: one Move and one terminal interaction, ending at 0 AP with the objective completed.

### 4. Position with an exposed firing opportunity

For a normal non-objective mover, a candidate with no cover that lies in one hostile LOS lane and also offers an unobstructed shot against an uncovered hostile receives raw firing `+10` and exposure `-14`, before progress, danger, and squad terms. Its local combat subtotal is therefore `-4`. Low cover changes those terms to `+4 - 9 + 10 = +5`; full cover produces `+7 - 5 + 10 = +12`. The position-scoring fixture verifies the signs and that directional cover improves the total. An objective-route mover receives no firing reward and multiplies exposure by 1.5, so the same open lane becomes less attractive.

