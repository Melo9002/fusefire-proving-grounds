# FuseFire tactical AI

This documentation describes the tactical AI currently implemented on `main`, including the Default, Cautious, and Aggressive commander doctrines. The AI is deterministic for a fixed battle configuration, commander assignment, action history, and AI decision seed, apart from its deliberately seeded Easy and Normal difficulty lapses.

The short answer to “why does it sometimes look smart?” is that simple unit policies operate over rich authoritative queries and share a small amount of squad memory. A unit does not plan the whole faction turn. It follows an ordered action policy, scores legal targets and movement destinations, and records destinations, intended targets, objective handlers, and protected evacuation corridors for units acting later that round. Combat geometry, directional cover, elevation-aware distance, line of sight, objectives, AP, SP, and reactions are resolved by the same services used by the player. Several independent choices can therefore line up into what looks like an ambush or coordinated push.

The AI is not a general planner, behavior tree, minimax search, or learned model. It does not forecast a complete enemy turn. Its main policy is an ordered ladder in `AIController._run_activation()`; utility scoring is used within movement and target choices, not across every possible action.

## Documents

- [Architecture and behavior](architecture-and-behavior.md) traces activation, candidate generation, mission behavior, Guard, and emergent coordination.
- [Scoring reference](scoring-reference.md) lists formulas, weights, thresholds, hard filters, ordering, and representative decisions.
- [Information access and fairness](information-access-and-fairness.md) identifies exactly what the AI reads and where it has computational advantages.
- [Tuning and maintainability](tuning-and-maintainability.md) maps the strongest tuning controls, diagnostics, confirmed issues, risks, and open questions.
- [Commander architecture](commander-architecture.md) defines the behavior-preserving policy foundation and the proposed strategic layer.

## Principal implementation

| Responsibility | Source |
| --- | --- |
| Per-unit activation policy and movement/target selection | `units/ai_controller.gd` |
| Position scoring | `systems/ai/ai_position_scorer.gd` |
| Target scoring | `systems/ai/ai_target_scorer.gd` |
| Difficulty weights and bounded lapses | `systems/ai/ai_difficulty_policy.gd` |
| Round-scoped coordination memory | `systems/ai/squad_context.gd` |
| Mission intent selection | `systems/objectives/objective_manager.gd:get_mission_intent` |
| Authoritative action queries and commits | `systems/actions/runtime/tactical_action_service.gd` |
| Phase, activation, AP refresh, and progression | `systems/turn_manager.gd` |
| AI wiring, shared queries, decision records | `systems/battle_controller.gd` |
| In-game scoring diagnostics | `ui/debug_tools.gd`, `presentation/overlays/ai_scoring_overlay.gd` |

## Verified scope

This audit checked the current source and the focused AI tests. It also ran the position, target, difficulty, ability, mission-intent, scoring-overlay, objective-navigation, intentional-mistake, second-advance, determinism, and stalemate-recovery suites. The checks confirm code paths and deterministic fixtures; they do not establish that every weight is well balanced on every future Goal 2 battlefield.

