# Source-editable architecture diagrams

[Architecture index](README.md) · [Code inventory](implementation.md#source-inventory) · [Walkthroughs](walkthroughs.md) · [Performance](performance.md)

Solid arrows in diagram B are calls or deliveries, and dotted arrows are shared reads or results. Diagrams A and C compress control flow. Diagram E tracks execution time. Source links beside each diagram identify the functions represented.

## A · Complete decision lifecycle

```mermaid
flowchart TB
    active["TurnManager selects active actor"] --> gate{"AI owns this live activation?"}
    gate -- no --> stop["Return to the current turn owner"]
    gate -- yes --> window["Pacing timer and wait for action window"]
    window --> board["Read live roster, board and objectives"]
    board --> policy["Mission intent, composed policy and role"]
    policy --> proposals["Rules and authoritative candidate queries"]
    proposals --> evaluate["Filter, score and compare short sequences"]
    evaluate --> choose["Choose one step or Wait"]
    choose --> authority{"Tactical action service accepts?"}
    authority -- yes --> commit["Commit result then await presentation"]
    authority -- no --> rejected["Attempt yields no commit; caller falls through or ends"]
    commit --> live{"Actor, battle and next action still eligible?"}
    rejected --> live
    live -- yes --> board
    live -- no --> handoff["Stop or advance the queue"]
    handoff --> active
    evaluate -. "yield resumed on stale board" .-> rejected
    window -. "actor lost or scene ended" .-> stop
```

Source: [AIController](../../units/ai_controller.gd) `_on_active_unit_changed`, `_await_action_window`, `_plan_activation`, `_execute_turn`; [TurnManager](../../systems/turn_manager.gd) `_set_active_unit`; [TacticalActionService](../../systems/actions/runtime/tactical_action_service.gd) `_validate_request`. Redirection after a stale search is caller-specific. It can abandon one branch and continue local fallbacks.

## B · Actual code architecture

```mermaid
flowchart TB
    admit["BattleLevel wires AIController<br/>TurnManager signals active_unit_changed"]
    ai["AIController"]
    inputs["ObjectiveManager<br/>Pathfinder"]
    policy["AICommanderPolicy · AIDifficultyPolicy<br/>AIMovementProfiles · AIMovementContext"]
    evaluators["AITargetScorer · AIPositionScorer<br/>AIPlanEvaluator"]
    grid["GridManager · MapData<br/>CombatRules for forecasts"]
    battle["BattleController"]
    squad["SquadContext per team"]
    service["TacticalActionService"]
    f3["DebugTools"]
    replay["BattleReplayRecorder"]
    playback["BattleReplayPlayer"]
    admit --> ai
    ai -->|"intent, routes"| inputs
    ai --> policy
    ai --> evaluators
    inputs -. "planning reads" .-> grid
    evaluators -. "geometry reads" .-> grid
    ai -->|"queries and submissions"| battle
    ai -->|"reserve"| squad
    battle -->|"owns and refreshes"| squad
    battle --> service
    service -->|"mission callbacks"| inputs
    battle -->|"decision and result signals"| f3
    service -->|"committed results"| replay
    playback -->|"recorded requests"| service
```

Source: [BattleLevel](../../levels/prototype_map/battle_level.gd) controller setup; [BattleController](../../systems/battle_controller.gd) query/try adapters, `get_squad_context`, `_commit_mission_action`, `record_ai_decision`; [AIController](../../units/ai_controller.gd) `_ensure_policy`, `_find_attack_target`, `_move_along_goal_path`; [BattleReplayRecorder](../../systems/replay/battle_replay_recorder.gd) `begin`; [BattleReplayPlayer](../../systems/replay/battle_replay_player.gd) `_execute`. The [inventory](implementation.md#source-inventory) maps each module to its concrete path. The grouped mission callback targets ObjectiveManager through BattleController. The route read targets Pathfinder, which reads the grid. Scorers call CombatRules for forecasts and consult squad preferences. The recorder additionally receives turn and mission commands.

## C · Action selection and precedence

```mermaid
flowchart TB
    enter["Window free; VIP uses follow/wait branch"] --> free["Free Extract or zero-AP mission opportunity"]
    free --> refresh["Post-action refresh while actor can act"]
    refresh --> urgent["Emergency Seal; clear carrier lane; escort threat shot"]
    urgent -->|none committed| mission["Mission branch: Rescue, Terminal, Protect, Survive, Reach or Extract"]
    mission -->|none committed| carry{"Carrying a casualty?"}
    carry -- yes --> wait["Wait and end this activation"]
    carry -- no --> shot{"Legal target after target scoring?"}
    shot -- yes --> movefire["If eligible, compare Move then Attack with immediate shots"]
    movefire -->|no move| final["Compare final-AP Shield where supported"]
    final -->|no Shield| aim["Compare Aim versus immediate affordable shots"]
    aim -->|no Aim| attack["Submit Attack"]
    shot -- no --> reload["Reload only if useful and legal"]
    attack -->|no successful Attack| reload
    reload -->|no Reload| goal{"Reach or Extract? Escort duty?"}
    goal -->|"Reach or Extract"| wait
    goal -->|"friendly carrier"| escort["Rejoin or find off-corridor support cell"]
    goal -->|"ordinary combat"| approach["Interception or closest hostile approach; safe second advance"]
    escort -->|no useful move| wait
    approach -->|no move| defend["Try worthwhile Shield; then plausible Guard"]
    defend -->|no action| wait
    urgent -->|"commit"| refresh
    mission -->|"commit and actor remains"| refresh
    mission -->|"extracted"| done["Stop; turn owner handles successor"]
    movefire -->|"move committed"| refresh
    final -->|"Shield committed"| refresh
    aim -->|"Aim committed"| refresh
    attack -->|"commit"| refresh
    reload -->|"commit"| refresh
    escort -->|"commit"| refresh
    approach -->|"commit"| refresh
    defend -->|"Shield"| refresh
    defend -->|"Guard"| done
    wait --> done
```

Source: [AIController](../../units/ai_controller.gd) `_plan_activation`, `_try_mission_step`, `_best_reposition_plan`, `_shield_instead_of_final_shot`, `_try_guard_if_useful`; [AIPlanEvaluator](../../systems/ai/ai_plan_evaluator.gd) `compare_aim`, `shots_with`, `best_attack_from` and `best_shield_plan`. A free action can finish directly. The ordering here is a sequence of rules, with local utilities inside target, move, Aim and Shield comparisons.

## D · Squad coordination

```mermaid
flowchart TB
    get["BattleController.get_squad_context"] --> context["Team-local SquadContext"]
    actor["Active unit's individual planner"] --> get
    context --> dest["Committed destination: hard veto for another actor’s claimed cell; nearby crowding penalty"]
    context --> focus["Target claims: preference to spread; likely finishing weakens penalty"]
    context --> owner["Objective handlers: know teammates already assigned"]
    context --> corridor["Carrier corridor with owner and ordered lane cells"]
    corridor --> live{"Carrier route viable under current occupancy?"}
    live -- yes --> progress["Carrier proposes a legal move along the route"]
    live -- no --> hint["Friendly-yield lane is a coordination hint"]
    hint --> yield["Blocker seeks legal side tile, else farther forward in the bottleneck"]
    yield --> authority["Action service validates committed moves"]
    progress --> authority
    authority --> reroute["Next lookup trims, revalidates or recalculates lane"]
    reroute --> context
    expiry["Round change, next owner activation, displacement, defeat, extraction, objective end"] -->|"prune or release as applicable"| context
```

Source: [SquadContext](../../systems/ai/squad_context.gd) `begin_round`, `begin_unit`, `block_reason`, `target_adjustment`, `revalidate`, `_revalidate_corridor`; [AIController](../../units/ai_controller.gd) `_carrier_route`, `_clear_carrier_route`, `_move_to_escort_position`; [Pathfinder](../../systems/grid/pathfinder.gd) `calculate_friendly_yield_path`. An off-lane escort can attack threats and rejoin. An impossible lane can remain blocked.

## E · Frame timing and ownership

Red boxes are synchronous work on the main thread. They can extend a frame. Yellow boxes await another frame, a pacing timer, or presentation settlement.

```mermaid
flowchart TB
    selection["Turn signal; early intent, squad refresh and claim"]:::sync
    selection --> pacing["Activation timer 0.6 s of scene time"]:::awaiting
    pacing --> busy{"Active, live, unpaused and service free?"}
    busy -->|"temporarily busy or paused"| frames["Wait process_frame"]:::awaiting
    frames --> busy
    busy -->|"no longer controlled"| cancel["Discard continuation"]
    busy -->|"yes"| inventory["Intent refresh, carrier route, legal inventory and goal field"]:::sync
    inventory --> candidates["One candidate or an internal path/LOS call"]:::sync
    candidates -->|"more candidates and time threshold hit"| yield["Yield process_frame"]:::awaiting
    yield --> stale{"Actor/lifetime valid and revision+occupancy unchanged?"}
    stale -->|yes| candidates
    stale -->|no| cancelplan["Return from this planning branch"]
    candidates -->|"finish scoring"| submit["Choice and publication where pre-submit; final validation"]:::sync
    submit --> commit["Commit, emitted receipt and observers"]:::sync
    commit --> presentation["Service still busy while action presentation awaits"]:::awaiting
    commit -->|"extraction can select successor here"| selection
    presentation --> resume["Release service; finish explanation where post-submit"]
    resume -->|"still eligible"| inventory
    resume -->|"spent AP, ended or removed"| next["Handoff or teardown"]
    next -->|"another actor"| selection
    classDef sync fill:#fee2e2,color:#451a1a,stroke:#b91c1c
    classDef awaiting fill:#fef3c7,color:#422006,stroke:#a16207
```

Source: [AIController](../../units/ai_controller.gd) `_await_action_window`, `_move_along_goal_path`, `_best_reposition_plan`, `_wait_for_objective_update`; [AIPlanningSnapshot](../../systems/ai/ai_planning_snapshot.gd) `capture` and `is_stale`; [TacticalActionService](../../systems/actions/runtime/tactical_action_service.gd) `_set_busy`, `_publish_commit`, `submit_move`, `submit_mission`. Successful attacks can add a 0.25 s pacing timer after presentation. The 5 ms check runs between candidates in the two sliced loops. It cannot interrupt one synchronous path call.

## F · Authority, RNG and replay

```mermaid
flowchart TB
    ai["AI: read/forecast/choose"] --> request["Typed request<br/>expected revision"]
    seed["Battle setup AI seed + actor name"] --> lapses["Separate RNG<br/>eligible near-best choices"]
    lapses --> ai
    replay["BattleReplayPlayer<br/>reconstruct saved action"] --> request
    request --> validate{"Service validates<br/>actor, window, revision and action"}
    validate -- reject --> no["Rejected result; no combat roll or committed mutation"]
    validate -- allow --> apply["Authoritative commit AP/SP, occupancy, stats and objectives"]
    combat["Service's seeded combat RNG"] -->|"Attack and valid reactions"| apply
    apply --> receipt["Commit, transaction and revision"]
    receipt --> recorder["Recorder saves action and fingerprint"]
    receipt --> verify["Replay verifies expected result and state"]
    recorder -. "saved action stream" .-> replay
```

Source: [AIController](../../units/ai_controller.gd) `_ready` and the two lapse call sites; [AIDifficultyPolicy](../../systems/ai/ai_difficulty_policy.gd) `choose_near_best_index`; [TacticalActionService](../../systems/actions/runtime/tactical_action_service.gd) `_validate_request`, `submit_attack`, `_resolve_overwatch_reactions`; [BattleReplayRecorder](../../systems/replay/battle_replay_recorder.gd) `_on_tactical_action_committed`; [BattleReplayPlayer](../../systems/replay/battle_replay_player.gd) `begin`, `_execute`, `_request_from_record`. A selection lapse may already have drawn AI randomness before a request rejects. Rejection itself does not draw combat randomness.

## G · Profiling and historical diagnostics

```mermaid
flowchart TB
    scores["Controller assembles choice, scores, context and reasons"] --> record["BattleController stamps ID, revision, faction, policy and squad copy"]
    record -->|"selection can precede commit"| pending["Pending decision link by actor and action"]
    commit["Authoritative commit and validation receipt"] --> pending
    commit -->|"some explanations follow presentation"| last["Most recent unmatched commit"]
    last --> record
    record --> f3["DebugTools retained timeline"]
    pending --> f3
    f3 --> open["Select history: stored scores, receipt and squad snapshot"]
    f3 --> overlay["Separate live tactical overlays"]
    profile["Optional profile-ai clocks"] --> sample["AIActivationProfile: slices, waits, stages and action windows"]
    commit --> sample
    sample --> log["Log and simulator analysis"]
    record --> sim["AIMatchSimulator collects decisions and outcome links"]
    pending --> sim
```

Source: [AIController](../../units/ai_controller.gd) `_record_ai_decision` and `_publish_movement_preview`; [BattleController](../../systems/battle_controller.gd) `record_ai_decision`, `_on_action_committed`, `_report_ai_rejection`; [DebugTools](../../ui/debug_tools.gd) `_on_ai_decision_recorded`, `_on_ai_action_outcome`, `_format_decision_detail`; [AIActivationProfile](../../systems/ai/ai_activation_profile.gd) `suspend`, `resume`, `begin_action`, `end_action` and `finish`. UI history retains up to 80 entries. Alternative labels can include branch context as text. A historical list is not an exhaustive action inventory, and terminal combat can outlive its decision explanation.
