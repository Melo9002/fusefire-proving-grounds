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

- **Archetype `bulwark`** (`units/archetypes/bulwark.tres`): speed 4 (baseline 5), attack range 8 (battle default 10), 3 AP, 110 HP, yellow stripe (tuned by AI-versus-AI trials, below). It is added at the end of the catalog, so it appears last in the match-setup roster. The older `shieldbearer` stays as the lab preset with the original 120° Shield.
- **Shield `bulwark_shield.tres`**: 360° arc (omnidirectional), accuracy modifier −30, damage multiplier 0.5, 1 AP (strengthened after the Shield trial below), no attacking or reloading while it is up, and a **capacity of 2 covered attacks** per stance.
- **Capacity rule** (`ShieldCapability.max_attacks_covered`, 0 = unlimited): every attack the shield covers (a shot, a Guard reaction or a retaliation) counts; once the count reaches the capacity, later attacks get no protection and the attack preview says "Shield overwhelmed". The count lives in `TacticalState.shield_attacks_covered`, resets when the stance is made or ends (next activation), is part of the replay fingerprint only when it is above zero, and joins the shield signature only when the capacity is set. The original Shield is therefore unchanged: same behaviour, same signature, same fingerprint.
- **AI**: the Shield plan values only as many attackers as the capacity covers (the most valuable first); with a 360° arc all attackers are in the arc, so the facing choice no longer matters.
- **HUD**: the state label reads `SHIELD ALL-ROUND n/2` (attacks still covered); the Shield tooltip says the arm tracks every attacker and states the capacity.
- **Stripe**: a thin band on the chest bone (`UnitVisualAdapter.set_class_marker`), colour from the archetype's `marker_color` (alpha 0 = none). Presentation only. Rendered review: `tests/class_marker_capture.gd` (explicit-only). The band is round, a little wide for the torso in side view, and an obvious placeholder for a proper paint job.
- **Tests**: `tests/bulwark_shield_test.gd` (archetype numbers, signature compatibility, omnidirectional cover, capacity in a real battle, fingerprint, AI valuation with a capacity, the stripe); `tests/tactical_archetype_lab_test.gd` updated for the sixth archetype (an intended catalog change; its shield-less rule now exempts the Bulwark too).
- **Not done**: no simulation version bump (existing content, replays and fingerprints are unchanged; a recording that uses the Bulwark records its shield signature), no baseline with Bulwarks in it, no balance numbers beyond the proposals above, no shield-arm animation.

## Skirmisher and the weapon damage multiplier

