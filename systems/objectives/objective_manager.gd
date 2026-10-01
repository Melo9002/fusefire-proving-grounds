class_name ObjectiveManager
extends Node

const MissionIntentData = preload("res://systems/objectives/mission_intent.gd")
const RescueActionData = preload("res://systems/actions/rescue_action.gd")

signal mission_loaded(mission: MissionDefinition)
signal objective_progress_changed(state: MissionObjectiveState)
signal objective_completed(state: MissionObjectiveState)
signal objective_failed(state: MissionObjectiveState)
signal mission_report_changed

@export var mission: MissionDefinition
var _states: Dictionary[StringName, MissionObjectiveState] = {}
var _turn_manager: TurnManager
var _battle_controller: BattleController
var _grid_manager: GridManager
var total_vips := 0
var extracted_vips := 0
var total_units := 0
var extracted_units := 0
var escaped_enemies := 0
var left_behind := 0

func _ready() -> void:
	if mission: load_mission(mission)

func load_mission(definition: MissionDefinition) -> bool:
	if not _is_valid_definition(definition): return false
	mission = definition
	_states.clear()
	for objective in mission.objectives:
		_states[objective.objective_id] = MissionObjectiveState.new(objective)
	mission_loaded.emit(mission)
	_print_active_objectives()
	return true

func clear_mission() -> void:
	mission = null
	_states.clear()

func begin_tracking(turn_manager: TurnManager, battle_controller: BattleController, grid_manager: GridManager) -> void:
	_turn_manager = turn_manager
	_battle_controller = battle_controller
	_grid_manager = grid_manager
	turn_manager.automatic_annihilation_results = false
	turn_manager.round_started.connect(_on_round_started)
	battle_controller.unit_moved.connect(_on_unit_moved)
	battle_controller.unit_defeated_in_battle.connect(_on_unit_defeated)
	_initialize_extraction_totals()

func get_objective(id: StringName) -> MissionObjectiveState:
	return _states.get(id) as MissionObjectiveState

func get_objectives() -> Array[MissionObjectiveState]:
	var result: Array[MissionObjectiveState] = []
	for definition in mission.objectives if mission else []:
		result.append(_states[definition.objective_id])
	return result

func get_mission_intent(unit: TacticalUnit) -> MissionIntentData:
	if not mission or not is_instance_valid(unit):
		return MissionIntentData.new()

	var rescue := _first_active_objective(MissionObjectiveDefinition.Kind.RESCUE, unit.faction)
	if rescue:
		return _build_intent(rescue, MissionIntentData.Kind.RESCUE, &"", "Approach and secure the rescue target.")

	if should_seek_extraction(unit):
		var extraction := _extraction_for_faction(unit.faction)
		if extraction:
			var zone_id := extraction.definition.zone_id if not extraction.definition.zone_id.is_empty() else &"extract"
			return _build_intent(extraction, MissionIntentData.Kind.EXTRACT, zone_id, "Reach the extraction zone and evacuate.")

	var reach := _first_active_objective(MissionObjectiveDefinition.Kind.REACH, unit.faction)
	if reach:
		return _build_intent(reach, MissionIntentData.Kind.REACH, &"reach", "Reach the mission destination.")
	var protect := _first_active_objective(MissionObjectiveDefinition.Kind.PROTECT, unit.faction)
	if protect:
		return _build_intent(protect, MissionIntentData.Kind.PROTECT, &"", "Keep the protected mission actor alive.")
	var survive := _first_active_objective(MissionObjectiveDefinition.Kind.SURVIVE, unit.faction)
	if survive:
		return _build_intent(survive, MissionIntentData.Kind.SURVIVE, &"", "Remain alive until the survival requirement is complete.")
	var eliminate := _first_active_objective(MissionObjectiveDefinition.Kind.ELIMINATE, unit.faction)
	if eliminate:
		return _build_intent(eliminate, MissionIntentData.Kind.ELIMINATE, &"", "Defeat hostile combatants.")
	return MissionIntentData.new()

