# Tuning, diagnostics, and maintainability

## What most strongly shapes behavior

The largest behavioral controls are not all numeric weights:

1. **Action-ladder order** in `AIController._run_activation()` determines which action families can preempt others.
2. **Mission intent order** in `ObjectiveManager.get_mission_intent()` determines the unit's strategic goal.
3. **Move acceptance threshold and urgency** decide whether cautious units advance or wait.
4. **Exposure and danger penalties** strongly shape second moves and firing positions.
5. **Mission target bonuses and vulnerability** dominate target selection.
6. **Squad reservations** prevent collisions, spread fire, and create carrier formations.
7. **Difficulty lapses** create bounded imperfection without changing legality.

Changing a weight can have no visible effect when an earlier action branch prevents that scorer from running. Tuning should therefore begin with recorded decision traces, not only constants.

## Existing observability

`BattleController.record_ai_decision()` already records:

- actor, action, subject, reason, and named alternatives;
- mission goal and difficulty;
- position and target summaries;
- all considered and rejected position/target candidates;
- chosen markers and component scores;
- squad notes;
- AP, grid position, recent origins, low-value count, hold score, movement threshold, urgency, and route corridor.

The F3 **Show AI decisions** view displays the latest summary. **Show AI scoring overlay** renders a movement heatmap, optional numeric labels, rejected cells, target diamonds, and component breakdowns. Failed simulations serialize structured decision trails in seed-failure reports. This is already a strong foundation for commander profiles and Goal 2 map diagnosis.

Useful future diagnostic additions, without changing policy, would be:

- log every top-level policy gate as `not considered`, `illegal`, `failed`, or `selected`;
- include authoritative query codes for Shield, Guard, Aim, Reload, and mission actions, as targets already do;
- record hold-position components alongside candidate components;
- record the chosen option's rank before a difficulty lapse;
- attach explicit tie-break provenance;
- separate “candidate was legal” from “candidate survived doctrine filters” in the overlay;
- provide a per-activation timeline joining consecutive decisions from the same unit.

## Confirmed maintainability findings

### The policy is centralized but long

`AIController` is about 1,070 lines and combines activation policy, mission adapters, carrier routing, movement candidate generation, target selection, diagnostics, and anti-stalemate state. Responsibilities remain identifiable and authoritative mutations remain outside it, so this is not uncontrolled spaghetti. It is nevertheless the main concentration of tuning interactions.

### Action priorities and scores use different mechanisms

Targets and positions expose detailed numeric breakdowns. Emergency Seal, Aim, Reload, Shield, Guard, and mission actions are selected by ordered predicates. A designer cannot compare “why Guard beat Shield” as two scores because no such comparison occurred. Documentation and diagnostics must preserve this distinction.

### One configured policy weight is inactive

`survival_cover_weight` varies by difficulty and is asserted by `ai_difficulty_policy_smoke.gd`, but neither survival scoring nor position scoring reads it. Difficulty still changes general `position_cover_weight`, so survival cover behavior changes indirectly, but this named parameter itself has no effect.

### Some tuning constants remain local

Many behavior-shaping values are embedded in `AIController`, `AIPositionScorer`, and `AITargetScorer`: route multipliers, cover/exposure/firing values, danger thresholds, mission bonuses, escort distances, revisit penalties, and urgency values. Difficulty multipliers are centralized, but the base doctrine is distributed across three files.

### Equal-score behavior lacks one universal contract

Several selections use strict `>` and retain first iteration order; sorted option arrays specify score only. Current upstream ordering and tests are deterministic, but adding new map/objective dictionaries or changing candidate production could alter equal-score choices. Shield and terminal approach already use explicit tie-breaks and show the intended standard.

### Diagnostic alternatives are descriptive

The recorded `alternatives` string names plausible actions but is written by each branch; it is not proof that those alternatives were legal or evaluated in that state. Candidate arrays are stronger evidence for targets and positions.

## Overlapping incentives

