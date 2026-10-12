# Tactical Conditions and Fictional Systems Reference

This document records Task 01.12 as implemented and keeps its fictional interpretation separate from future design. It is a reference for gameplay engineering, mission and equipment design, narrative writing, and Task 01.13.

The labels below are deliberate:

- **Implemented** — verified in the current game, source, and tests.
- **Provisional fictional canon** — an agreed setting assumption used for writing and design, but not necessarily simulated.
- **Proposed** — a possible future direction that has not been approved as a mechanic or fact of the setting.
- **Undecided** — a question that still needs a design or worldbuilding decision.

## Terminology

| Term | Status | Meaning |
| --- | --- | --- |
| Activation | **Implemented** | One actor's opportunity to spend AP and perform legal actions. |
| Tactical beat | **Implemented boundary; provisional duration** | One complete shared tactical round. The engine exposes one deterministic end-of-round boundary. Fiction treats the interval as approximately three seconds. |
| Action Point (AP) | **Implemented resource; provisional interpretation** | The authoritative action budget spent during an activation. Fictionally, AP measures useful tactical opportunities rather than literal seconds. |
| Condition definition | **Implemented** | An Inspector-editable `ConditionDefinition` Resource containing stable identity, susceptibility, duration, recurring damage, an optional restricted action, an optional non-positive maximum-AP delta, and presentation metadata. |
| Condition instance | **Implemented** | Per-unit runtime state containing the definition, remaining beats, application beat, and source identity. |
| Susceptibility | **Implemented** | A data flag indicating that a unit can receive biological, mechanical-fluid, or electronic conditions. |
| Immunity | **Implemented** | A per-unit condition-ID exclusion checked before application. It is also the narrow hook future equipment can populate. |
| Emergency Seal | **Implemented mechanic; fictional form undecided** | A one-charge self-treatment action that stops Leaking without restoring lost HP. |
| Active fluid loss | **Provisional fictional concept** | Continuing loss from a damaged mechanical system, represented mechanically by Leaking. |
| Lasting impairment | **Proposed** | Damage that continues to affect performance after active fluid loss is sealed. No such penalty exists in 01.12. |

## Tactical time

### Fictional model

**Provisional fictional canon:** one tactical beat represents approximately **three seconds** of battlefield activity. It is a pacing and worldbuilding approximation, not a real-time clock. Sequential activations present events in a readable order even though some movement, thought, and reaction may overlap fictionally.

An activation belongs to one actor. A tactical beat is the shared interval in which eligible combatants receive activation opportunities. AP measures how many meaningful tactical opportunities a unit can exploit in that interval. Three AP therefore does not assert that a unit literally moves, aims, or thinks 50 percent faster than a two-AP unit. Actions also do not each consume exactly one fictional second.

### Implemented boundary

**Implemented:** `TurnManager._end_round()` emits `tactical_beat_ended(current_round)` after the allied and enemy activation queues have finished. If a phase has no actors, the turn manager passes through it and reaches the same shared boundary. The signal is synchronous and occurs before the round counter increments and before the next player phase begins.

`TacticalActionService._on_tactical_beat_ended()` then:

1. Collects registered actors and sorts them by stable tactical actor ID.
2. Skips invalid or already defeated actors.
3. Ticks each actor's active conditions in stable condition-ID order.
4. Decrements each condition's remaining duration.
5. Applies configured recurring damage through `UnitStats.take_damage()`.
6. Records HP before and after, duration, beat, and defeat in the beat event.
7. Removes a condition after its final tick when its remaining duration reaches zero.

Periodic damage therefore occurs once per shared round boundary, never once per action or AP. A condition applied during a round causes no immediate periodic damage; its first tick occurs at the next end-of-round boundary. A final tick still applies its configured damage before expiration.

Condition damage uses the existing defeat signals, roster removal, objectives, battle result, and turn recovery. If a casualty ends the mission during the boundary, `TurnManager` does not advance into another round. The actor list is read in a deterministic order, and a defeated actor receives no further condition ticks.

### Worked Leaking example

Assume MIRA-03 has 10 HP, one Emergency Seal charge, and acquires a fresh three-beat Leaking instance during beat 4.

| Moment | HP | Remaining beats | Result |
| --- | ---: | ---: | --- |
| Leaking is applied during beat 4 | 10 | 3 | No immediate periodic damage. Blue droplets and the status label reflect committed state. |
| End of beat 4 | 9 | 2 | The first 1 HP tick resolves. |
| During beat 5, MIRA-03 uses Emergency Seal | 9 | — | The action spends 1 AP and one charge, removes Leaking, stops the droplets, and restores no HP. |
| End of beat 5 | 9 | — | No Leaking instance remains, so no further damage occurs. |

