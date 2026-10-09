# Shared attack queries

Player controls and AI ask `TacticalActionService` the same tactical questions. Presentation decides how to display the answer; AI policy decides how to rank legal answers. Neither owns legality.

This follows the useful boundary verified in the local XCOM 2 SDK: `XComGameState_Ability.UpdateAbilityAvailability`, `CanActivateAbility`, and `GatherAbilityTargets` supply rules-owned choices; `XGAIBehavior.CollectPotentialAbilities`/`ScorePotentialAbility` rank those choices; `UITacticalHUD_AbilityContainer` and AI ultimately submit through the same ability activation machinery. FuseFire keeps that boundary without importing XCOM's template registry or behavior-tree vocabulary.

## Ownership

| Change | Edit here |
| --- | --- |
| Carrying, defeat, faction, range, cover, obstruction, aim point, or hit chance | `systems/combat_rules.gd` |
| Activation, AP, revision, service-busy, and final submission rules | `systems/actions/runtime/tactical_action_service.gd` |
| Prediction fields returned to consumers | `systems/actions/runtime/attack_query_result.gd` |
| Hover text and trajectory presentation | `systems/battle_controller.gd` (`_update_attack_preview`) |
| Attack-button availability and tooltip formatting | `ui/action_hud_controller.gd` |
| Strategic preference among legal targets | `units/ai_controller.gd` and `systems/ai/ai_target_scorer.gd` |

## Targeted prediction

Call `BattleController.query_attack(actor, target)` from battle-facing code, or `TacticalActionService.query_attack(actor_id, target_id)` when stable identities are already available. The result contains:

- structured validation code and message;
- the tactical state revision;
- AP cost and predicted AP before/after;
- hit chance, damage on hit, damage bounds, and expected damage;
- distance, cover, obstruction, visible fraction, aim point, and blocking cell.

These values are observations. They never consume RNG or authorize a later attack. Build the request immediately before submission with `make_attack_request()`; `submit_attack()` checks its revision and all current rules again.

## Candidate inventory

Call `query_attack(actor)` without a target to receive `legal_target_ids` plus `candidate_results`. Each registered actor except the attacker has its own `AttackQueryResult`, including rejected candidates. UI can decide whether an Attack button is useful, while AI can separate legal facts from target preference without reproducing faction, range, or trajectory rules.

The AI's hypothetical threat estimates intentionally call `CombatRules` directly. Those questions ask what another unit could threaten from a position, regardless of whose activation it currently is; applying active-turn/AP validation would answer the wrong question.

## Safety contract

Queries do not spend AP, damage units, move actors, advance objectives or revisions, consume combat RNG, emit presentation, or commit replay records. Identical queries against the same tactical revision return equivalent results. A successful preview can still become stale and be rejected at submission.
