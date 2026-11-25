# FuseFire tactical AI architecture

Source baseline [`0df1700bb3697283f0feb350c2159303fb6068af`](https://github.com/Melo9002/fusefire-proving-grounds/tree/0df1700bb3697283f0feb350c2159303fb6068af), integrated after Milestone 05. The AI implementation is identical to the Step 12 merge `d51d83c`. Main advanced through the Ironclad changes. Research tracks [#87](https://github.com/Melo9002/fusefire-proving-grounds/issues/87) and responsiveness tracks [#4](https://github.com/Melo9002/fusefire-proving-grounds/issues/4).

## Verdict

**Keep the hybrid controller, shared tactical authority and replay architecture. Prioritize making expensive occupied path searches resumable.** The AI has clear authorities for turn order, objectives, legal actions and playback. Utility scoring solves genuinely contextual choices, while fixed priorities protect fragile mission behavior. The controller has accumulated coordination, scheduling, routing, trace construction and action order in one place. That makes changes expensive to verify, but evidence does not justify replacing the decision model. A small internal separation between paired route computations and decision scheduling would support the highest-value performance experiment.

| Read | What it answers |
| --- | --- |
| [How the AI plays and where the code lives](implementation.md) | What the AI sees, how it chooses, and who owns each responsibility |
| [Seven source-editable diagrams](diagrams.md) | Lifecycle, code, action precedence, squad, frame timing, determinism and F3 |
| [Decision walkthroughs](walkthroughs.md) | Interception, carrier coordination and combat decisions with recorded candidates and receipts |
| [Responsiveness and improvement plan](performance.md) | Fresh and historical measurements, invalidation boundaries, experiment order |
| [Architectural health and industry comparison](assessment.md) | Strengths, concrete weaknesses and where alternative designs fit |

The [AI roadmap](../ai-2-plan.md), [current behavior history](../ai-current-behavior.md), [Step 11 profiling](../quality/ai-step11-profiling-f3-2026-11-24.md), [Step 12 acceptance](../quality/ai-step12-acceptance-2026-11-25.md) and [F3 guide](../debug-inspection.md) retain their original scopes. This research traces the integrated code and adds three fresh simulation traces plus a normal-speed probe. See the performance report for evidence scope and reproduction.

## Explain it in a minute

Each unit gets an activation in a turn sequence. It examines the live board, asks the objective system what it should be doing, and shares temporary plans with its side. A sequence of rules tests mission work and urgent needs, then looks for good combat or support choices. Those choices have their own scores. A soldier can spend one action on a better firing position, check what actually happened, then choose again. The action service checks the live board and is the only route from an AI combat proposal to an authoritative move, shot or mission action. A replay reconstructs the battle and resubmits saved actions through that service.

Think of a rescue escort blocking a narrow passage. The shared squad context points out which cells the carrier needs. The escort considers normal legal moves and can yield into a side cell. The carrier then finds or resumes a usable route. The record can explain the escort's choice and show the committed movement receipt. If no legal space exists, the system can hold the route and wait. A coordination hint can include a teammate's current cell because it describes a possible lane after that teammate moves.

## Scope

The research branch contains documentation and compact evidence. Gameplay, configuration, scoring, scheduling, action authority and replay code are outside the changes. [Verification and open questions](performance.md#verification-and-open-questions) records the checks and their limits.
