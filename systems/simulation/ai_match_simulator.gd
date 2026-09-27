class_name AIMatchSimulator
extends Node

const BATTLE_SCENE := preload("res://levels/prototype_map/prototype_map.tscn")

var _decision_count := 0
var _decision_records: Array[Dictionary] = []

func run_match(config: Dictionary) -> AIMatchSimulationResult:
	var result := AIMatchSimulationResult.new()
	result.seed = int(config.get("seed", 1))
	result.difficulty = config.get("difficulty", AIDifficultyPolicy.Tier.NORMAL)
	var mission_kind: MissionObjectiveDefinition.Kind = config.get("mission_kind", MissionObjectiveDefinition.Kind.ELIMINATE)
	var player_count := clampi(int(config.get("player_count", 2)), 1, 5)
	var enemy_count := clampi(int(config.get("enemy_count", 2)), 1, 5)
	var ally_count := clampi(int(config.get("ally_count", 0)), 0, 5)
	var include_vip: bool = config.get("include_vip", mission_kind == MissionObjectiveDefinition.Kind.PROTECT)
	var generated_map: bool = config.get("generated_map", true)
	result.configuration = {
		"seed": result.seed,
		"mission_kind": MissionObjectiveDefinition.Kind.keys()[mission_kind],
		"player_count": player_count,
		"enemy_count": enemy_count,
		"ally_count": ally_count,
		"include_vip": include_vip,
		"generated_map": generated_map,
		"map_size": _serializable_value(config.get("map_size", Vector2i(32, 24))),
		"refinery": bool(config.get("refinery", false)),
		"difficulty": AIDifficultyPolicy.Tier.keys()[result.difficulty],
		"maximum_rounds": maxi(1, int(config.get("maximum_rounds", 20))),
		"stall_seconds": maxf(1.0, float(config.get("stall_seconds", 6.0))),
		"timeout_seconds": maxf(1.0, float(config.get("timeout_seconds", 30.0))),
	}
	var mission := MissionCatalog.create_mission(mission_kind, enemy_count, include_vip)
	result.mission_id = mission.mission_id
	result.mission_title = mission.title
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure(
		player_count, enemy_count, generated_map, result.seed, ally_count,
		config.get("map_size", Vector2i(32, 24)), include_vip,
		config.get("vip_behavior", MissionActor.VIPBehavior.FOLLOW_ESCORT),
		mission, result.difficulty, config.get("refinery", false)
	)
	add_child(level)
	var setup_deadline := Time.get_ticks_msec() + 10000
	while level.turn_manager.current_round == 0 and Time.get_ticks_msec() < setup_deadline:
		await get_tree().process_frame
	if level.turn_manager.current_round == 0 or not level.battle_controller.last_map_validation or not level.battle_controller.last_map_validation.is_valid():
		result.reason = "Battle scene did not initialize a valid map."
		result.map_source = level.battle_controller.grid_manager.map_data.source_kind
		result.map_size = level.battle_controller.grid_manager.map_data.map_size
		if level.battle_controller.last_map_validation:
			for issue in level.battle_controller.last_map_validation.errors:
				result.validation_errors.append(issue.describe())
		await _dispose_level(level)
		return result

	result.quality = level.battle_controller.last_map_quality
	result.map_source = level.battle_controller.grid_manager.map_data.source_kind
	result.map_size = level.battle_controller.grid_manager.map_data.map_size
	result.traversal_link_count = level.battle_controller.grid_manager.map_data.traversal_links.size()
	for cell: MapCellData in level.battle_controller.grid_manager.map_data.cells.values():
		result.elevated_cell_count += int(cell.grid_position.y != 0)
	_decision_count = 0
	_decision_records.clear()
	level.battle_controller.ai_decision_recorded.connect(_on_ai_decision)
	level.battle_controller.set_debug_player_ai(true)
	var started_at := Time.get_ticks_msec()
	var last_progress_at := started_at
	var previous_signature := _state_signature(level)
	var maximum_rounds := maxi(1, int(config.get("maximum_rounds", 20)))
	var stall_seconds := maxf(1.0, float(config.get("stall_seconds", 6.0)))
	var timeout_seconds := maxf(stall_seconds, float(config.get("timeout_seconds", 30.0)))
	while level.turn_manager.battle_result == TurnManager.BattleResult.ONGOING:
		await get_tree().create_timer(0.05).timeout
		var now := Time.get_ticks_msec()
		var signature := _state_signature(level)
		if signature != previous_signature:
			previous_signature = signature
			last_progress_at = now
		if level.turn_manager.current_round > maximum_rounds:
			result.status = AIMatchSimulationResult.Status.ROUND_LIMIT
			result.reason = "Exceeded %d rounds. State: %s" % [maximum_rounds, signature]
			break
		if float(now - last_progress_at) / 1000.0 >= stall_seconds:
			result.status = AIMatchSimulationResult.Status.STALLED
			result.reason = "No authoritative state change for %.1f seconds. State: %s" % [stall_seconds, signature]
			break
		if float(now - started_at) / 1000.0 >= timeout_seconds:
			result.status = AIMatchSimulationResult.Status.TIMEOUT
			result.reason = "Exceeded %.1f seconds." % timeout_seconds
			break

	result.elapsed_seconds = float(Time.get_ticks_msec() - started_at) / 1000.0
	result.rounds = level.turn_manager.current_round
	result.decision_count = _decision_count
	result.decision_records.assign(_decision_records)
	result.final_state = _state_signature(level)
	result.battle_result = level.turn_manager.battle_result
	if result.battle_result != TurnManager.BattleResult.ONGOING:
		result.status = AIMatchSimulationResult.Status.COMPLETED
	print("[AISim] %s" % result.summary())
	await _dispose_level(level)
	return result

func _on_ai_decision(record: Dictionary) -> void:
	_decision_count += 1
	var serialized: Variant = _serializable_value(record)
	if serialized is Dictionary:
		_decision_records.append(serialized)

func _serializable_value(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			result[str(key)] = _serializable_value(value[key])
		return result
	if value is Array:
		var result := []
		for item in value:
			result.append(_serializable_value(item))
		return result
	if value is Object:
		return value.name if value is Node else value.get_class()
	if value is Vector2i:
		return [value.x, value.y]
	if value is Vector3i:
		return [value.x, value.y, value.z]
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is StringName:
		return String(value)
	return value

func _state_signature(level: BattleLevel) -> String:
	var parts: Array[String] = [
		str(level.turn_manager.current_round),
		str(level.turn_manager.current_phase),
		str(level.turn_manager.active_unit.name if is_instance_valid(level.turn_manager.active_unit) else "none"),
	]
	for unit in level.turn_manager.player_units + level.turn_manager.allied_units + level.turn_manager.enemy_units:
		if is_instance_valid(unit) and unit.stats:
			parts.append("%s:%s:%d:%d" % [unit.name, level.battle_controller.grid_manager.get_unit_grid(unit), unit.stats.current_hp, unit.stats.current_ap])
	for state in level.objective_manager.get_objectives():
		parts.append("%s:%d:%d" % [state.definition.objective_id, state.status, state.progress])
	return "|".join(parts)

func _dispose_level(level: BattleLevel) -> void:
	if is_instance_valid(level):
		level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
