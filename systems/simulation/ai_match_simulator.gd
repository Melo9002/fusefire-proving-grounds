class_name AIMatchSimulator
extends Node

const BattleConfigurationData := preload("res://systems/battle_configuration.gd")
const BattlefieldCatalog := preload("res://systems/generation/battlefield_catalog.gd")

const BATTLE_SCENE := preload("res://levels/prototype_map/prototype_map.tscn")

var _decision_count := 0
var _action_outcomes: Array[Dictionary] = []
var _decision_records: Array[Dictionary] = []
var _round_samples: Array[Dictionary] = []

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
		"industrial_warehouse": bool(config.get("industrial_warehouse", false)),
		"refinery_2": bool(config.get("refinery_2", false)),
		"loading_yard": bool(config.get("loading_yard", false)),
		"battlefield_id": String(config.get("battlefield_id", BattlefieldCatalog.GENERATED_COVER)),
		"difficulty": AIDifficultyPolicy.Tier.keys()[result.difficulty],
		"player_commander": AICommanderPolicy.get_label(config.get("player_commander", AICommanderPolicy.Profile.DEFAULT)),
		"enemy_commander": AICommanderPolicy.get_label(config.get("enemy_commander", AICommanderPolicy.Profile.DEFAULT)),
		"maximum_rounds": maxi(1, int(config.get("maximum_rounds", 20))),
		"stall_seconds": maxf(1.0, float(config.get("stall_seconds", 6.0))),
		"timeout_seconds": maxf(1.0, float(config.get("timeout_seconds", 30.0))),
	}
	var mission := MissionCatalog.create_mission(mission_kind, enemy_count, include_vip)
	result.mission_id = mission.mission_id
	result.mission_title = mission.title
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	var battle_config := BattleConfigurationData.new()
	battle_config.player_count = player_count
	battle_config.enemy_count = enemy_count
	battle_config.generated_map = generated_map
	battle_config.battle_seed = result.seed
	battle_config.ally_count = ally_count
	battle_config.map_size = config.get("map_size", Vector2i(32, 24))
	battle_config.include_vip = include_vip
	battle_config.vip_behavior = config.get("vip_behavior", MissionActor.VIPBehavior.FOLLOW_ESCORT)
	battle_config.mission = mission
	battle_config.difficulty = result.difficulty
	battle_config.player_commander = config.get("player_commander", AICommanderPolicy.Profile.DEFAULT)
	battle_config.enemy_commander = config.get("enemy_commander", AICommanderPolicy.Profile.DEFAULT)
	# Optional rosters (archetype IDs per slot). Left out, every unit is Generic as before, and the
	# recorded configuration is unchanged.
	if not config.get("player_archetypes", []).is_empty() or not config.get("enemy_archetypes", []).is_empty():
		var player_roster: Array[StringName] = []
		var enemy_roster: Array[StringName] = []
		for id in config.get("player_archetypes", []): player_roster.append(StringName(id))
		for id in config.get("enemy_archetypes", []): enemy_roster.append(StringName(id))
		battle_config.player_archetypes = TacticalArchetypeCatalog.normalize_ids(player_roster, player_count)
		battle_config.enemy_archetypes = TacticalArchetypeCatalog.normalize_ids(enemy_roster, enemy_count)
		result.configuration["player_archetypes"] = Array(battle_config.player_archetypes).map(func(id): return String(id))
		result.configuration["enemy_archetypes"] = Array(battle_config.enemy_archetypes).map(func(id): return String(id))
	battle_config.select_battlefield(BattlefieldCatalog.id_from_configuration(config, BattlefieldCatalog.SERVICE_DEPOT))
	result.configuration.battlefield_id = String(battle_config.battlefield_id)
	if config.has("content_manifest"):
		battle_config.content_manifest = config.content_manifest.duplicate(true)
		result.configuration.content_manifest = _serializable_value(battle_config.content_manifest)
	level.configure_battle(battle_config)
	result.configuration.map_size = _serializable_value(level.generated_size)
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
	_action_outcomes.clear()
	_round_samples.clear()
	level.battle_controller.ai_decision_recorded.connect(_on_ai_decision)
	level.battle_controller.ai_action_outcome_recorded.connect(func(record: Dictionary): _action_outcomes.append(record.duplicate(true)))
	level.battle_controller.set_debug_player_ai(true)
	var started_at := Time.get_ticks_msec()
	var last_progress_at := started_at
	var previous_signature := _state_signature(level)
	var sampled_round := -1
	var maximum_rounds := maxi(1, int(config.get("maximum_rounds", 20)))
	var stall_seconds := maxf(1.0, float(config.get("stall_seconds", 6.0)))
	var timeout_seconds := maxf(stall_seconds, float(config.get("timeout_seconds", 30.0)))
	while level.turn_manager.battle_result == TurnManager.BattleResult.ONGOING:
		await get_tree().create_timer(0.05).timeout
		var now := Time.get_ticks_msec()
		if level.turn_manager.current_round != sampled_round:
			sampled_round = level.turn_manager.current_round
			_round_samples.append(_round_sample(level, float(now - started_at) / 1000.0))
		var signature := _state_signature(level)
		if signature != previous_signature:
			previous_signature = signature
			last_progress_at = now
		var stop := classify_stop(level.turn_manager.battle_result, level.turn_manager.current_round,
			maximum_rounds, float(now - last_progress_at) / 1000.0, stall_seconds,
			float(now - started_at) / 1000.0, timeout_seconds)
		if not stop.is_empty():
			result.status = stop.status
			result.reason = stop.reason
			break

	result.elapsed_seconds = float(Time.get_ticks_msec() - started_at) / 1000.0
	result.rounds = level.turn_manager.current_round
	result.decision_count = _decision_count
	result.decision_records.assign(_decision_records)
	result.action_outcomes.assign(_action_outcomes)
	_round_samples.append(_round_sample(level, result.elapsed_seconds))
	result.round_samples.assign(_round_samples)
	for outcome in _action_outcomes:
		if outcome.stage == "committed": result.committed_action_count += 1
		else: result.rejected_action_count += 1
	result.final_state = _state_signature(level)
	result.battle_result = level.turn_manager.battle_result
	if result.battle_result != TurnManager.BattleResult.ONGOING:
		result.status = AIMatchSimulationResult.Status.COMPLETED
		result.reason = ""
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

