# Prototype 1.5 Movement Migration Audit

Task 01.7 began at `589232d` on `p2-foundation`. This audit records the evidence reviewed before implementation. XCOM SDK references are local research references only; no XCOM source or assets are copied into FuseFire.

## Current FuseFire movement flow

| Stage | Verified owner | Current behavior | Assessment |
| --- | --- | --- | --- |
| Player preview | `BattleController` | Builds a reachable set directly from `Pathfinder`, filters occupancy, then calculates the hovered path again. | Duplicates the service's definition of a legal destination. |
| AI planning | `AIController` | Uses `Pathfinder` for long-range hypothetical routes and reachable cells, then filters occupancy before scoring. | Hypothetical routing belongs here, but active-turn legal destinations duplicate player/service rules. |
| Query/validation | `TacticalActionService.query_move` and `BattleController._query_move_data` | Resolves the stable actor ID, checks activation/AP, reachability, stoppability and occupancy, and returns the path plus traversal poses. | Targeted queries are authoritative and read-only. They lack an inventory form and useful structured budget/cost/AP facts. |
| Submission | `TacticalActionService.submit_move` | Revalidates revision and action window, reruns the movement query, spends one AP, and updates occupancy once. | Correct commit boundary. A preview never authorizes submission. |
| Occupancy | `GridManager.update_unit_position` | Releases the origin and claims the destination synchronously before presentation. | The committed occupancy is the destination reservation. Animation position is never tactical position. |
| Objectives | `BattleController.unit_moved` to `ObjectiveManager` | Reach/automatic Rescue consequences occur during the parent Move commit and are captured in the Move result. | Correct transaction ownership; they must not become nested replay actions. |
| Replay | Typed Move request/result and normal service submission | Reconstructs the request, validates revisions, resolves normally, compares the result and state fingerprint. | Correct shared simulation path. |
| Presentation | `TacticalActionPresenter.present_move` and `TacticalUnit.move_along_path` | Consumes the committed presentation path and traversal poses, blocks completion, and snaps to committed state when suppressed or interrupted. | Correct separation. Presentation does not choose legality, path, AP, occupancy, or objective outcomes. |

## Verified gaps

1. Player range display and AI active-turn candidate generation compute legal destinations independently of `query_move`.
2. `query_move` does not apply the service action-window check used by Attack queries, so hover/query behavior can disagree while another action is being presented or the tree is paused.
3. Movement query results omit movement budget, path cost, AP prediction, elevation delta, and a deterministic legal-destination inventory even though the UI, AI, tests, and diagnostics need those facts.
4. Destination ordering comes from an AStar connection traversal and is not explicitly stabilized before consumers iterate it. AI tie behavior should not inherit container iteration order.
5. Path cost exists in `Pathfinder` but is recomputed privately by AI and is not exposed with the authoritative movement query.

## XCOM 2 SDK movement trace

The inspected War of the Chosen SDK source root is:

`C:/Program Files (x86)/Steam/steamapps/common/XCOM 2 War of the Chosen SDK/Development/SrcOrig/XComGame/Classes`

### Rules and authoritative state

- `X2Ability_DefaultAbilitySet.uc` constructs the movement ability and its game-state builder. The builder reads `AbilityContext.InputContext.MovementPaths`, commits the unit's final tile with `SetVisibilityLocation`, applies ability costs, updates movement bookkeeping, and emits movement events including `ObjectMoved` and `UnitMoveFinished`.
- `XComGameStateContext_Ability.uc` carries `MovementPaths` with the ability context. The path accepted by the rules layer therefore becomes explicit input to both state construction and visualization.
- This is embedded in XCOM's object-history and ability-template framework. FuseFire does not need that framework to preserve the useful rule: validate a path, commit its final state once, and retain the accepted path in the resolved result.

### Pathfinding and AI

- `XGUnit.uc` owns the reachable-tile cache and exposes path construction through `BuildPathToTile`, falling back to `X2PathSolver.BuildPath` where required.
- `XGAIBehavior.uc` checks `m_kReachableTilesCache.IsTileReachable`, calls `BuildPathToTile`, rejects paths shorter than two points, scores candidate destinations separately, and submits the chosen path through the tactical movement operation.
- The useful boundary is that reachability is a tactical fact while destination value is an AI policy. FuseFire should share the former and retain `AIPositionScorer`, mission intent, danger, cover, squad reservations, and difficulty choices as AI-owned preference.

### Visualization

- `X2Action_Move.uc` reads the committed `XComGameStateContext_Ability` and its movement path, then performs locomotion, traversal, facing, camera, interruption, and resume presentation.
- It does not independently decide whether the destination was legal or choose a replacement authoritative route.
- XCOM's visualization tree, interrupt history chain, group movement, scamper, destruction, phasing, and string-pulling machinery solve requirements FuseFire does not currently have and are rejected for this milestone.

## Decisions

### Adopt

- One read-only inventory of legal active-turn destinations for player and AI.
- A targeted movement query that returns the exact path the service would commit now.
- Structured budget, cost, AP, elevation, traversal, revision, and rejection information.
- Deterministic destination ordering and deterministic path tie behavior.
- Commit occupancy before presentation; animate only the committed result.
- Retain the accepted grid path in the committed Move result and new replay records. The added resolved field is backward compatible because comparison treats older expected payloads as an explicit subset.

### Simplify

- Use the existing `MoveQueryResult`, `Pathfinder`, action service, result, and presenter instead of an ability-template hierarchy or reachable-cache object graph.
- Treat committed occupancy as the reservation. Squad destination reservations remain AI coordination preferences.
- Keep long-range hypothetical route analysis in AI because active-turn validation would answer a different question.

### Reject or defer

- XCOM object history, visualization graphs, interrupt game states, group/scamper movement, destruction traversal, and full rollback.
- New traversal mechanics, animation assets, or a generalized movement manager.

## Implementation target

`TacticalActionService.query_move(actor_id)` will return a deterministic inventory. `query_move(actor_id, destination)` will return that destination's current authoritative path and prediction. Player hover/click and AI active-turn candidate scoring will consume those results. Submission will still rerun the targeted query immediately before commit. `Pathfinder` remains responsible for geometry and cost; `GridManager` remains responsible for occupancy; the presenter remains responsible for motion.