Without treatment, Leaking would tick at the ends of beats 4, 5, and 6, then expire after the third point of damage.

## Implemented condition architecture

The implementation is intentionally narrower than a general effect engine.

### Definitions and runtime ownership

`ConditionDefinition` Resources are immutable shared definitions. They expose a stable ID, display text, required susceptibility flags, duration, recurring damage, one optional restricted action, one optional non-positive maximum-AP delta, and status color. `ConditionComponent` belongs to each spawned unit and owns its independent active instances. Applying or treating a condition never mutates the shared Resource.

There is at most one active instance for each condition ID on a unit. Reapplication refreshes that instance to the definition's full duration and updates its application beat and source; it does not create a second stack or an extra immediate tick.

`TacticalUnit.can_receive_condition()` checks explicit condition-ID immunity first, then requires every susceptibility flag named by the definition. Current MIRA archetypes are configured for mechanical-fluid and electronic susceptibility. Biological susceptibility is supported by data and fixtures without introducing playable humans.

### Authority and action integration

Condition application is owned by `TacticalActionService`:

- a configured damaging Attack may append application evidence to its `AttackActionResult`;
- an entered hazardous movement checkpoint may append exposure evidence to its parent `MoveActionResult`;
- Emergency Seal is a typed query/request/result action;
- the tactical-beat signal drives periodic ticks.

Rejected and stale actions do not alter AP, charges, HP, or condition state. Nested attack and hazard applications do not create separate top-level transactions or revisions. Presentation observes committed state and never applies, ticks, removes, or damages.

### Condition summary

| Condition | Status | Susceptibility | Duration | Periodic effect | Other rule | Presentation |
| --- | --- | --- | ---: | --- | --- | --- |
| Leaking | **Implemented** | Mechanical fluid | 3 beats | 1 HP per beat | Removed by Emergency Seal; no AP or accuracy penalty | Blue `CPUParticles3D` droplets plus HUD/world status text |
| Bleeding | **Implemented definition and proof fixture** | Biological | 3 beats | 1 HP per beat | Emergency Seal does not treat it | Basic shared status text/color; no bespoke biological actor or effect |
| Jammed | **Implemented** | Electronic | 1 beat | None | Disables Aim and clears an existing Aim when successfully applied | Basic shared status text/color |
| System Overload | **Implemented provisional test fixture** | Electronic | 2 beats | None | Applies -1 effective maximum AP through `condition:system_overload`; absent from normal missions and loadouts | Basic shared status text/color |

Leaking, Bleeding, and Jammed retain their original rules and apply no AP modifier. No accuracy, movement, Shield, Guard, or additional damage modifiers are implied by System Overload.

### Condition-owned AP modifiers

**Implemented in 01.13.4:** a definition with a nonzero `maximum_ap_delta` is synchronized by its owning `ConditionComponent` through the stable `condition:<condition_id>` source in `UnitStats`. Reapplication refreshes the one runtime condition instance and replaces the same modifier source, so it cannot stack duplicate penalties. Explicit removal, expiration, component clearing, and unit defeat remove that source idempotently. Other modifier sources remain untouched.

The AP lifecycle continues to own capacity and expenditure. Applying a penalty can ratchet activation capacity downward. Removing or expiring it restores effective maximum but never raises capacity or refunds AP during the current activation; the restored maximum becomes available at the next faction-phase refresh. Susceptibility or immunity rejection occurs before condition state changes and therefore creates no modifier.

System Overload is deliberately stored under `tests/fixtures/`. It proves this contract without adding an ordinary weapon, hazard, mission rule, loadout, AI policy, or wider condition catalogue.

### Emergency Seal

**Implemented mechanics:**

- self-treatment costs 1 AP;
- one successful use consumes one available charge;
- it requires an active Leaking instance;
- it removes Leaking immediately;
- it restores 0 HP;
- it does not remove Bleeding or Jammed;
- rejection consumes neither AP nor a charge;
- AI checks the same authoritative query and self-treats when Leaking and eligible.

**Provisional fictional interpretation:** Emergency Seal stabilizes an active breach and prevents additional loss. It does not repair components or reverse damage already represented by missing HP. The physical product, application method, and material remain undecided.

Lasting injuries, actuator damage, full maintenance, broader field-repair kits, ally treatment, biological bandages, and inventory management remain future design space.

