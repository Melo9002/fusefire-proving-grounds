# Milestone 06 movement architecture

This describes integrated main at `6d125eebd0c16062a4d2ea49e2b4348e48c23a9a`. [Audit findings and verification](movement-06-step01-audit.md).

## A. Authority and consumers

Solid arrows show calls, production events or built data. Dotted arrows show dependency or read access. The navigation graph owns connectivity. The action service owns the transaction. The presenter owns visual playback.

```mermaid
flowchart LR
  Auth["Authored scene and asset shapes"] --> Compiler["AuthoredSceneMapCompiler"]
  Compiler --> Map["MapData: support, solids, canonical points and traversal links"]
  Map --> Graph["MapGraphBuilder / Pathfinder"]
  Player["MouseRaycaster / BattleController"] --> Service["TacticalActionService"]
  AI["AIController"] --> Service
  AI -.-> Graph
  Service --> Rules["BattleController move query / GridManager"]
  Rules --> Graph
  Service --> Receipt["MoveActionResult and state revision"]
  Receipt --> Presenter["TacticalActionPresenter"]
  Presenter --> Adapter["TacticalCharacterAdapter / CharacterPresenter"]
  Receipt --> Recorder["BattleReplayRecorder"]
  Replay["BattleReplayPlayer"] --> Service
  Map -.-> F3["DebugTools F3 walkability"]
  Map -.-> Combat["CombatRules: LOS, cover and Guard"]
```

Sources: [compiler](../../systems/generation2/authored_scene_map_compiler.gd), [map](../../systems/grid/map_data.gd), [graph](../../systems/grid/map_graph_builder.gd), [AI controller](../../units/ai_controller.gd), [action service](../../systems/actions/runtime/tactical_action_service.gd), [combat rules](../../systems/combat_rules.gd), [F3](../../ui/debug_tools.gd).

## B. Player and AI request lifecycle

The map overlay answers whether a cell has map geometry permitting traversal. A selected actor’s highlighted movement range adds its current budget, occupancy and stopping rules. The targeted query returns the path and feedback data. A click can re-query even after a successful hover. The AI has additional read-only route searches for planning, including hypothetical yielding. A returned route grants no authority to enter occupied cells. Plans are invalidated on relevant changes during cooperative planning.

```mermaid
flowchart TD
  Ray["MouseRaycaster floor hit and viewed floor"] --> Mode["BattleController move mode"]
  Mode --> Inventory["query_move without a destination"]
  Inventory --> Range["Budgeted reach filtered by actor occupancy and stopping"]
  Range --> Hover["Hover / click restricted to highlighted cells"]
  AI["AIController scored candidates"] --> Inventory
  AI --> Hypo["Occupied route searches and SquadContext"]
  Hover --> Query["query_move for exact destination"]
  AI --> Query
  Query --> Legal{"Legal and within movement budget?"}
  Legal -->|Yes| Preview["Route, AP, canonical ghost or AI candidate"]
  Legal -->|No| Return["Typed validation; current hover clears feedback"]
  Preview --> Request["Request with actor, source, destination and expected revision"]
  Request --> Submit["submit_move validates and re-queries"]
```

Sources: [MouseRaycaster](../../systems/grid/mouse_raycaster.gd), [BattleController](../../systems/battle_controller.gd#L331) (`_query_move_data`, `_update_movement_preview`, `_on_floor_clicked`, `try_move`), [move DTO](../../systems/actions/runtime/move_query_result.gd), [planning snapshot](../../systems/ai/ai_planning_snapshot.gd), [squad context](../../systems/ai/squad_context.gd).

## C. Placement, route and combat geometry

A tile has a logical identity, a support center and, when legal, a canonical standing point. Shape authority, line-of-sight indexing and floor support are distinct data sets. A supported destination can be unreachable from a given start. A raised transit cell can contribute to a route while refusing a stop.

```mermaid
flowchart TD
  Inputs["Authored solids / semantic shape rules / floor and elevation markers"] --> Index["Movement and LOS indexes; support columns"]
  Index --> Fit["SurfacePlacement ranks obstacle-clear points inside one cell"]
  Fit --> Check["SurfaceNavigation rounds each contender and requires support and stationary clearance"]
  Check -->|Candidate rejected in compiler 11| Fit
  Check --> Points["Canonical point / rejected stop / raised vault transit"]
  Points --> Graph["MapGraphBuilder validates static swept edges"]
  Index --> Graph
  Graph --> PF["Pathfinder budgets diagonal and weighted steps"]
  Bodies["GridManager live occupancy and neighbor body checks"] --> PF
  PF --> Scope["Action query: targeted route and movement budget"]
  Index --> LOS["CombatRules: shot intersections and cover contact"]
  Points --> LOS
  Scope --> Refine["Presentation-only route expansion and refinement"]
```

Sources: [shape rules](../../systems/generation2/tactical_shape_rules.gd), [asset placement guide](../asset-edge-placement.md), [SurfacePlacement](../../systems/grid/surface_placement.gd), [SurfaceNavigation](../../systems/grid/surface_navigation.gd), [Pathfinder](../../systems/grid/pathfinder.gd), [GridManager](../../systems/grid/grid_manager.gd), [tactical route builder](../../presentation/tactical/tactical_route_builder.gd).

[Step 06.02 documents the supported search and the historical compiler boundary](movement-06-step02-support-placement.md).

## D. Action window, Guard and presentation

The authoritative Move can visit several logical checkpoints in one transaction. Guard and applicable environmental effects run on those checkpoints. A lethal reaction removes the defeated carrier from its registered origin. Move then settles passenger release from the lethal checkpoint before publishing its receipt. The presenter animates the shortened route and reveals the passenger at the lethal impact. [Step 06.10A explains the ordering and historical replay compatibility](movement-06-step10a-passenger-release.md).

```mermaid
sequenceDiagram
  participant H as Player / AI / Replay
  participant S as TacticalActionService
  participant W as GridManager / objectives / Guard
  participant R as Replay recorder
  participant P as TacticalActionPresenter / character
  H->>S: Submit expected-revision Move
  S->>S: Validate, re-query and acquire busy window
  S->>W: Spend AP, resolve checkpoint hazards and Guard
  opt Lethal Guard
    W-->>W: Defeat removes carrier from registered origin
    S->>S: Truncate committed route to lethal checkpoint
    S->>W: Release passenger at checkpoint or legal fallback
  end
  S->>W: Final occupancy, pose-state cleanup and objective update
  S-->>R: Commit typed receipt and revision
  S->>P: Present committed movement unless suppressed
  opt Lethal Guard with passenger
    P->>P: At impact, remove carry visual and reveal placed passenger
  end
  P-->>S: Settlement / cancellation
  S-->>H: Release action window and return result
```

Sources: [submit and reactions](../../systems/actions/runtime/tactical_action_service.gd#L605), [defeat callback](../../systems/battle_controller.gd#L1046), [objective release](../../systems/objectives/objective_manager.gd#L289), [presentation](../../presentation/tactical/tactical_action_presenter.gd), [replay](../../systems/replay/battle_replay_player.gd), [fingerprint](../../systems/replay/battle_state_fingerprint.gd).
