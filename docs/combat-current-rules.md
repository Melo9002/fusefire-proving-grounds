# Combat today — milestone 04 baseline

Baseline audited at `2bbc7b1`, 2026-11-15; prediction/feedback corrections followed on 2026-11-16 as noted below. Geometry/LOS corrections followed in milestone step 4; step 5 adds physical directional cover and distinct 20/40-point penalties. Other accuracy modifiers and damage are unchanged. This describes current behavior; the remaining range/height accuracy and Aim changes in the [intended Combat 2.0 rules](combat-2-rules.md) are still pending. [Original ranked findings and reproduction](quality/combat-audit-2026-11-15.md).

## From click to damage

Player hover/click, action availability and AI target selection read `BattleController.query_attack()` → `TacticalActionService.query_attack()` → `CombatRules`. Execution revalidates through the action service before committing AP, supply, RNG, damage, reactions and objectives; presentation then animates that result. Replay submits through the same service and checks recorded evidence.

Raw geometric evaluation is distinct from permission to act: CombatRules checks actors, factions, map bounds, carrying, range and visibility; the service additionally checks phase, action availability, AP, supply, Shield restrictions and request revision. A geometric firing lane does not by itself mean an actor can spend an action now.

| Topic | Current rule |
| --- | --- |
| Legal targets | Living hostile actors on existing map cells. A carrying attacker cannot shoot. A legal normal attack also needs its action window, activation, AP and supply, and must obey stance restrictions. |
| Range | Unit-specific maximum; 3D Euclidean distance between actual supported surface positions divided by cell size. No distance accuracy falloff. |
| Shot geometry | One origin at the actual supported surface plus `standing_height`; five target samples at scaled upper body, head, shoulders and lower body. Tactical obstacle data decides obstruction; animation, camera fading and render-mesh physics do not decide hits. |
| Visibility | Zero clear samples makes the attack illegal. With 1/2/3/4/5 clear samples, obstruction penalties are 50/40/25/10/0 percentage points. The samples approximate a body; their fraction is not a measured visible-mesh percentage. |
| Directional cover | Current maps inspect actual nearby cover faces, including parts in the defender's own cell and diagonally nearby parts. Historical non-surface fixtures retain the four-neighbor lookup. The ray from the actual firing origin to the target's lower-body sample must hit a protecting part, using the same corner/compound geometry as LOS. Side/rear attacks, gaps and shooting above the surface remove its bonus. AI and hypothetical previews pass actual body heights. |
| Half/full cover | Physical low/full protection supplies 20/40 points, editable in `systems/combat_cover_tuning.tres`. Precise compound objects use the height of the intersected part (full at 1.2 tile widths above the target surface), not another part's taller envelope. Cover and obstruction use their maximum, not their sum. A full surface can still block every sample, making the shot illegal. |
| Elevation | Changes 3D range and geometry through actual surface height, including fractional offsets. No explicit height-advantage accuracy modifier exists. |
| Accuracy | `clamp(100 − max(cover penalty, obstruction penalty) + Aim bonus + Shield modifier, 5, 100)` for a legal normal shot. Guard substitutes its −15 reaction modifier for the ordinary Aim bonus. |
| Damage | Normal base damage is 25 on hit, zero on miss. Shield scales damage, rounded with a minimum of 1. No critical or hit-location damage system is present in this action path. Configured hit conditions can have subsequent effects. |
| Randomness | Queries do not roll. An accepted shot draws from the seeded combat RNG; a roll in `[0,100)` hits if strictly below chance. Rejected requests do not consume a roll. |
| Aim | Costs 1 AP; +15 points on the next normal attack. That attack consumes Aim, including a miss. Movement, Reload and relevant stance changes cancel it; it also resets on the next own activation. |
| Guard / Overwatch | Spends all remaining AP, requires at least 1 SP, and reserves one reaction. Movement checks path checkpoints; attacking an armed target can provoke that target's retaliation if it survives. Reaction costs 1 SP and ends Guard even on a miss. It uses weapon range and visibility without a facing cone, with −15 accuracy; it expires at the next own activation. |
| Physical Shield | Current capability costs 1 AP, protects an inclusive 120° facing arc, applies −20 hit chance and ×0.35 damage (25 becomes 9). Attack/Reload are disallowed while active. Movement is allowed; reactions resolve before Move clears the stance. Other stance transitions and the next own activation can clear it. |

The displayed chance is an outcome probability, not a promise of a particular random result. A clear unmodified shot currently reaches 100%; that guarantee follows today's formula. Changing it is a deliberate balance decision.

## Existing feedback and its limits

Direct target hover already shows chance, AP/SP cost, damage on hit, cover label, obstruction and a shot line/blocker marker. Move hover lists route/AP, cover and firing lanes against enemies, plus outgoing shots and post-move AP/SP warnings. It explicitly cancels Aim for outgoing predictions.

The three reproduced consumer inconsistencies were corrected on 2026-11-16: attack/Guard painted ranges and AI position scoring now use the shared body-sample visibility; completed-destination evaluation excludes Shield canceled by Move; blocked-shot feedback selects the nearest intersection. Empty range cells represent a hypothetical hostile with the shooter's body height; occupied cells use the actual body's height. This geometric coverage remains separate from AP/faction permission to attack. During-route Guard retains the existing checkpoint Shield semantics. See the [fix verification](quality/combat-consistency-fixes-2026-11-16.md). The dated audit remains the original baseline.

Step 4 also indexes raised precise parts independently of standing cells, without creating walkable surfaces. Blocked feedback uses the selected body-sample ray and highlights its intersected compound part. Existing single-corner grazing and paired-corner sealing are retained. Current compiler revision is 6, with default surface placement described below; incompatible simulation recordings reject before playback. See [geometry/LOS verification](quality/combat-geometry-los-2026-11-16.md).

Step 5 exposes the protecting cell and cover/exposure/combined penalties in the authoritative evaluation. The editable cover resource is shared; replay records its value signature and rejects missing or changed tuning. Current simulation identity is `prototype-1.5-surface-placement-7`. See [cover/flanking verification](quality/combat-cover-flanking-2026-11-16.md).

In [all new current-map compilations](asset-edge-placement.md), one supported standing point replaces the cell center consistently for movement, range, five-sample LOS, Guard and physical adjacency. Nearby cover is selected from actual contacts, including own-cell parts; source/target-cell obstacles remain independently indexed. Body/route clearance and replay evidence are checked. Existing authored ladder, ramp and stair transitions use checked support routes. This does not add tactical peeking, new accuracy/damage balance or arbitrary vertical traversal.

## Owners

- `systems/combat_rules.gd`: geometry, directional cover, sample visibility, range, chance and predicted cells.
- `systems/actions/runtime/tactical_action_service.gd`: query/commit authority, costs, RNG, damage and reaction ordering.
- `systems/battle_controller.gd`, `ui/action_hud_controller.gd`, `units/ai_controller.gd`: player/UI and AI action consumers.
- `systems/ai/ai_position_scorer.gd`: destination heuristics; `presentation/overlays/tactical_feedback_text.gd`: player-facing query descriptions.
- `units/components/tactical_state.gd`, `units/capabilities/physical_shield.tres`: state lifetime and current Shield parameters.
- `systems/replay/`: reconstruction, requests, result/state verification and compatibility.
