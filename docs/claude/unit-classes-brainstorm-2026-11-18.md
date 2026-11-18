# MIRA unit classes: first shielded unit and future ideas — 2026-11-18

Status: **the first Bulwark is implemented** (see "What shipped" at the end); the rest is design notes. Every number is a starting proposal to be tuned against the baseline. Written from a brainstorm with the project owner; the lines marked "owner" are their direction. Units are MIRA robots, so a body-mounted arm or heavy plating is in fiction.

## The idea in one paragraph

A **Bulwark** carries an extra robotic arm with a heavy shield. The arm tracks incoming fire, so the protection is **omnidirectional** (owner). The class pays for that with mobility and reach: it is **slow, short-ranged and committed to its position**. The shield is also **harder to hit** rather than only reducing damage (owner prefers the XCOM-like "make me harder to hit" feel). Its counters are not about facing but about **capacity** and **weapons that ignore a shield**.

## What exists today

- `TacticalArchetype` already carries `max_hp`, `base_ap`, `movement_range`, `attack_range`, `max_supply_points` and an optional `shield_capability`. Zero means "inherit the unit scene's value".
- `units/archetypes/shieldbearer.tres` only adds the shield capability; it is not yet a class.
- `physical_shield.tres`: 1 AP, 120° arc, damage multiplier 0.35, accuracy modifier −20, no attacking or reloading while it is up. The stance lasts until the unit's next activation.
- The AI values the stance as expected prevented damage from the real combat rules, so a change to arc, accuracy or damage multiplier is priced automatically (AI step 6 slice D).
- Not there: per-archetype weapon damage (damage per hit is global), a per-class tint, grenades, weapon types, armor piercing.

## First shielded unit: proposed model

| Property | Baseline | Bulwark (proposal) | Why |
| --- | --- | --- | --- |
| Movement range | scene default | clearly lower (start at about 60% of baseline) | "A heavy shield decreases mobility" (owner). A permanent class cost replaces the earlier "braced next turn" idea. |
| Attack range | scene default | baseline minus 1 to 2 cells | Short-range weapon (owner); it must commit close to fight. |
| HP | baseline | baseline or slightly higher | Durability comes from the shield, not from a big HP pool. |
| AP | 3 | 3 | Shield stance costs 1 AP, so it still has two for other actions. |
| Shield arc | 120° | **360° (omnidirectional)** | The arm tracks any shooter (owner). |
| Shield accuracy modifier | −20 | keep −20 to start | Harder to hit (owner). |
| Shield damage multiplier | 0.35 | moderate (0.6 to 0.8 to start) | The accuracy modifier is the main defense; a very large damage cut would make hit chance meaningless. |
| Shield capacity | none | **hits blocked per round: 2 to start** | Counter to focus fire. Resets at the unit's next activation. |
| While shielded | no attack, no reload | same | Already implemented. |
| Visual | default | distinct tint for now | So players can tell it apart at a glance (owner). |

## Weaknesses (the balance side)

1. **Capacity** (new): the arm can only cover a limited number of hits per round. Several attackers overwhelm it. Readable and fits one arm.
2. **Mobility and reach**: slow, short range, so it must walk into the fight and can be kited.
3. **Weapons that ignore a shield** (future, owner): an anti-material sniper and similar. Needs weapon types first.
4. **Explosives** (future): grenades hit an area and are not "a bullet the arm can block". Needs grenades first.
5. **Cannot shoot while shielded**: already implemented, so the stance is a real commitment.

## Where it shines

- **Rescue missions** (owner): a carrier is already slow, so a Bulwark escort moves at the same pace and can stand next to the carrier or VIP with no concern for facing. Escorts do not reposition today, so the AI side needs thought.
- Holding a doorway or chokepoint while others flank the enemy.

## Future implementation ideas

Weapon and unit variety:
- **Skirmisher**: high mobility, small-caliber pistol, short range, lower damage (owner).
- **Anti-material sniper**: very long range, high damage, ignores shields (owner).
- **Per-archetype weapon profile**: damage, range, hit-chance curve and armor piercing per archetype rather than one global value.
- **Grenades and explosives**: area damage that shields and cover handle differently.