- Directional cover can add a cover reward and reduce the size of an exposure penalty. This is intentional double influence, but it makes cover particularly strong.
- Multiple incoming lanes contribute one exposure penalty per hostile and an additional crossfire danger penalty after the first.
- Objective movement combines weighted route progress and direct geometric distance improvement; both reward forward movement.
- Carriers multiply objective protection adjustments again, making exposed carrier routes extremely unattractive.
- Mission target bonuses can overlap with VIP, threat, carrier, wounds, and finishing bonuses.
- Focus penalty encourages spreading attacks, while finishing and mission bonuses encourage concentration. That tension produces useful behavior but is sensitive to difficulty weights.
- Anti-stalemate urgency lowers the hold threshold and widens route tolerance; at maximum urgency it can also admit detours and least-bad objective steps.

These are confirmed interactions, not necessarily defects.

## Potential risks and hypotheses

- **Target accuracy omission:** a valuable 5% legal shot can outrank a reliable lower-value shot. Whether this is undesirable requires playtesting; changing it would alter combat behavior.
- **Guard range estimate:** `attack_range + hostile.speed` ignores walls, path topology, and likely hostile goals. It can produce Guard that never triggers, although repeated low-value prevention stops immediate Guard loops.
- **No explicit elevation doctrine:** richer Goal 2 vertical maps may need no change if geometry supplies enough value, but this is unverified.
- **Objective-handler reservations are mostly informational:** the count generates notes, while most actual spreading comes from destination, target, and corridor reservations.
- **Nearest hostile fallback:** first approach movement pursues nearest world-space hostile rather than the highest-value unreachable target or objective-level squad plan.
- **Sequential teammate knowledge:** later units know earlier reservations, but earlier units do not anticipate later units. Roster order can therefore shape formations.
- **Long-lived per-unit history:** recent origins and low-value counters persist across rounds for that unit, intentionally providing memory but also making a decision dependent on more than the visible current board.

These are candidates for later investigation, not authorization to change behavior.

## Recommended tuning workflow

1. Reproduce a seed and mission with the same difficulty and roster.
2. Enable the AI decision and scoring overlays.
3. Inspect whether the unexpected outcome came from action-ladder order, authoritative illegality, doctrine filtering, scoring, a lapse, or turn progression.
4. Compare component totals and hold threshold before changing a constant.
5. Run the focused scorer tests, determinism test, stalemate seeds `25005` and `25100`, and Prototype 1 matrix.
6. Evaluate the same change across authored, standard generated, and refinery maps.

For future commander profiles, prefer selecting named policy weights and narrow doctrine predicates over copying `AIController`. A cautious profile could increase exposure, incoming-lane, and close-range danger penalties and lower its safe-advance tolerance. A gambler could accept more exposure for route progress, finishing opportunities, or an objective breakthrough. These profiles should influence candidate scores and selected doctrine; they must not bypass `TacticalActionService` legality.

Weights alone cannot express every personality because action categories are chosen by the ordered `_run_activation()` ladder before movement and target scores are compared. If a future commander needs to prefer a risky attack over defense, add a small policy hook at the relevant ladder decision rather than duplicating the controller or introducing commander-specific action execution. `SquadContext` can carry limited shared intent—such as a breakthrough lane, protected runner, or focus target—while individual units continue to choose and submit their own authoritative actions. This is proposed architecture, not current behavior.

## Further investigation before Goal 2 tuning

- Capture decision distributions across current baseline maps: Move, Attack, Aim, Guard, Shield, Wait, and objective action counts.
- Measure how often candidate movement is rejected as outside route, unsafe, below threshold, or squad-reserved.
- Compare high-ground selection frequency with equivalent ground positions before proposing an elevation bonus.
- Identify equal-score frequency and whether roster/iteration tie behavior is visible in play.
- Test Guard plausibility on walls, multi-floor interiors, alleys, and long route detours expected from Battlefield Generation 2.0.
- Test whether richer maps cause maximum urgency to accept tactically poor but technically legal detours.
- Decide whether future hidden interiors create a real visibility model; if so, define observable state before changing AI.