func _first_active_objective(kind: MissionObjectiveDefinition.Kind, faction: TacticalUnit.Faction) -> MissionObjectiveState:
	for state in get_objectives():
		if state.is_active() and state.definition.kind == kind and state.definition.is_pursued_by(faction):
			return state
	return null

func _extraction_for_faction(faction: TacticalUnit.Faction) -> MissionObjectiveState:
	for state in get_objectives():
		if state.definition.kind == MissionObjectiveDefinition.Kind.EXTRACT and state.definition.is_pursued_by(faction):
			if state.is_active() or (mission.mission_id == &"prototype_rescue" and state.is_completed()):
				return state
	return null

func _build_intent(state: MissionObjectiveState, kind: MissionIntentData.Kind, zone_id: StringName, reason: String) -> MissionIntentData:
	return MissionIntentData.new(
		kind,
		state.definition.objective_id,
		state.definition.title,
		zone_id,
		state.definition.target_ids,
		state.definition.required,
		reason
	)

func add_progress(id: StringName, amount := 1) -> bool:
	var state := get_objective(id)
	if not state or not state.is_active() or amount <= 0: return false
	state.progress = mini(state.progress + amount, state.definition.target_amount)
	objective_progress_changed.emit(state)
	print_rich("[color=medium_purple][Objectives][/color] PROGRESS — %s %d/%d" % [state.definition.title, state.progress, state.definition.target_amount])
	if state.progress >= state.definition.target_amount: _complete_state(state)
	return true

func complete_objective(id: StringName) -> bool:
	var state := get_objective(id)
	if not state or not state.is_active(): return false
	state.progress = state.definition.target_amount
	objective_progress_changed.emit(state)
	_complete_state(state)
	return true

func fail_objective(id: StringName) -> bool:
	var state := get_objective(id)
	if not state or not state.is_active(): return false
	state.status = MissionObjectiveState.Status.FAILED
	objective_failed.emit(state)
	print_rich("[color=red][Objectives][/color] FAILED — %s" % state.definition.title)
	_evaluate_outcome.call_deferred()
	return true

func are_required_objectives_complete() -> bool:
	var found := false
	for state in get_objectives():
		if state.definition.required:
			found = true
			if not state.is_completed(): return false
	return found

func has_required_objective_failed() -> bool:
	for state in get_objectives():
		if state.definition.required and state.is_failed(): return true
	return false

func can_extract(unit: TacticalUnit) -> bool:
	if not mission or not is_instance_valid(unit) or unit.is_moving or not _turn_manager or not _grid_manager: return false
	if not _turn_manager.player_units.has(unit) and not _turn_manager.allied_units.has(unit) and not _turn_manager.enemy_units.has(unit): return false
	var extraction := _extraction_for_faction(unit.faction)
	if not extraction or not _has_extract_target(unit): return false
	var zone_id := extraction.definition.zone_id if not extraction.definition.zone_id.is_empty() else &"extract"
	if not _grid_manager.map_data.get_objective_zone(zone_id).has(_grid_manager.get_unit_grid(unit)): return false
	if mission.mission_id == &"prototype_survive" and not get_objective(&"survive").is_completed(): return false
	return true

func should_seek_extraction(unit: TacticalUnit) -> bool:
	if not mission or not is_instance_valid(unit): return false
	if not _has_extract_target(unit): return false
	return mission.mission_id != &"prototype_survive" or get_objective(&"survive").is_completed()

func try_extract(unit: TacticalUnit) -> bool:
	if get_tree().paused:
		return false
	if _battle_controller and _battle_controller.is_action_in_progress:
		return false
	if not can_extract(unit):
		return false
	if _battle_controller:
		_battle_controller.is_action_in_progress = true
	var camera_presented := false
	if _battle_controller and not _battle_controller.replay_mode and _battle_controller.action_camera_director:
		var facing := unit.visual_adapter.global_basis.z if is_instance_valid(unit.visual_adapter) else Vector3.FORWARD
		_battle_controller.is_action_in_progress = true
		camera_presented = await _battle_controller.action_camera_director.present(unit, &"extract", unit.global_position + facing * 3.0, unit.stats.current_ap, true)
	if unit.visual_adapter:
		unit.visual_adapter.present_boarding()
		await get_tree().create_timer(0.6, false).timeout
	var succeeded := ExtractAction.new(unit, self).execute()
	if succeeded and _battle_controller:
		_battle_controller.record_replay_action("extract", unit)
	if camera_presented:
		await _battle_controller.action_camera_director.finish_live_presentation(true)
	if _battle_controller:
		_battle_controller.is_action_in_progress = false
	return succeeded

