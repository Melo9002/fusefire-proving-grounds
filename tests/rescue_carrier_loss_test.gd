extends SceneTree
## Issue #40: a carrier that falls must not strand the rescued VIP.
## Rules under test:
##  - The VIP drops where the carrier fell (nearest legal cell if that one cannot be stood on), visible,
##    active and on the grid, and the carrier no longer carries anyone.
##  - The Rescue objective reopens, so any pursuing unit can carry the VIP again.
##  - Until the VIP is carried again, escorts cannot extract (the VIP is still outstanding).
##  - The mission can still be won: the second carrier extracts with the VIP and the rest follow.
##  - Losing a unit that carries nobody changes nothing about the rescue.

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _create_level() -> BattleLevel:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(3, 2, false, 1, 0, Vector2i(32, 24), false, MissionActor.VIPBehavior.PLAYER_CONTROLLED, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.RESCUE, 2, false))
	root.add_child(level)
	await create_timer(0.15).timeout
	level.action_camera_director.frequency = level.action_camera_director.Frequency.OFF
	return level

func _finish(level: BattleLevel) -> void:
	level.queue_free()
	await process_frame
	await process_frame

func _run() -> void:
	await _carrier_falls_and_the_vip_can_be_recovered()
	await _blocked_drop_cell_falls_back_to_a_free_one()
	await _losing_a_non_carrier_changes_nothing()
	print("Rescue carrier loss: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _rescue(level: BattleLevel, carrier: TacticalUnit, target: TacticalUnit) -> bool:
	var grid := level.battle_controller.grid_manager
	grid.update_unit_position(carrier, carrier.grid_position, grid.get_unit_grid(target) + Vector3i.LEFT)
	return await level.objective_manager.try_rescue(carrier, target)

func _carrier_falls_and_the_vip_can_be_recovered() -> void:
	var level := await _create_level()
	var turns := level.turn_manager
	var grid := level.battle_controller.grid_manager
	var objectives := level.objective_manager
	var target := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var carrier: TacticalUnit = turns.player_units[0]
	var teammate: TacticalUnit = turns.player_units[1]
	var remaining: TacticalUnit = turns.player_units[2]
	check(await _rescue(level, carrier, target), "Setup: the carrier rescues the VIP")
	check(carrier.is_carrying_unit() and not target.visible, "Setup: the VIP is carried and hidden")
	var fall_cell := carrier.grid_position
	carrier.stats.take_damage(1000)
	await create_timer(1.6).timeout

	check(not is_instance_valid(carrier) or not carrier.is_carrying_unit(), "A fallen carrier no longer carries anyone")
	check(is_instance_valid(target) and target.visible, "The dropped VIP is visible again")
	check(is_instance_valid(target) and target.process_mode != Node.PROCESS_MODE_DISABLED, "The dropped VIP is active again")
	check(is_instance_valid(target) and grid.get_unit_at(target.grid_position) == target, "The dropped VIP stands on the grid")
	check(is_instance_valid(target) and target.grid_position.distance_to(fall_cell) <= 1.5, "The VIP drops where the carrier fell (carrier at %s, VIP at %s)" % [fall_cell, target.grid_position if is_instance_valid(target) else "gone"])
	check(objectives.find_mission_actor([target.get_mission_id()]) == target, "The dropped VIP can be found on the field")
	check(objectives.find_rescue_carrier(TacticalUnit.Faction.PLAYER) == null, "Nobody is carrying the VIP")
	var rescue := objectives.get_objective(&"rescue")
	check(rescue.is_active() and rescue.progress == 0, "The Rescue objective reopens (status %s, progress %d)" % [rescue.status, rescue.progress])
	check(objectives.get_objective(&"extract_rescue").is_active(), "The VIP's extraction objective stays open")
	check(turns.battle_result == TurnManager.BattleResult.ONGOING, "The mission continues: the VIP can be recovered")

	# Until the VIP is carried again, escorts cannot leave.
	var exit: Vector3i = grid.map_data.get_objective_zone(&"extract")[0]
	var rescuer_cell := target.grid_position + Vector3i.LEFT
	if not grid.can_unit_occupy_cell(teammate, rescuer_cell):
		rescuer_cell = target.grid_position + Vector3i.RIGHT
	grid.update_unit_position(remaining, remaining.grid_position, exit)
	check(not objectives.can_extract(remaining), "An escort cannot extract while the VIP is still on the field")

	# A teammate recovers the VIP.
	grid.update_unit_position(teammate, teammate.grid_position, rescuer_cell)
	check(objectives.can_rescue(teammate, target), "A teammate beside the dropped VIP can rescue it")
	check(await objectives.try_rescue(teammate, target), "The teammate carries the VIP")
	check(teammate.is_carrying_unit() and objectives.get_objective(&"rescue").is_completed(), "The Rescue objective completes again")
	check(objectives.can_extract(remaining), "With the VIP carried again, escorts may extract")

	# The mission can still be won.
	grid.update_unit_position(teammate, teammate.grid_position, exit + Vector3i.RIGHT if grid.can_unit_occupy_cell(teammate, exit + Vector3i.RIGHT) else exit)
	var zone: Array[Vector3i] = grid.map_data.get_objective_zone(&"extract")
	grid.update_unit_position(teammate, teammate.grid_position, zone[1] if zone.size() > 1 else zone[0])
	check(await objectives.try_extract(teammate), "The new carrier extracts together with the VIP")
	await process_frame
	check(turns.battle_result == TurnManager.BattleResult.ONGOING, "Boarding the VIP leaves time for the remaining escort")
	grid.update_unit_position(remaining, remaining.grid_position, zone[0])
	check(await objectives.try_extract(remaining), "The remaining escort extracts")
	await process_frame
	await process_frame
	check(turns.battle_result == TurnManager.BattleResult.VICTORY, "Rescuing, losing the first carrier and recovering the VIP is still a Victory (result %s)" % str(turns.battle_result))
	await _finish(level)

## If the carrier's own cell cannot be stood on, the VIP is placed on the nearest cell that can.
func _blocked_drop_cell_falls_back_to_a_free_one() -> void:
	var level := await _create_level()
	var grid := level.battle_controller.grid_manager
	var target := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var carrier: TacticalUnit = level.turn_manager.player_units[0]
	check(await _rescue(level, carrier, target), "Setup: the carrier rescues the VIP")
	var fall_cell := carrier.grid_position
	grid.get_cell_data(fall_cell).can_stop = false
	carrier.stats.take_damage(1000)
	await create_timer(1.6).timeout
	check(is_instance_valid(target) and target.visible and grid.get_unit_at(target.grid_position) == target, "The VIP is placed even when the fall cell cannot be stood on")
	check(is_instance_valid(target) and target.grid_position != fall_cell and target.grid_position.distance_to(fall_cell) <= 3.0, "It lands on a nearby cell instead (fall %s, VIP %s)" % [fall_cell, target.grid_position if is_instance_valid(target) else "gone"])
	check(is_instance_valid(target) and grid.can_unit_occupy_cell(target, target.grid_position) == false and grid.get_cell_data(target.grid_position).can_stop, "The chosen cell is a legal standing cell")
	await _finish(level)

## A fallen unit that carries nobody leaves the rescue exactly as it was.
func _losing_a_non_carrier_changes_nothing() -> void:
	var level := await _create_level()
	var objectives := level.objective_manager
	var target := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var bystander: TacticalUnit = level.turn_manager.player_units[1]
	var cell_before := target.grid_position
	bystander.stats.take_damage(1000)
	await create_timer(1.2).timeout
	check(objectives.get_objective(&"rescue").is_active() and objectives.get_objective(&"rescue").progress == 0, "The Rescue objective is untouched")
	check(target.visible and target.grid_position == cell_before, "The VIP has not moved")
	check(level.turn_manager.battle_result == TurnManager.BattleResult.ONGOING, "The mission continues")
	await _finish(level)
