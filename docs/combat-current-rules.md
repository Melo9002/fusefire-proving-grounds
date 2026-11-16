# Combat today — milestone 04 baseline

Audited at `2bbc7b1`, 2026-11-15. This describes current behavior, not the proposed Combat 2.0 design. [Ranked findings and reproduction](quality/combat-audit-2026-11-15.md).

## From click to damage

Player hover/click, action availability and AI target selection read `BattleController.query_attack()` → `TacticalActionService.query_attack()` → `CombatRules`. Execution revalidates through the action service before committing AP, supply, RNG, damage, reactions and objectives; presentation then animates that result. Replay submits through the same service and checks recorded evidence.

Raw geometric evaluation is distinct from permission to act: CombatRules checks actors, factions, map bounds, carrying, range and visibility; the service additionally checks phase, action availability, AP, supply, Shield restrictions and request revision. A geometric firing lane does not by itself mean an actor can spend an action now.

| Topic | Current rule |
| --- | --- |
| Legal targets | Living hostile actors on existing map cells. A carrying attacker cannot shoot. A legal normal attack also needs its action window, activation, AP and supply, and must obey stance restrictions. |
| Range | Unit-specific maximum; 3D Euclidean distance between grid-derived positions divided by cell size. No distance accuracy falloff. |
| Shot geometry | One grid-derived origin at `standing_height`; five target samples at scaled upper body, head, shoulders and lower body. Tactical obstacle data decides obstruction; animation, camera fading and render-mesh physics do not decide hits. |
| Visibility | Zero clear samples makes the attack illegal. With 1/2/3/4/5 clear samples, obstruction penalties are 50/40/25/10/0 percentage points. The samples approximate a body; their fraction is not a measured visible-mesh percentage. |
| Directional cover | Checks the neighboring cell on the dominant incoming X/Z axis. An exact diagonal checks both axes and takes the strongest label. It does not test that protecting face's actual exposure or use the attacker's elevation to scale cover. |
| Half/full cover | Either label supplies a 50-point accuracy penalty when directional cover applies. A physically taller full-cover obstacle may independently block all samples. Cover and obstruction penalties use the larger penalty, not their sum. |
| Elevation | Changes 3D range and geometry through grid elevation. No explicit height-advantage accuracy modifier exists. |
| Accuracy | `clamp(100 − max(cover penalty, obstruction penalty) + Aim bonus + Shield modifier, 5, 100)` for a legal normal shot. Guard substitutes its −15 reaction modifier for the ordinary Aim bonus. |
| Damage | Normal base damage is 25 on hit, zero on miss. Shield scales damage, rounded with a minimum of 1. No critical or hit-location damage system is present in this action path. Configured hit conditions can have subsequent effects. |
| Randomness | Queries do not roll. An accepted shot draws from the seeded combat RNG; a roll in `[0,100)` hits if strictly below chance. Rejected requests do not consume a roll. |
| Aim | Costs 1 AP; +15 points on the next normal attack. That attack consumes Aim, including a miss. Movement, Reload and relevant stance changes cancel it; it also resets on the next own activation. |
| Guard / Overwatch | Spends all remaining AP, requires at least 1 SP, and reserves one reaction. Movement checks path checkpoints; attacking an armed target can provoke that target's retaliation if it survives. Reaction costs 1 SP and ends Guard even on a miss. It uses weapon range and visibility without a facing cone, with −15 accuracy; it expires at the next own activation. |
| Physical Shield | Current capability costs 1 AP, protects an inclusive 120° facing arc, applies −20 hit chance and ×0.35 damage (25 becomes 9). Attack/Reload are disallowed while active. Movement is allowed; reactions resolve before Move clears the stance. Other stance transitions and the next own activation can clear it. |

The displayed chance is an outcome probability, not a promise of a particular random result. A clear unmodified shot currently reaches 100%; that guarantee follows today's formula. Changing it is a deliberate balance decision.

## Existing feedback and its limits

Direct target hover already shows chance, AP/SP cost, damage on hit, cover label, obstruction and a shot line/blocker marker. Move hover lists route/AP, cover and firing lanes against enemies, plus outgoing shots and post-move AP/SP warnings. It explicitly cancels Aim for outgoing predictions.

The main remaining inconsistencies are in supporting consumers: attack/Guard painted ranges and AI position scoring use single-line LOS helpers rather than the five-sample attack evaluation; destination evaluation retains current Shield state; blocker selection follows traversal order rather than nearest intersection. See the audit for exact reproductions and qualifications.

## Owners

- `systems/combat_rules.gd`: geometry, directional cover, sample visibility, range, chance and predicted cells.
- `systems/actions/runtime/tactical_action_service.gd`: query/commit authority, costs, RNG, damage and reaction ordering.
- `systems/battle_controller.gd`, `ui/action_hud_controller.gd`, `units/ai_controller.gd`: player/UI and AI action consumers.
- `systems/ai/ai_position_scorer.gd`: destination heuristics; `presentation/overlays/tactical_feedback_text.gd`: player-facing query descriptions.
- `units/components/tactical_state.gd`, `units/capabilities/physical_shield.tres`: state lifetime and current Shield parameters.
- `systems/replay/`: reconstruction, requests, result/state verification and compatibility.