func can_rescue(rescuer: TacticalUnit, target: TacticalUnit) -> bool:
	var rescue := get_objective(&"rescue")
	if not rescue or not rescue.is_active() or not _grid_manager:
		return false
	if not is_instance_valid(rescuer) or not is_instance_valid(target) or rescuer.is_carrying_unit():
		return false
	if not rescue.definition.is_pursued_by(rescuer.faction) or not rescue.definition.target_ids.has(target.get_mission_id()):
		return false
	if target.get_mission_actor_kind() != MissionActor.Kind.RESCUABLE:
		return false
	return CombatRules.can_reach_adjacent(_grid_manager.get_unit_grid(rescuer), _grid_manager.get_unit_grid(target), _grid_manager)

func try_rescue(rescuer: TacticalUnit, target: TacticalUnit) -> bool:
	if get_tree().paused:
		return false
	var target_name := String(target.name) if is_instance_valid(target) else ""
	if not can_rescue(rescuer, target):
		return false
	var camera_presented := false
	if _battle_controller and not _battle_controller.replay_mode and _battle_controller.action_camera_director:
		_battle_controller.is_action_in_progress = true
		camera_presented = await _battle_controller.action_camera_director.present(rescuer, &"rescue", target.global_position, rescuer.stats.current_ap, true)
	var succeeded := RescueActionData.new(rescuer, target, self).execute()
	if succeeded and _battle_controller:
		_battle_controller.record_replay_action("rescue", rescuer, {"target": target_name})
	if camera_presented:
		await get_tree().create_timer(0.3, false).timeout
		await _battle_controller.action_camera_director.finish_live_presentation(true)
	if _battle_controller:
		_battle_controller.is_action_in_progress = false
	return succeeded

func complete_rescue(rescuer: TacticalUnit, target: TacticalUnit) -> bool:
	if not can_rescue(rescuer, target):
		return false
	_grid_manager.unregister_unit_at(_grid_manager.get_unit_grid(target))
	rescuer.carry_unit(target)
	complete_objective(&"rescue")
	return true

func find_mission_actor(target_ids: Array[StringName]) -> TacticalUnit:
	if not _grid_manager:
		return null
	for occupied in _grid_manager.occupancy_map:
		var candidate := _grid_manager.get_unit_at(occupied)
		if is_instance_valid(candidate) and target_ids.has(candidate.get_mission_id()):
			return candidate
	return null

func find_rescue_carrier(faction: TacticalUnit.Faction) -> TacticalUnit:
	if not mission or mission.mission_id != &"prototype_rescue" or not _turn_manager:
		return null
	for candidate in _turn_manager.player_units + _turn_manager.allied_units:
		if is_instance_valid(candidate) and candidate.faction == faction and candidate.is_carrying_unit():
			return candidate
		if is_instance_valid(candidate) and faction in [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ALLY] \
			and candidate.faction in [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ALLY] and candidate.is_carrying_unit():
			return candidate
	return null

func complete_extraction(unit: TacticalUnit) -> bool:
	if not can_extract(unit): return false
	if unit.faction == TacticalUnit.Faction.ENEMY:
		escaped_enemies += 1
		add_progress(&"enemy_escape")
		fail_objective(&"stop_enemy_evacuation")
		mission_report_changed.emit()
		_battle_controller.extract_unit(unit)
		return true
	if unit.is_carrying_unit():
		_record_vip_extraction(unit.carried_unit)
		unit.carried_unit.queue_free()
	if unit.mission_actor.is_vip():
		_record_vip_extraction(unit)
	else:
		extracted_units += 1
		var squad := get_objective(&"extract_units")
		if squad and squad.is_active(): add_progress(&"extract_units")
	mission_report_changed.emit()
	_battle_controller.extract_unit(unit)
	_evaluate_outcome.call_deferred()
	return true