Shield and defense:
- **Shield capacity per round** as described above, shown in the unit UI.
- **Shield integrity (ablative)**: an alternative to the per-round cap, where the arm has HP that depletes and repairs.
- **A "braced" movement penalty** after using the stance, if the class's permanent slowness turns out not to be enough.
- **Hunker-style stance for non-shield units** (XCOM reference): harder to hit while in cover.

Presentation:
- **Shield arm animation**: the arm swings toward the incoming shooter (owner). The game already knows who the shooter is, so this is presentation on top of the rules.
- **Class tint, then class models.**

AI:
- **Class-aware AI**: Bulwark escorts, focus-fire on a shield that is near its capacity, use of the anti-material sniper against Bulwarks.
- **Guard (overwatch) valuation** is still open from AI step 6.

## Code work needed for the first Bulwark

Small:
1. Edit `shieldbearer.tres`: movement range, attack range, HP.
2. Tint per archetype (new field and a hook where the unit is built).

Medium:
3. Omnidirectional arc: set `protected_arc_degrees` to 360 and confirm `CombatRules.is_within_protected_arc` and the AI's facing choice behave for a full circle.
4. Capacity per round: new state on the unit, cleared in `begin_activation`, honoured in `CombatRules.evaluate_attack`, in the replay fingerprint and in the AI's prevented-damage valuation.

Always when combat numbers change:
5. Advance `SIMULATION_VERSION`, update the shield signature test and replay documentation.
6. Rerun the AI baseline and compare; the baseline has no Shield-capable units, so add a scenario or a small Bulwark baseline.

## Open questions

- Capacity per round (resets next activation) or per stance use? Proposed: per round.
- Should the damage multiplier stay at all, or should the shield be only "harder to hit" plus capacity?
- Exact movement and range numbers: confirm against the real baseline values before fixing them.

## What shipped (first Bulwark)

- **Archetype `bulwark`** (`units/archetypes/bulwark.tres`): speed 3, attack range 6 (the battle default is 10), 3 AP, 100 HP, yellow stripe. It is added at the end of the catalog, so it appears last in the match-setup roster. The older `shieldbearer` stays as the lab preset with the original 120° Shield.
- **Shield `bulwark_shield.tres`**: 360° arc (omnidirectional), accuracy modifier −20, damage multiplier 0.7, 1 AP, no attacking or reloading while it is up, and a **capacity of 2 covered attacks** per stance.
- **Capacity rule** (`ShieldCapability.max_attacks_covered`, 0 = unlimited): every attack the shield covers (a shot, a Guard reaction or a retaliation) counts; once the count reaches the capacity, later attacks get no protection and the attack preview says "Shield overwhelmed". The count lives in `TacticalState.shield_attacks_covered`, resets when the stance is made or ends (next activation), is part of the replay fingerprint only when it is above zero, and joins the shield signature only when the capacity is set. The original Shield is therefore unchanged: same behaviour, same signature, same fingerprint.
- **AI**: the Shield plan values only as many attackers as the capacity covers (the most valuable first); with a 360° arc all attackers are in the arc, so the facing choice no longer matters.
- **HUD**: the state label reads `SHIELD ALL-ROUND n/2` (attacks still covered); the Shield tooltip says the arm tracks every attacker and states the capacity.
- **Stripe**: a thin band on the chest bone (`UnitVisualAdapter.set_class_marker`), colour from the archetype's `marker_color` (alpha 0 = none). Presentation only. Rendered review: `tests/class_marker_capture.gd` (explicit-only). The band is round, a little wide for the torso in side view, and an obvious placeholder for a proper paint job.
- **Tests**: `tests/bulwark_shield_test.gd` (archetype numbers, signature compatibility, omnidirectional cover, capacity in a real battle, fingerprint, AI valuation with a capacity, the stripe); `tests/tactical_archetype_lab_test.gd` updated for the sixth archetype (an intended catalog change; its shield-less rule now exempts the Bulwark too).
- **Not done**: no simulation version bump (existing content, replays and fingerprints are unchanged; a recording that uses the Bulwark records its shield signature), no baseline with Bulwarks in it, no balance numbers beyond the proposals above, no shield-arm animation.
