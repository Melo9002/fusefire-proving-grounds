# Aim, Guard and Shield

Milestone 04 step 8, 2026-11-17. These are the current prototype rules, with distinct purposes; this review does not change their numerical balance.

| Action | Useful when | Cost and benefit | Direction / duration |
| --- | --- | --- | --- |
| Aim | You can spend an AP improving a difficult shot now | 1 AP, no SP; +35 accuracy points to one normal Attack. No damage bonus, stacking, added range or ability to shoot through a wall. | No facing restriction. Consumed by Attack even on a miss; canceled by Move, Reload, Skip and other incompatible committed actions. Expires at the next own activation. |
| Guard | You want to reserve a response during opposing actions | Spends all remaining AP, requires 1 SP ready. The one reaction costs 1 SP only when fired, uses -15 accuracy instead of Aim and ordinary hit damage. | No facing cone. Hostile movement checkpoints can trigger it; a direct attack on the watcher can trigger retaliation if the watcher survives. Consumed by one shot even on a miss, or expires unused at the next own activation. |
| Shield | You want to hold a position under frontal fire | Shieldbearer capability; default 1 AP, no SP. Within its inclusive 120° arc: -20 incoming accuracy and ×0.35 hit damage (25 becomes 9). Attack and Reload are blocked while active. | Choose a living hostile to face using actual supported positions. Direction remains fixed; no automatic tracking. Skip preserves it. Move preserves protection during eligible route reactions, then clears it. Aim replaces it; other incompatible committed actions and the next own activation clear it. |

Shield and Guard cannot combine. Entering Guard cancels Aim. Aim can replace Shield by paying its own AP cost. Merely selecting another soldier does not create a new activation or remove these states. Rejected actions consume nothing and do not cancel a stance.

## What the feedback means

- **Guard: movement at (cell)** identifies the actual triggering checkpoint. **Retaliation after being attacked** identifies the other trigger. Both show the final chance and that the one reaction/SP was spent.
- **Did not fire — Blocked / Out of range / Not enough SP** is a reason from the actual reaction check. One latest checked reason per watcher per action is shown; it is not a summary claiming that every checkpoint failed for the same reason. The message says whether a reaction remains reserved.
- A watcher defeated by the incoming attack cannot retaliate; the log explains that and spends no reaction SP.
- Enemy Aim, Reload and unrelated actions do not trigger a reaction. No message is emitted for every non-triggering action; the Guard tooltip states the trigger contract, and unused Guard is reported at expiry.
- **Inside Shield arc / Outside Shield arc** describes actual supported-position geometry. Height is not a vertical Shield cone: the current arc is horizontal. A directly overhead threat with no horizontal bearing cannot establish a facing.
- **Shield stays active** after Skip confirms that spending the remaining AP did not undo the defensive choice. Aim, Shield and unused Guard expiry appear in the bounded recent-combat log.

A clear final 100% shot is guaranteed; Shield and Guard's modifiers can lower that chance. Accuracy does not scale a successful hit. Shield's independent reduction remains the exception to ordinary 25-damage hits. Balance and Shield animation are still provisional.

## Where to tune

Aim/Guard accuracy and normal damage: `systems/combat_cover_tuning.tres`. Shield AP cost, arc, accuracy/damage effects and Attack/Reload permissions: `units/capabilities/physical_shield.tres`. The Shield button reports the capability's AP cost. Change settings before a fresh match; prior recordings with incompatible rules reject clearly.

## Quick test

1. Start Tactical Test Range with a Shieldbearer. Enter Shield, face an enemy, then Skip. Shield should remain for the enemy turn; front shots show protection and rear shots do not. At the next own activation it expires.
2. Aim at a difficult legal shot. The next Attack gains +35 points, consumes Aim even if it misses, and keeps the normal hit damage. A Move first should cancel Aim.
3. Guard with at least one AP and one SP. A blocked/out-of-range enemy move should keep the reservation and explain why no shot happened. A legal move should spend one reaction/SP, including on a miss.
4. Attack a surviving watcher to trigger retaliation. Defeat that watcher instead and it must not fire back. Waiting without a qualifying opportunity should produce an unused-expiry message.

[Verification and implementation limits](quality/combat-defensive-actions-2026-11-17.md). Next is milestone 04 step 9: chance colors and presentation refinement.