func can_end_mission_early() -> bool:
	return mission and mission.mission_id in [&"prototype_extract", &"prototype_rescue"] and extracted_units + extracted_vips > 0 and _all_vip_objectives_complete() and _turn_manager.battle_result == TurnManager.BattleResult.ONGOING

func get_units_left_behind() -> int:
	return _turn_manager.player_units.size() + _turn_manager.allied_units.size() if _turn_manager else 0

func end_mission_early() -> bool:
	if get_tree().paused:
		return false
	if not can_end_mission_early(): return false
	if _battle_controller and _battle_controller.is_action_in_progress: return false
	# Departure stores its pre-action fingerprint; playback validates it before
	# applying this terminal command, then checks the final battle result.
	_battle_controller.record_replay_action("depart", null)
	left_behind = get_units_left_behind()
	_turn_manager.finish_battle(TurnManager.BattleResult.VICTORY)
	mission_report_changed.emit()
	return true

func get_result_report() -> String:
	if mission and mission.mission_id == &"prototype_enemy_evacuation":
		return "Enemies escaped %d/%d" % [escaped_enemies, get_objective(&"enemy_escape").definition.target_amount]
	var report := "VIPs extracted %d/%d | Units extracted %d/%d" % [extracted_vips, total_vips, extracted_units, total_units]
	return report + (" | Left behind %d" % left_behind if left_behind > 0 else "")

func _initialize_extraction_totals() -> void:
	for unit in _turn_manager.player_units + _turn_manager.allied_units:
		if unit.mission_actor.is_vip(): total_vips += 1
		else: total_units += 1
	if mission.mission_id == &"prototype_rescue": total_vips += 1
	var squad := get_objective(&"extract_units")
	if squad: squad.definition.target_amount = maxi(1, total_units)
	mission_report_changed.emit()

func _on_unit_defeated(unit: TacticalUnit) -> void:
	for state in get_objectives():
		if not state.is_active(): continue
		if state.definition.kind == MissionObjectiveDefinition.Kind.ELIMINATE and unit.faction == TacticalUnit.Faction.ENEMY:
			add_progress(state.definition.objective_id)
		elif state.definition.kind in [MissionObjectiveDefinition.Kind.PROTECT, MissionObjectiveDefinition.Kind.RESCUE, MissionObjectiveDefinition.Kind.EXTRACT] and state.definition.target_ids.has(unit.get_mission_id()):
			fail_objective(state.definition.objective_id)
	if unit.faction in [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ALLY] and not unit.mission_actor.is_vip():
		total_units = maxi(extracted_units, total_units - 1)
		var squad := get_objective(&"extract_units")
		if squad and squad.is_active():
			squad.definition.target_amount = maxi(1, total_units)
			if squad.progress >= squad.definition.target_amount:
				_complete_state(squad)
	mission_report_changed.emit()
	_evaluate_outcome.call_deferred()

func _on_round_started(round_number: int) -> void:
	if round_number > 1 and get_objective(&"survive"): add_progress(&"survive")

func _on_unit_moved(unit: TacticalUnit, _from: Vector3i, to: Vector3i) -> void:
	var reach := get_objective(&"reach")
	if reach and reach.is_active() and unit.faction in [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ALLY] and _grid_manager.map_data.get_objective_zone(&"reach").has(to):
		complete_objective(&"reach")
	var rescue := get_objective(&"rescue")
	if rescue and rescue.is_active() and rescue.definition.is_pursued_by(unit.faction):
		var target := _adjacent_target(to, rescue.definition.target_ids)
		# This is a consequence of the movement command, so the enclosing move
		# recording captures the resulting carried actor and objective progress.
		# Recording a second nested rescue here would place it before the move.
		if target: complete_rescue(unit, target)

