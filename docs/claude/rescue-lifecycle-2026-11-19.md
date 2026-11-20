# Rescue interaction, incapacitation and lifecycle integrity (stabilization 02)

## 1. Root causes

* **Automatic pickup.** `ObjectiveManager._on_unit_moved` called `complete_rescue` for any pursuing unit whose move ended next to a rescue target. It dates from the first
  commit (`6213710 Replay system`): inherited from the original design, with the comment "a consequence of the movement command", not an accident of the animation work. There
  was **no** player-facing Rescue control at all: the only explicit callers were AI units (`ai_controller.gd`) and tests. (The Extract action has a button on the unit's world bar;
  Rescue never did.) So "restore the explicit workflow" meant removing the side effect and adding the missing button.
* **Premature state.** The tactical commit (`unit_moved`, then `complete_rescue` -> `carry_unit`) happens when the move is committed, before the carrier's body had walked there;
  the presentation then started the lift with the carrier still far away (stabilization 01B hid this by deferring the lift until arrival). With rescue now an explicit action taken
  from an adjacent cell, the tactical carry state and the body agree in normal play; the arrival deferral stays as a safety for a rescue decided while the body is still elsewhere
  (AI, scripts).
* **Standing VIP after carrier loss.** The tactical release (`release_carried_unit`) correctly re-registered the actor, visible and active, and reopened the objective, but nothing
  told the VIP's visual it was still incapacitated, so its ordinary standing rig reappeared. In fact it was *never* shown incapacitated before pickup either: it stood with a rifle.

## 2. The explicit workflow

1. The player selects an eligible unit and moves it next to the target (ordinary movement). Nothing is rescued.
2. The tactical rescue query (`query_mission(&"rescue", unit)`) lists legal targets (adjacent, objective active, rescuer not already carrying). Unchanged rules, zero-AP cost.
3. The unit's world bar shows a **RESCUE** button (`UnitWorldBar.rescue_button`, same pattern and placement as the Extract button). Pressing it calls
   `ObjectiveManager.try_rescue`, i.e. the existing validated, recorded action.
4. The tactical state changes (carrying, objective completed); the action presenter waits for the timed lift (`RescueInteraction`), which starts from how the target lies.

**Not supported (and not invented):** selecting a *distant* target and having the unit walk there and rescue. Rescue requires adjacency today and there is no move-then-act order
anywhere in the action model. Documented gap; adding it is a game-design decision (a new compound command).

## 3. Timing contract

Tactical layer: eligibility, range, cost, carrying, ownership, objective state, carrier death and recovery. Presentation: approach visuals, lift choreography, passenger look, carry poses,
weapon sling. A pending rescue is not a completed pickup: `UnitVisualAdapter.pickup_pending()` is true while the tactical carry exists but the body has not arrived; `_carrying()` is
false then (the carrier walks with its rifle). No new tactical state was added. Every interruption resolves: movement or boarding during the lift settles it (`finish_interaction_now`);
the carrier falling at any point clears pending and frees the passenger (`present_carry_released`); a repeated Rescue is rejected by the tactical rules.

## 4. Incapacitated presentation

* **Owner of the flag:** `ObjectiveManager.refresh_incapacitation()` derives `TacticalUnit.awaiting_rescue` from the rescue objective (target, objective active, not carried) at round start,
  on every objective change and after a carrier falls. It is a *derived presentation hint*, not a tactical state; it changes no rule.
* **Presentation:** `UnitVisualAdapter.present_incapacitated(bool)` hides the standing rig and its rifle and shows an `IncapacitatedBody` (a `RescuePassenger` in the lying pose) on the
  ground at the actor's position; no idle, weapon or locomotion. It persists until the flag changes.
* **Continuity:** the pickup starts from that body's exact position and orientation (`ground_basis`; tested to 20 mm and 3 degrees), and it is the pose the lift already used, so the
  swap to the carrier's passenger is invisible. After a carrier falls the same body reappears where the actor is.
* **Extensibility:** other conditions (conscious, mobility-impaired, disabled) would be other poses behind the same `present_incapacitated`-style entry point driven by a richer derived
  flag; only the single incapacitated state exists.

## 5. Files

`systems/objectives/objective_manager.gd` (auto-rescue removed, `refresh_incapacitation`), `units/tactical_unit.gd` (`awaiting_rescue`, pass the lying orientation),
`ui/unit_world_bar.gd/.tscn` (Rescue button), `presentation/characters/runtime/unit_visual_adapter.gd` (incapacitated presentation, lying orientation handed to the lift),
`rescue_passenger.gd` (`lie_on_ground`, `ground_basis`), `character_rig.gd` (`begin_pickup` takes the orientation). Tests: `rescue_lifecycle_test.gd` (new, 38 checks);
`core_objectives_smoke.gd` (rescue is now explicit; encodes "moving next to the target does not rescue"), `rescue_carrier_loss_test.gd` (unchanged contract).

## 6. Limitations

Distant rescue orders are unsupported (above). The player-controlled VIP is still selectable/ordinary tactically (rules unchanged). The incapacitated body is a hard cut from the VIP
standing before the mission starts (it is incapacitated from the first frame). Orientation of the lying body is fixed (across the unit's facing). End Turn during a lift is not specially
handled (the lift continues; the turn manager is untouched). Evidence is scripted from the real level and the real world-bar button; no mouse was driven.
