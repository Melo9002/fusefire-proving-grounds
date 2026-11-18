# AI hard constraints, milestone 05 step 5 — 2026-11-18

Starting commit `0e3387a`. Evidence level: automated (E2) plus a 48-match behaviour comparison. No human playtest. The design context is in [AI decision pipeline](ai-decision-pipeline.md); the plan is [milestone 05](../ai-2-plan.md).

## Question asked

Can an attractive score make the AI take an illegal action, and when it cannot act, does it say why using the same reasons the player's UI would show? Step 5 asks for options to come from the shared action and movement queries, genuinely forbidden squad commitments to be distinguished from soft crowding preferences, and rejections to carry specific reasons.

## What the audit found

**Legality already comes from the shared queries.** Every AI action goes through `BattleController.query_*` (the authoritative `TacticalActionService`) and is committed through `try_*`, which validates again at submission:

| Constraint | Where it is enforced | Rejection code |
| --- | --- | --- |
| AP | every query and every submit | `insufficient_ap` |
| Supply points / ammo | attack, reload, shield, overwatch | `insufficient_supply_points`, `resource_full` |
| Shield stance rules | attack, reload, overwatch | `shield_stance_restriction` |
| Activation order, dead or missing actor/target | submit | `wrong_activation`, `actor_defeated`, `target_missing`, `target_not_hostile` |
| Stale plan, busy engine, pause | submit (AI plans are also discarded when the state revision moves) | `stale_revision`, `action_busy`, `paused` |
| Occupancy, bounds, body and route clearance | `query_move` legal destination set and the submit | per move result |

Attack candidates are exactly the hostiles `query_attack` accepts. Movement candidates are exactly `query_move`'s `legal_destination_cells`, so no score can add a cell to that set. A rejected AI move publishes an outcome with the service's reason. Nothing needed changing here.

**Goal finding is separate from legality.** A few helpers consult occupancy and the pathfinder directly to choose a goal or route (`_nearest_reachable_zone_cell`, `_nearest_terminal_approach_cell`, `_carrier_route`, `_path_to_target_neighbor`). They never commit anything: the move itself is always picked from the legal set. This is duplicated knowledge rather than a bypass, and is noted for step 9.

**Two real gaps in explanation:**

1. A wait caused by a blocked route said "no reachable legal destination" although 53 legal cells existed, and never named the blocker (issue #42). A branch meant to name an occupant ("Occupied by ...") was never produced anywhere.
2. Squad commitments were told apart only by a `-1000` sentinel inside a score and reported as a generic "Reserved by ally" with no owner.

## What changed

- **Blocked routes are named.** When a route cannot start, the controller explains it: "route to EnemyUnit1 is blocked by AllyUnit1 at (12, 0, 28)", or "no walkable route to X", or that it is closed to this unit. The note is cleared at the start of each activation and each approach, so a stale blocker is not reported once it moves.
- **The no-destination reason comes from the shared Move query.** If no move is legal the wait reason carries that query's own message (what the UI would show). If legal moves exist it states how many and that none was worth taking. Transient engine states (busy, paused, stale revision) are never given as a reason: they describe the moment, not the situation.
- **Squad vetoes are explicit.** `SquadContext.block_reason(actor, cell)` names a forbidden cell ("Destination reserved by X", "Corridor reserved by X") and `crowding_adjustment` is the separate soft penalty. `HARD_BLOCK` and `CROWDING_PENALTY` are named constants; `destination_adjustment` keeps its old values for existing callers. `AIPositionScorer` returns an infinite-negative total with the named reason, so no other score term can outweigh a held cell. The wait reason also reports "cells reserved by X".

## Proof that decisions did not change

The 48-match baseline (3 sites x 8 missions x seeds 16 and 17, 3v3, Normal) was rerun on the new code and compared with the step-4 reference, ignoring explanatory text (`reason`, `summary`, `position_scores`) and comparing every action, score, outcome, round sample and final state.

| Run | Result |
| --- | --- |
| Full 48 matches | **48 of 48 identical** apart from text |
| Text that changed | one distinct string, 10 occurrences: "no reachable legal destination" became a more specific reason |
| 4-match sample after the final wording fix | 4 of 4 identical |

The comparison also caught a flaw in my first wording: the new reason read "no legal destination (Another action is already being resolved or presented)" in those 10 cases, which blames a transient engine state. It was changed to "no destination was worth taking" and covered by a test. The last wording change only builds a string, so the full 48 were not repeated; the 4-match sample confirms it.

## Tests

- New: `tests/ai_hard_constraints_test.gd`, **32 checks**:
  - an illegal target is recorded with the shared Attack query's own code and reason, never chosen;
  - the no-AP and legal-moves-exist wait reasons;
  - a busy engine is not given as the reason;
  - a blocked route names the ally, and a stale blocker is dropped;
  - one AP never pays for a two-AP Aim plan;
  - squad vetoes name their owner, crowding stays soft, and the scorer cannot make a held cell attractive.
- Extended: scenario S6 (blocked corridor) now asserts the named blocker and that the old wording is gone. `ai_decision_scenarios_test.gd`: 55 checks. `squad_context_smoke.gd` still passes unchanged, so the refactor kept the old numbers.
- The new test fails on the old controller (checked by reverting it), though only partly for behavioural reasons: the new route note does not exist there. The scenario S6 assertions on the wait wording are the sharper behavioural check.
- Subsystems, final: assets 9, combat 39, movement 24, **AI 31**, replay 17, UI 26 passed, 0 failed (skips are the existing explicit-only checks).

## Failures found and how they were classified

1. **Defective test setup (fixed):** the first version stood a hostile on a cell the fixture reports unusable. The fixture flagged it; the test now uses a valid out-of-range cell.
2. **Misleading new wording (fixed):** found by the baseline comparison, above.
3. **Own defect avoided:** a local named `owner` would shadow a built-in Node property; renamed before it ran.

## Not done, and limits

- **Pre-positioning near a temporarily blocked passage** (the rest of #42) is not changed: the unit still holds where it stood. That belongs to step 9 (corridor yielding).
- **The duplicated goal-finding checks** stay as they are; they are not a legality bypass.
- **UI and AI agreement is by construction:** both read the same queries. It is tested for the AI's rejection code and reason against the query and for the Move message; there is no UI-level test.
- **Commitment expiry and timing** are step 8; scoring relative to the action is step 6. No planning performance was measured.
