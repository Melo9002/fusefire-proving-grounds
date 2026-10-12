# Tactical Tempo validation and freeze

**Status:** Implemented, validated, and frozen by Task 01.13.6.

This reference records the stable Tactical Tempo contract established by Tasks 01.13.1–01.13.6. A freeze means later systems may consume these rules, while changing them requires a concrete gameplay or correctness reason and focused regression coverage.

## Authoritative state

`UnitStats` is the only AP authority. It owns:

| Fact | Meaning |
| --- | --- |
| Base AP | Inspector-authored normal action budget. Current MIRA archetypes use 3; the reusable scene fallback is 2. |
| Effective maximum AP | `max(0, base_ap + sum(active modifiers))`. |
| Activation capacity AP | The ceiling captured at refresh and allowed to ratchet downward during that activation. |
| Spent AP | AP already committed during the activation. |
| Current AP | `max(0, activation_capacity_ap - spent_ap)`. |

Fixed-cost actions call `consume_ap()`. Guard and Wait call `spend_all_remaining_ap()`. Rejected and stale actions change none of these fields. Movement range remains the independent `UnitStats.speed` budget; changing AP does not change route cost, diagonal rules, elevation, or reachable distance per Move.

## Refresh and modifier invariants

- Each living faction roster refreshes once when its phase begins.
- Refresh copies effective maximum into activation capacity and clears expenditure.
- A reduced effective maximum ratchets activation capacity down immediately.
- Removing a penalty or adding a positive modifier never raises capacity during the current activation.
- Restored or increased capacity becomes available at the next legitimate phase refresh.
- Stable modifier source IDs replace their own value instead of stacking duplicates; canonical snapshots sort them by source ID.
- Effective maximum and current AP may reach zero. Explicit eligibility checks skip actors with no ordinary or legal free objective action, so automated phases continue.
- Terminal, Rescue, and Extraction retain their narrow authoritative zero-AP continuation rules.

The shared tactical beat remains the end-of-round boundary after the enemy phase. Conditions tick and casualties resolve before the next round and player refresh. System Overload is a controlled test fixture that proves a condition-owned `-1` AP modifier, idempotent cleanup, non-stacking refresh, and no same-activation refund. It is not present in ordinary missions. Jammed still disables Aim without modifying AP; Leaking and Bleeding still deal periodic HP damage.

## Integrated behavior

- Player, AI, replay, and headless callers submit the same typed action requests through `TacticalActionService`.
- Action availability comes from authoritative queries. UI labels observe `ap_changed(current, effective_maximum)` and never mutate AP.
- Guard spends the watcher's remaining AP only when registered. Nested movement or return-fire reactions consume SP and remain inside their parent action transaction.
- Defeat clears owned tactical state and condition modifiers. A beat casualty cannot refresh or hold selection.
- Tactical Tempo replay fingerprints are feature-gated. New recordings include Base AP, effective maximum, activation capacity, expenditure, current AP, and sorted modifier evidence. Recordings without the gate retain their historical fingerprint shape.

## Frozen validation matrix

The freeze gate covers:

- 2, 3, and 4 Base AP initialization, sequential spending, overspend rejection, and refresh;
- effective maximum zero, overlapping sources, duplicate replacement, expiration, removal, and capacity below expenditure;
- movement and diagonal-cost independence;
- fixed-cost actions, Guard/Wait spend-all, zero-cost objectives, reaction nesting, condition cleanup, defeat, and beat ordering;
- zero-capacity player, allied, enemy, and automated-player progression;
- AI legality, HUD/portrait/world-label agreement, current replay playback, historical feature gates, and hidden tempo-state divergence detection;
- the deterministic Prototype 1 mission matrix, including the permanent stalemate fixtures.

Primary focused fixtures are `tests/ap_capacity_modifiers_test.gd`, `tests/ap_tactical_beat_lifecycle_test.gd`, `tests/condition_ap_tempo_integration_test.gd`, `tests/tactical_tempo_replay_hud_test.gd`, `tests/overwatch_reactions_test.gd`, `tests/diagonal_movement_test.gd`, and `tests/ai_abilities_integration_test.gd`.

## Deliberately deferred

- playable humans and final human balance;
- explicit current-AP grants, bonus-action pools, AP banking, and initiative;
- equipment, enhancement, injury, and movement-range modifier systems;
- gameplay deployment of System Overload;
- a universal attribute or modifier framework;
- broader Tactical Tempo UI explanations.

These are future features rather than gaps in the frozen authority model.