### AI behavior

**Implemented:** at the start of each ordinary AI decision loop, a leaking unit tries the shared Emergency Seal query. A legal treatment is submitted through the same action service used by the player, consumes its normal resources, and then the AI continues its turn if AP remains. Jammed Aim attempts fail through the shared Aim query, so AI cannot bypass the restriction or enter a separate AI-only legality path.

This is a small deterministic policy, not medical planning. The AI does not value future leak damage, transfer supplies, treat allies, or select between treatment items.

### Presentation

**Implemented:** the HUD lists active conditions with remaining beats. Leaking creates lightweight blue droplets attached to the affected unit. The emitter stops as soon as authoritative state removes Leaking or the unit is defeated. Bleeding and Jammed use the shared status display and configured colors without bespoke effects.

The particle system and labels communicate simulation state. They do not own duration, damage, eligibility, or removal.

## Environmental effects

**Implemented:** `TileHazardMarker` is an Inspector-authored placement adapter. Its assigned condition definition is copied into the corresponding runtime `MapCellData`; the scene node is not the authority after setup. The default marker definition is Jammed.

During a committed Move, each entered checkpoint resolves in this order:

1. The mover enters the legal checkpoint in the movement-resolution context.
2. The cell's hazard exposure is evaluated and any eligible condition is applied or refreshed.
3. Armed hostile Guard reactions are evaluated from that checkpoint.
4. Movement continues or stops according to the committed outcomes.

This ordering means an electrified tile can apply Jammed before a Guard shot at the same checkpoint. Exposure and reaction facts remain nested in the one parent Move transaction. Rejected movement creates no exposure, and presentation callbacks cannot create it.

Ordinary missions do not automatically receive hazards. A hazard exists only when authored or deliberately installed in a test fixture; the current standard map scenes do not globally convert tiles into electrified terrain.

**Proposed examples, not approved features:** fire, gas, corrosive pools, unstable machinery, and other hazards could reuse the same definition/application boundary where their rules fit. Spreading terrain, diffusion, destructible sources, chained environmental simulation, and arbitrary effect graphs are outside 01.12.

## Combat application

**Implemented:** a unit or test weapon may assign one optional `attack_condition` definition. A committed Attack applies it only when the attack hits, deals positive damage, and leaves the target alive and susceptible. The application is part of the parent Attack result. Misses, rejected attacks, zero-damage outcomes, defeated targets, immune targets, and ordinary attackers with no configured condition do not receive or apply the condition.

Ordinary attacks do **not** automatically inflict Leaking. Critical hits and persistent conditions are separate design concepts; 01.12 adds no critical-hit system and requires no random condition roll.

**Proposed:** specialized weapons or ammunition may deliberately apply conditions. An EMP grenade is one example that could reuse Jammed, but neither EMP grenades nor grenades generally are implemented or approved by this milestone.

## Determinism and replay

**Implemented:** new battle configurations explicitly set `conditions_enabled`. Condition-enabled fingerprints include each unit's sorted condition identity, remaining duration, application beat, source ID, and Emergency Seal charge count. Attack and Move payload schema 9 store nested condition events; Emergency Seal uses typed payload schema 9. The replay envelope remains schema 3.

Historical configurations that omit `conditions_enabled` load it as false. They retain pre-condition fingerprints and semantics, cannot submit Emergency Seal, and do not gain hazards or attack conditions retroactively. Existing pre-SP, pre-Aim, pre-Shield, pre-Guard, and terminal-era recordings therefore do not silently change meaning.

Condition queries consume no combat RNG. Periodic ticks, eligibility, treatment, and hazard exposure are deterministic. Normal, suppressed, headless, and replay execution share authoritative outcomes; only presentation differs.

## Fictional interpretation of MIRA damage

The following distinctions guide writing without establishing unsupported engineering lore.

| Concept | Status | Interpretation |
| --- | --- | --- |
| Mechanical body damage | **Provisional fictional canon** | Lost HP represents damage already suffered by the body. Sealing a leak does not erase it. |
| Active fluid loss | **Provisional fictional canon** | Leaking represents an ongoing breach that causes further damage until sealed or naturally resolved by duration. |
| Electronic disruption | **Provisional fictional canon** | Jammed represents temporary interference severe enough to prevent deliberate Aim preparation, without reducing AP or shutting the MIRA down. |
| Battlefield stabilization | **Provisional fictional canon** | Emergency Seal stops further fluid loss but is not full repair or maintenance. |
| Long-term physical impairment | **Proposed** | Damaged components may eventually affect accuracy, movement, or tactical tempo after stabilization. No such rule exists now. |

