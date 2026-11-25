# Follow a real decision

[Architecture index](README.md) · [Diagrams](diagrams.md) · [Performance and rerun commands](performance.md) · [Captured decision and timing excerpts](evidence/samples.json)

The fresh runs used the normal battle scene on integrated `0df1700`, the named sites, Default doctrine and both sides automated. “Decision” refers to a historical explanation and “transaction” to a committed action. The two identifiers happen to match in the examples below. A decision can carry its linked receipt inside the record or receive it through the later outcome signal. Earlier move positions and target candidates can remain in the next explanation within the same activation. Treat the reason and appropriate typed candidate list as the scope of each observation.

## Freight Yard · Intercept an escaping runner

**Normal, seed 17, 3v3, Enemy Evacuation.** Decision 38, PlayerUnit2 at (19, 0, 27), has 3 AP. The active intent is Stop Enemy Evacuation. EnemyUnit1 and EnemyUnit2 are out of range. EnemyUnit3 has a blocked shot. These are recorded attack-query outcomes. The no-shot fallback reaches `_evacuation_intercept`, which projects EnemyUnit2's 12.5-cost exit route against a next-activation budget of 15 and identifies (38, 0, 38) as a cell the defender can plausibly influence.

The projection becomes a goal. The live move inventory and route/corridor checks still decide which tile the soldier can actually enter this action.

| Candidate | Recorded utility | Explanation |
| --- | ---: | --- |
| (23, 0, 29) | 24.32 | Chosen. Progress term around +45, exposure term −21. |
| (22, 0, 30) | 19.04 | Similar incoming exposure and lower progress. |
| (22, 0, 29) | 15.02 | Lower progress still. |

Transaction 38 committed the move, AP 3 → 2 and revision 45 → 46. Decision and transaction 39 then recorded an Attack on EnemyUnit2 at 100% forecast, AP 2 → 1 and SP 2 → 1. EnemyUnit2 was the only legal target in that decision record. The match ended in round 5, Victory, with no enemy Extract. This traces the recorded attempt and outcome. An unplayed alternative move could also have succeeded. See [A, C and F](diagrams.md).

## Service Depot · A carrier advances and escorts coordinate

**Hard, seed 16, 5v5 plus ally, Rescue.** At (22, 0, 3), PlayerUnit2 legally picks up the adjacent casualty in transaction 39. AP stays 1 and revision advances 45 → 46. The intent changes from Rescue to Extract. The selected movement profile stacks Objective Route and Carrier. The recorded corridor claim holds 38 cells at decision 40.

Four live route queries lead into the legal movement comparison. (23, 0, 4) scored **12.05** and won. (23, 0, 5) had more nominal progress but a crowding adjustment of about −14 and total **4.80**. (23, 0, 3) scored **4.72**. All three are scored candidates from the legal movement lane. Move committed AP 1 → 0 and revision 46 → 47. PlayerUnit3 subsequently used the Escort profile to move from (14, 0, 12) to (17, 0, 10), after which the stored corridor had 37 cells. The recorded choice beat (18, 0, 11), whose firing benefit came with greater exposure. Transaction 41 spent 1 AP. Depot ended in round 12, Defeat, with zero rejected receipts seen by the simulator. This trace establishes local progress and support, and does not establish delivery.

**Controlled blockage and recovery, using a real battle scene.** The same implementation was independently checked in [the corridor scenario](../../tests/ai_decision_scenarios_test.gd), `_carrier_corridor_recovery`. The fixture uses the live swept-body planner and action commits. Carrier (8, 0, 10) rescues the casualty, while the escort actually occupies exit (12, 0, 10). An open recess (12, 0, 11) appears in the escort's legal moves. The escort commits Move and records Support, after which the carrier commits Extract. With two blockers the first yield leaves the route blocked and the second escort must clear its own recess. An available alternative exit avoids an unnecessary yield. Closing the recess with no alternative leaves the escort in place and the carrier unable to move through it or extract, including on repeat activation. The defeated-handler companion case checks that a surviving escort can pick up the casualty through a real Rescue action. These controls establish causal recovery that the complete-match excerpt alone cannot isolate. See [D and E](diagrams.md).

## Freight Yard · Move before firing, Aim, or hold

**Normal, seed 17, 3v3, Eliminate.** Decision 36 is after a completed reposition. Before moving, EnemyUnit3 was the only legal target in that inventory, with 55% hit chance. EnemyUnit1 was blocked and EnemyUnit2 was out of range. The record says immediate shots valued **35.9**, while moving to (16, 0, 16) and budgeting two 100% shots valued **45.0**, clearing the required benefit and exposure gates. Those are the plan's estimates, not damage receipts. Transaction 36 was a Move, AP 3 → 2, revision 43 → 44. No two-shot commitment was made by submitting it. The [paired Move→Attack fixture](../../tests/ai_decision_scenarios_test.gd) asserts a subsequent attack and a better shot, and has negative controls for a good current shot, one AP and Easy difficulty.

Decision 57 gives a cleaner view of an Aim comparison. PlayerUnit1's legal shot at EnemyUnit1 was 50%. The recorded plan valued two direct shots at **25.0** and two shots with Aim at **33.75**. Aim spent AP 3 → 2 at transaction 57, revision 68 → 69. The service applies the actual hit result later. In the same match, PlayerUnit2 at 25% HP selected Defensive and Wait at decision 60. EnemyUnit1 was blocked from the current position. The recorded reason counted 35 cells outside the route and 22 moves below the acceptance threshold. Wait committed at revision 71 → 72. The match ended in round 7, Victory. See [C and G](diagrams.md).

## Reading the evidence

The [JSON excerpt](evidence/samples.json) retains actual numerical records, selected receipts, selected position samples and profile rows. It shows, for example, that the Move→Attack entry carries a post-move cell and no ranked move table. The printed summary captures what the planner compared. It cannot recover every evaluated destination or their pre-move positions. Scope the evidence to the fields reproduced here. Full fresh JSON and engine logs remain under local ignored artifacts. [Reproduction commands](performance.md#reproduce-the-evidence) describe how to generate them again.
