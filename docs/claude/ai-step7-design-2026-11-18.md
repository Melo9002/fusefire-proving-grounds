# AI step 7 design: named movement profiles — 2026-11-18

Roadmap text: *Build editable defensive, aggressive, flanking, escort, carrier and support presets from the current movement weights and constraints. Keep commander preferences, tactical roles and difficulty distinct. Explain which intent selects a profile.* Finished when: *profiles are easy to adjust and produce distinguishable, useful behavior in controlled examples while obeying the same legality rules.*

## Audit: where movement preferences live today

| Where | What | Kind |
| --- | --- | --- |
| `AIDifficultyPolicy` | Weights for progress, cover, exposure, firing, danger, crowding, separation, safe-advance tolerance, plus lapse and repositioning. | **Quality** of play (Easy / Normal / Hard) |
| `AICommanderPolicy` | Multipliers on the same weights (Cautious, Aggressive) plus a safe-advance delta, composed into one unit policy (`compose`). | **Doctrine** of the whole team |
| `AIPositionScorer.evaluate` | Hard-coded role adjustments: on an *objective route* firing is dropped, exposure x1.5, cover x1.25, progress per route cell 8 instead of 4; a *carrier* gets exposure x2.5, danger x2.0, cover x1.5. | **Situation / role**, buried in code |
| `AIController` | Escort movement, route clearing and carrier moves choose their own goals and call the scorer with a goal cell and the objective flag. | Role behaviour, partly in the controller |

So the three things the roadmap wants kept distinct exist, but the third (situation and role) is two hard-coded blocks in the scorer, not editable, not named, not explained.

## Design

**A profile is a layer of multipliers on the position score**, authored as a `Resource` (`AIMovementProfile`) so it can be edited in the Inspector like an archetype:

- `profile_id`, `display_name`, `description`
- multipliers: `progress`, `cover`, `exposure`, `firing`, `danger`, `crowding` (1.0 = unchanged)
- new terms, zero by default: `flank_weight` (reward a position that spreads fire onto a target from a new bearing and lessens the target's cover) and `ally_cohesion_weight` (reward staying near allies)

**Layers combine by multiplication**, so the existing blocks become profiles with identical numbers and still compose: the *objective route* profile (progress x2, firing x0, exposure x1.5, cover x1.25) and the *carrier* profile (exposure x2.5, danger x2.0, cover x1.5) apply together exactly as today.

**Three levels stay separate and visible**, in this order: difficulty weights (how well), then commander multipliers (team doctrine, `compose`), then the situational profile layers chosen per unit and per decision (what it is doing now). A decision's trace names all three.

**A selector, `AIMovementProfileSelector`, picks the layers and says why.** Rules, each with an explicit reason string:

| Profile | Selected when |
| --- | --- |
| carrier | the unit is carrying someone |
| objective route | the mission intent is a route (reach, extract, rescue, terminal) |
| escort | the unit is guarding a carrier or VIP |
| defensive | badly wounded, out of ammo, or outnumbered by hostiles that can reach it |
| aggressive | healthy, with a wounded target in reach, or clearly outnumbering the nearby hostiles |
| flanking | an ally already holds the focus target from another bearing and this unit is free to spread |
| support | the unit's squad has a wounded or exposed ally it can cover (archetype `support` prefers it) |
| default | none of the above |

Precedence is fixed and explained (carrier and route first, since those are mission constraints; then escort; then the tactical ones). The profile never touches legality: the same candidate cells, the same exposure check, the same squad vetoes.

## Slices

| Slice | Work | Proof |
| --- | --- | --- |
| **A** | `AIMovementProfile` resource, the default / objective / carrier profiles with today's numbers, the scorer reads layers instead of the hard-coded blocks, the selector and the trace say which layers applied. | **Behaviour identical**: 48 matches identical to a reference run on `main`, text excepted. |
| **B** | Defensive, aggressive, escort, flanking, support presets and their selection rules; the two new terms. | Controlled scenarios in which each profile picks a distinguishable, legal tile; the same unit with a different profile moves differently; legality unchanged; baseline measured, not assumed. |
| **C** | F3 / decision trace shows the profile and why; documentation; the editing guide for presets. | Trace test, docs. |

## What this does not do

- It does not retune difficulty or commander values (step 10) or squad commitments (step 8).
- It does not teach the AI to use unit mobility or Shield beyond what step 6 did; a "mobility" profile for Skirmisher-style units is a later preset, once the layering exists.