## Passive per-round progress snapshot for baselines; reads state only.
func _round_sample(level: BattleLevel, elapsed: float) -> Dictionary:
	var sides := {"player": 0, "ally": 0, "enemy": 0}
	var alive := {"player": 0, "ally": 0, "enemy": 0}
	for pair in [["player", level.turn_manager.player_units], ["ally", level.turn_manager.allied_units], ["enemy", level.turn_manager.enemy_units]]:
		for unit: TacticalUnit in pair[1]:
			if is_instance_valid(unit) and unit.stats and not unit.stats.is_defeated:
				sides[pair[0]] += unit.stats.current_hp
				alive[pair[0]] += 1
	var objectives: Array[Dictionary] = []
	for state in level.objective_manager.get_objectives():
		objectives.append({"id": String(state.definition.objective_id), "status": state.status, "progress": state.progress})
	return {"round": level.turn_manager.current_round, "elapsed": elapsed, "hp": sides, "alive": alive, "objectives": objectives}

func _dispose_level(level: BattleLevel) -> void:
	if is_instance_valid(level):
		level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

## Terminal state wins over a deadline observed in the same sampling frame.
static func classify_stop(outcome: TurnManager.BattleResult, round_count: int, round_limit: int,
	idle_seconds: float, stall_limit: float, elapsed_seconds: float, timeout_limit: float) -> Dictionary:
	if outcome != TurnManager.BattleResult.ONGOING:
		return {"status": AIMatchSimulationResult.Status.COMPLETED, "reason": ""}
	if round_count > round_limit:
		return {"status": AIMatchSimulationResult.Status.ROUND_LIMIT, "reason": "Exceeded %d rounds." % round_limit}
	if idle_seconds >= stall_limit:
		return {"status": AIMatchSimulationResult.Status.STALLED, "reason": "No authoritative state change for %.1f seconds." % stall_limit}
	if elapsed_seconds >= timeout_limit:
		return {"status": AIMatchSimulationResult.Status.TIMEOUT, "reason": "Exceeded %.1f seconds." % timeout_limit}
	return {}