- **Archetype `skirmisher`**: speed 7, attack range 9, 110 HP, weapon damage x0.8 (a 20-damage hit instead of 25), 3 AP, **red stripe**. Last in the match-setup roster, after the Bulwark. No shield.
- **`weapon_damage_multiplier`** (new, on `TacticalUnit` and `TacticalArchetype`, default 1.0): scales every hit the unit's weapon deals. It is folded into the attack evaluation (`AttackEvaluation.damage_multiplier`, read through `CombatRules.damage_of`), so the preview, the committed hit, Guard reactions, the target scorer and the AI's Shield valuation all use one number. With 1.0 nothing changes for any other unit. The first small-caliber weapon, not yet a weapon type of its own.
- **Tests**: `tests/combat_skirmisher_weapon_test.gd` (12 checks: preview, committed damage, weapon times shield, the AI prices a shield by each attacker's own weapon); `tests/match_setup_bulwark_test.gd` now covers both classes in the setup menu and in battle; `tests/bulwark_replay_test.gd` records, saves, reloads and replays real AI matches with either class on either side (40 checks).

## Balance trials (AI against AI, 2026-11-18)

Headless matches on `service_depot`, ELIMINATE, Normal, 3 against 3, seeds 16 to 23: 8 with the class as players and 8 as enemies, against all-Generic. `tests/ai_baseline_report.gd` takes `player_archetype=` and `enemy_archetype=`; the simulator accepts rosters and records them only when given. Reference: all-Generic mirror, players win 5 of 8 (the player side has a built-in edge, which is why both sides are played). Target: the class side wins about 8 of 16.

**Correction.** An earlier version of this section said the first tougher Bulwark numbers won "4 of 8". That misread which side had won: it was 6 of 8 on seeds 16 to 19, and 14 of 16 on all eight seeds, so too strong.

| Class | Numbers (speed / range / HP, other) | Class side wins of 16 |
| --- | --- | --- |
| Bulwark | 3 / 6 / 100 (first proposal), seeds 16 to 19 | 0 of 8 |
| Bulwark | 4 / 8 / 130 | 14 |
| Bulwark | 3 / 8 / 130 | 11 |
| Bulwark | 4 / 8 / 115 | 10 |
| Bulwark | **4 / 8 / 110 (adopted)** | **10** |
| Bulwark | 4 / 7 / 110 | 6 |
| Bulwark | 4 / 7 / 120 | 6 |
| Bulwark | 3 / 8 / 120 | 5 |
| Bulwark | 4 / 8 / 100 | 4 |
| Skirmisher | 7 / 6 / 90, x0.6 damage (first proposal) | 0 of 16 |
| Skirmisher | x0.8, 100 HP, range 8 | 0 |
| Skirmisher | x0.75, 100 HP, range 10 | 1 |
| Skirmisher | x0.85, 110 HP, range 8 | 1 |
| Skirmisher | x0.9, 100 HP, range 9 | 1 |
| Skirmisher | x0.85, 100 HP, range 9 | 1 |
| Skirmisher | x0.8, 110 HP, range 8, speed 6 | 3 |
| Skirmisher | **x0.8, 110 HP, range 9, speed 7 (adopted)** | **7** |
| Skirmisher | x0.9, 110 HP, range 10, speed 6 | 9 |
| Skirmisher | x1.0, 90 HP, range 8 | 8 |

Reading, with limits:
- 16 matches per row: a result has roughly a plus or minus 12 point margin. These rows rank candidates; they do not prove balance. One map, one mode, one difficulty, and the same AI plays both sides.
- **The AI never kites and rarely uses Shield.** Across all the Bulwark and Skirmisher matches it took the stance only a handful of times, and a replay run of 16 class matches saw no covered attack. So the Bulwark numbers above are mostly the balance of a slow, short-ranged unit with extra HP, and the Skirmisher gets almost nothing from its speed. That is why the adopted Skirmisher has *more* HP than a baseline unit (110): the AI cannot use mobility, so the numbers compensate. Revisit both once the AI understands mobility (milestone 05 step 7, movement profiles) and when to shield.
- The adopted Skirmisher is still below even in one place: as players it won 2 of 8, as enemies 5 of 8.

## The AI and the Shield (2026-11-18)

**Why the AI almost never shielded.** The Shield branch sat after shooting and advancing, so a unit with a target never reached it. Fixing that alone changed nothing, because the AI now *compares* the plans and the numbers lose: with accuracy −20 and damage x0.7 the stance prevents about 8 HP per attacker, so even two covered attackers (about 17) are worth less than one good shot. The AI was right; the shield was weak.

**What changed in the AI** (`AIController._shield_instead_of_final_shot`): with only the stance's AP left and a legal shot, it compares the shot (HP-capped expected damage plus kill value) with the stance (expected prevented damage) and holds the stance only if it wins by a factor of 1.25 (`SHIELD_OVER_SHOT_MARGIN`). Earlier AP are still spent shooting, so the usual result is "attack, Shield". Scenarios S10c (three attackers: shoots, then holds the stance, "27.1 prevented against about 20.8 from the last shot") and S10d (a finishing shot is kept) cover it.

**Shield numbers, AI against AI** (same method as above, 16 matches each; Shield decisions counted over all units in those 16 matches):

| Shield (accuracy / damage / capacity) | Class side wins of 16 | Shield decisions |
| --- | --- | --- |
| −20 / x0.7 / 2 (before) | 11 | 6 |
| **−30 / x0.5 / 2 (adopted)** | **9** | **48** |
| −30 / x0.5 / 3 | 10 | 46 |
| −40 / x0.4 / 3 | 9 | 60 |

A stronger shield makes the AI use it eight times as often and the Bulwark stays about even. Limits: the AI only counts hostiles that can shoot it from where they stand now (not ones about to move into range), and it does not yet value the shield for protecting allies.
