# AI step 7 results: named movement profiles — 2026-11-18

Design: [AI step 7 design](ai-step7-design-2026-11-18.md). Evidence: automated (E2) plus three 48-match baseline runs (3 sites x 8 missions x seeds 16 and 17, Normal, 3 against 3). No human playtest. Starting commit `4caa382`.

## What changed

| Slice | Change | Behaviour |
| --- | --- | --- |
| **A** | `AIMovementProfile` (an editable Resource): multipliers on the position score (route progress, goal progress, cover, exposure, firing, danger, crowding) plus two extra terms. The two hard-coded role blocks in `AIPositionScorer` (objective route, carrier) became the `objective_route` and `carrier` presets with the same numbers; `AIMovementProfiles` selects the layers and says why; every movement decision records `movement_profile`. | **Identical.** 48 of 48 matches identical to a reference run on the previous commit (decisions, outcomes, final states; explanation text excepted). |
| **B** | Five new presets (`defensive`, `aggressive`, `flanking`, `escort`, `support`), the two new terms (`flank_weight`, `ally_cohesion_weight`, computed by `AIMovementContext`) and the rules that pick a stance. | **Intended change**, measured below. |

## How a decision is shaped now

1. **Difficulty** sets the weights (how well the AI plays). 2. **Commander** multiplies them (team doctrine; Default, Cautious, Aggressive). 3. **Profile layers** multiply the position score terms for what the unit is doing right now. The three stay separate; the decision record names the layers and the reason (`movement_profile`), and the existing commander composition snapshot is unchanged.

Layers: the context layers first (`objective_route` when the mission intent is a route; `carrier` when carrying), then at most one **stance** chosen in this order, each with a reason string:

| Order | Stance | Chosen when |
| --- | --- | --- |
| 1 | escort | a rescue carrier exists and the unit is not it |
| 2 | defensive | HP at or below 40%, or out of ammunition, or outmatched (two or more hostiles can shoot it beyond the allies nearby) |
| 3 | support | the unit is a support archetype, or an ally within 10 cells is at or below 50% HP |
| 4 | flanking | an ally already has a legal shot at a hostile |
| 5 | aggressive | HP at or above 70% and either a wounded target (40% HP or less) is in reach or the unit has the local advantage |

A carrier takes no stance; a unit on an objective route takes only the escort stance, so a tactical stance never pulls a mission unit off its goal. The thresholds are named constants at the top of `ai_movement_profiles.gd`.

**Legality is untouched.** Profiles re-weight cells the shared queries already allow; the candidate set, the exposure check on second advances and the squad vetoes are the same. A test checks a cell held by another unit is vetoed under all six non-default profiles.

## Slice B effect on the baseline

Slice B against slice A (identical to the reference):

- **Use:** layer mentions across the movement decisions (a decision on an objective route can name two): Default 1,156, Objective route 849, Flanking 403, Support 235, Escort 91, Aggressive 87, Defensive 65, Carrier 46. Flanking and Support are the stances that matter in these battles.
- **Outcomes:** 37 Victories became 34; 19 of 48 matches ended differently or at a different length. All 48 still Completed (no stalls, timeouts or round limits). Rounds 258 to 256, decisions 3,367 to 3,284. One match ran long (`freight_yard-ELIMINATE-16`, Victory in 8 rounds became Defeat in 16).
- **Shot quality** (the same AI plays both sides, so win counts cannot say whether it is better; shots can): expected damage per attack, players and allies 19.74 to 20.13, enemies 20.50 to 20.80. Attacks made: players and allies 350 to 335, enemies 347 to 364. Moves made: players and allies 1,102 to 1,062.
- **Balance consequence:** enemies gain more than the player side (total expected damage +6% against −2%), because mission-bound player units take fewer stances than free enemy hunters. That is a pacing question for step 10, recorded here and not hidden.

## Tests

`tests/ai_movement_profile_test.gd` (41 checks): the catalog and the exact numbers of the former hard-coded blocks; the scorer arithmetic (only the route term doubles on an objective route; layers multiply in order); every stance rule, reason and precedence; the same two cells ranking differently under Defensive, Default and Aggressive; flanking and cohesion (a new bearing beats the ally's line, no lane means no bonus, no context means zero); a hard veto under every profile; and a real decision recording that a hurt unit moved under Defensive and why. A mutation check (flank weight set to zero) makes the flank test fail.

## Failures found along the way

1. **Defective callers:** two test files and one more scorer test passed a bool where the scorer now takes layers, so the AI suite failed to parse; callers updated.
2. **Intended contract change:** the carrier test relied on the scorer applying the carrier weighting by itself; the weighting is now the carrier layer and the test passes it explicitly. The assertion is unchanged.
3. **My own test error:** a scenario compared a hostile against a unit of its own faction (never legal); fixed the fixture, not the assertion.

## Editing a preset

Each preset is a Resource in `systems/ai/profiles/`: open it in the Inspector and change a multiplier (1.0 leaves a term alone; `firing` 0 ignores firing lanes) or `flank_weight` and `ally_cohesion_weight` (zero by default). Adding a preset means a new `.tres`, one line in `AIMovementProfiles.all()`, and a rule in `_stance` if it should be chosen automatically.

## Limits

- The stance thresholds and preset numbers are first values: sensible, tested for direction, **not tuned**. Step 10 owns tuning.
- The new terms and stances act in the main movement planner only; escort-position and carrier-route scoring still use the context layers alone.
- The escort stance rule is the same "a carrier exists and I am not it" test the escort code already uses, so it also applies to units that are not assigned escorts.
- Flanking looks only at the nearest hostile an ally already has a shot at; it does not plan a coordinated pincer (step 8).
- The profile is in every movement decision record and has its own line in the F3 decision panel ("Movement profile"). The F3 position heatmap and candidate list are unchanged.
- One difficulty, two seeds per site and mission: a direction, not a distribution. Not play-tested by a person.