func _adjacent_target(cell: Vector3i, ids: Array[StringName]) -> TacticalUnit:
	for occupied in _grid_manager.occupancy_map:
		var target := _grid_manager.get_unit_at(occupied)
		if is_instance_valid(target) and ids.has(target.get_mission_id()) and CombatRules.can_reach_adjacent(cell, occupied, _grid_manager): return target
	return null

func _has_extract_target(unit: TacticalUnit) -> bool:
	var rescue := get_objective(&"rescue")
	if mission.mission_id == &"prototype_rescue" and rescue and rescue.is_completed():
		return unit.faction in [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ALLY]
	for state in get_objectives():
		if not state.is_active() or state.definition.kind != MissionObjectiveDefinition.Kind.EXTRACT or not state.definition.is_pursued_by(unit.faction): continue
		if _objective_targets_unit(state, unit): return true
	return false

func _objective_targets_unit(state: MissionObjectiveState, unit: TacticalUnit) -> bool:
	if state.definition.target_ids.is_empty() or state.definition.target_ids.has(unit.get_mission_id()): return true
	return unit.is_carrying_unit() and state.definition.target_ids.has(unit.carried_unit.get_mission_id())

func _record_vip_extraction(unit: TacticalUnit) -> void:
	extracted_vips += 1
	for state in get_objectives():
		if state.is_active() and state.definition.kind == MissionObjectiveDefinition.Kind.EXTRACT and state.definition.target_ids.has(unit.get_mission_id()): add_progress(state.definition.objective_id)

func _complete_state(state: MissionObjectiveState) -> void:
	state.status = MissionObjectiveState.Status.COMPLETED
	objective_completed.emit(state)
	print_rich("[color=green][Objectives][/color] COMPLETED — %s" % state.definition.title)
	if state.definition.kind == MissionObjectiveDefinition.Kind.ELIMINATE:
		var protect := get_objective(&"protect")
		if protect and protect.is_active(): complete_objective(&"protect")
	_evaluate_outcome.call_deferred()

func _evaluate_outcome() -> void:
	if get_tree().paused:
		await get_tree().create_timer(0.0, false).timeout
	if not _turn_manager or _turn_manager.battle_result != TurnManager.BattleResult.ONGOING: return
	if has_required_objective_failed():
		_turn_manager.finish_battle(TurnManager.BattleResult.DEFEAT)
		return
	if mission.mission_id == &"prototype_extract" and extracted_units >= total_units and _all_vip_objectives_complete():
		_turn_manager.finish_battle(TurnManager.BattleResult.VICTORY)
		return
	if are_required_objectives_complete():
		if mission.mission_id == &"prototype_rescue" and extracted_units < total_units:
			return
		if mission.mission_id != &"prototype_extract" or extracted_units >= total_units:
			_turn_manager.finish_battle(TurnManager.BattleResult.VICTORY)
			return
	if _turn_manager.player_units.is_empty() and not can_end_mission_early():
		_turn_manager.finish_battle(TurnManager.BattleResult.DEFEAT)

func _all_vip_objectives_complete() -> bool:
	for state in get_objectives():
		if state.definition.kind == MissionObjectiveDefinition.Kind.EXTRACT and not state.definition.target_ids.is_empty() and not state.is_completed(): return false
	return true

func _is_valid_definition(candidate: MissionDefinition) -> bool:
	if not candidate or candidate.mission_id.is_empty(): return false
	var ids: Dictionary[StringName, bool] = {}
	for objective in candidate.objectives:
		if not objective or objective.objective_id.is_empty() or objective.target_amount < 1 or ids.has(objective.objective_id): return false
		ids[objective.objective_id] = true
	return true

func _print_active_objectives() -> void:
	var labels: Array[String] = []
	for state in get_objectives(): labels.append("%s [%s, %s, 0/%d]" % [state.definition.title, MissionObjectiveDefinition.Kind.keys()[state.definition.kind], "required" if state.definition.required else "optional", state.definition.target_amount])
	print_rich("[color=medium_purple][Objectives][/color] ACTIVE — %s: %s" % [mission.title, "; ".join(labels)])