### Open worldbuilding questions

These questions are **undecided**:

- What fluid does a MIRA lose?
- Is it coolant, lubricant, hydraulic fluid, a multifunctional working fluid, or something else?
- Which internal systems depend on it?
- What does an Emergency Seal physically contain?
- Is the seal sprayed, injected, wrapped, magnetically attached, or applied another way?
- Can MIRA manufacturers use incompatible fluids, fittings, or repair products?
- Can a battlefield seal contaminate or complicate later maintenance?
- Which damaged internal components might affect future tactical tempo?
- Do MIRAs distinguish minor leakage from catastrophic system loss in language or diagnostics?

No chemical composition, manufacturer standard, service history, or established technological timeline is canonized by 01.12.

## Tactical tempo and Task 01.13

The following began as **01.13 design intent**. Base, effective maximum, activation capacity, expenditure, and current AP accounting are now implemented through 01.13.4; future humans, exceptional-unit balance, equipment, enhancements, and injuries remain proposals:

- typical future humans have 2 base AP;
- typical MIRAs have 3 base AP;
- exceptional units may reach 4 AP;
- base AP, effective maximum AP, activation capacity, expenditure, and current AP are distinct concepts;
- a provisional condition fixture can modify effective maximum AP;
- equipment, enhancements, and injuries may eventually provide other modifier sources;
- AP continues to represent effective tactical tempo rather than literal movement speed.

Current MIRA archetype Resources are authored with 3 Base AP. Runtime accounting preserves expenditure when capacity changes and prevents same-activation refunds. System Overload is the only condition/AP bridge and exists only as a controlled fixture. Human actors, injury-driven tempo changes, equipment bonuses, and explicit AP grants are not implemented.

The three-second fictional beat gives recurring effects and future tempo rules a shared narrative scale. It does not require a real-time scheduler or promise that every unit performs actions simultaneously.

## Implementation references

| Responsibility | Current source |
| --- | --- |
| Definition schema and runtime instances | [`units/conditions/condition_definition.gd`](../../units/conditions/condition_definition.gd), [`condition_instance.gd`](../../units/conditions/condition_instance.gd), [`condition_component.gd`](../../units/conditions/condition_component.gd) |
| Leaking, Bleeding, and Jammed data | [`units/conditions/`](../../units/conditions/) |
| Unit susceptibility, immunity hook, and droplets | [`units/tactical_unit.gd`](../../units/tactical_unit.gd) |
| Beat boundary and round progression | [`systems/turn_manager.gd`](../../systems/turn_manager.gd) |
| Application, treatment, hazards, ordering, and ticks | [`systems/actions/runtime/tactical_action_service.gd`](../../systems/actions/runtime/tactical_action_service.gd) |
| Authored hazard adapter and runtime cell state | [`systems/grid/tile_hazard_marker.gd`](../../systems/grid/tile_hazard_marker.gd), [`map_cell_data.gd`](../../systems/grid/map_cell_data.gd) |
| AI self-treatment | [`units/ai_controller.gd`](../../units/ai_controller.gd) |
| Replay fingerprints and compatibility | [`systems/replay/battle_state_fingerprint.gd`](../../systems/replay/battle_state_fingerprint.gd), [`battle_replay_recording.gd`](../../systems/replay/battle_replay_recording.gd), [`replay_record_tools.gd`](../../systems/replay/replay_record_tools.gd) |
| Focused verification | [`tests/tactical_conditions_test.gd`](../../tests/tactical_conditions_test.gd) |
| Condition/AP integration verification | [`tests/condition_ap_tempo_integration_test.gd`](../../tests/condition_ap_tempo_integration_test.gd), [`tests/fixtures/system_overload.tres`](../../tests/fixtures/system_overload.tres) |

The broader ownership summary remains in [`docs/architecture.md`](../architecture.md), and Inspector editing guidance remains in [`docs/human-editing-guide.md`](../human-editing-guide.md).

## Explicitly outside 01.12

- additional condition/AP integrations, equipment modifiers, and explicit AP grants;
- playable humans and biological treatment equipment;
- random critical condition application;
- grenades, EMP damage, specialized ammunition, and weapon inventories;
- ally treatment, supply transfer, and general item use;
- permanent injuries and post-battle maintenance;
- spreading or simulated environmental hazards;
- a universal effect graph, scripting language, or generalized equipment system;
- definitive MIRA fluid chemistry, repair standards, or manufacturer lore.
