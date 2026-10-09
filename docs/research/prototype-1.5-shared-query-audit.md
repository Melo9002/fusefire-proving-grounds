# Prototype 1.5 shared attack-query audit

**Date:** 2026-10-09  
**Starting checkpoint:** `7869308` (`write down what history remembers`)

## Verified shared behavior

- `TacticalActionService.query_attack()` is already the authoritative read-only gateway used by player hover, player confirmation, and the AI's immediate shot feasibility check.
- `CombatRules.evaluate_attack()` owns carrying, defeated-unit, faction, range, cover, obstruction, aim-point, and hit-chance rules. Final submission calls the same rules again before RNG is consumed or state changes.
- `AttackQueryResult` already carries validation, revision, AP cost, hit chance, cover, obstruction, aim point, and the underlying evaluation. Targetless queries already enumerate legal tactical actor IDs.
- Combat resolution calculates its hit chance from `CombatRules` after final validation. Rejected and preview queries do not consume combat RNG.
- Replay submits the recorded request through `TacticalActionService`; it does not substitute recorded predictions for simulation.

## Verified duplication and mismatches

| Path | Finding | Consequence |
| --- | --- | --- |
| Player action HUD | Attack availability separately checks AP and carrying state. | The button can disagree with turn eligibility, service availability, or whether any legal target exists. |
| Player click | `_on_unit_clicked()` prefilters by hostility before calling the service. | It hides the structured authoritative rejection and repeats one eligibility rule. |
| Legacy controller helpers | `can_attack()` and `evaluate_attack()` expose raw `CombatRules` beside `query_attack()`. | Callers can accidentally bypass AP, activation, revision, and structured rejection rules. |
| AI target discovery | The AI discovers hostiles itself and individually queries each one. | Legal facts are shared, but the targetless service inventory and invalid-candidate reasons are unused. |
| AI rescue-carrier filter | Immediate attacker legality is queried, while the hostile's hypothetical threat uses raw combat evaluation. | The first half is authoritative. The second is intentionally hypothetical because that hostile is not the active actor. |
| AI target scorer | Threat and mission scoring use raw `CombatRules` for hypothetical future attacks. | This is strategic preference/evaluation, not current action legality; forcing it through active-turn validation would be incorrect. |
| Prediction result | Damage, AP before/after, distance, visibility fraction, and blocking-cell data are absent or only reachable through the internal evaluation object. | UI and AI cannot consume a complete, stable, structured prediction contract. |
| Targetless query | Only legal IDs are retained. | Invalid candidates and their structured rejection codes are lost. |
| Attack range overlay | It evaluates cells and line of sight rather than unit targets. | This is a spatial visualization, not target legality. It should remain a combat-rule visualization until a cell-query use case exists. |

## Implementation direction

Extend the existing `AttackQueryResult`; do not add another query service. A targeted query will expose stable prediction fields derived from the same `CombatRules.AttackEvaluation` used by commit. A targetless query will retain a result for every registered candidate, including structured invalid reasons and legal IDs.

The action HUD will use the targetless query for availability and tooltips. Player hover will keep using the targeted query. AI candidate discovery will consume the targetless results and apply its existing strategic scorer only after legality succeeds. Final submission remains revision-checked and revalidates current state.

Raw `CombatRules` remains appropriate for hypothetical threat estimation and cell overlays, where active-turn/AP validation would answer a different question.
