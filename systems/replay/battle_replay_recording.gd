class_name BattleReplayRecording
extends RefCounted

const CURRENT_SCHEMA_VERSION := 3
const LEGACY_SCHEMA_VERSION := 2
const SIMULATION_VERSION := "prototype-1.5-action-pipeline"

var schema_version := CURRENT_SCHEMA_VERSION
var simulation_version := SIMULATION_VERSION
var configuration: Dictionary = {}
## Generation 2.0 replays preserve accepted construction intent rather than
## assuming that a seed can reproduce the same content forever. Legacy replay
## envelopes intentionally leave this empty.
var battlefield_document: Dictionary = {}
var battlefield_document_signature := ""
var initial_state_fingerprint := ""
var actions: Array[Dictionary] = []
var expected_result := TurnManager.BattleResult.ONGOING
var validation_error := ""

func append_action(record: Dictionary) -> void:
	actions.append(record.duplicate(true))

func is_playable() -> bool:
	return validation_message().is_empty()

func validation_message() -> String:
	if not validation_error.is_empty():
		return validation_error
	if schema_version not in [LEGACY_SCHEMA_VERSION, CURRENT_SCHEMA_VERSION]:
		return "Unsupported replay schema %d; this build supports %d and legacy %d" % [schema_version, CURRENT_SCHEMA_VERSION, LEGACY_SCHEMA_VERSION]
	if configuration.is_empty(): return "Replay has no battle_configuration"
	if int(configuration.get("battlefield_preset", BattleConfiguration.BattlefieldPreset.LEGACY)) == BattleConfiguration.BattlefieldPreset.GENERATION_2_INDUSTRIAL:
		if battlefield_document.is_empty(): return "Generation 2.0 replay has no battlefield_layout_document"
		var document := BattlefieldLayoutDocument.from_dictionary(battlefield_document)
		var document_failures := document.validate()
		if not document_failures.is_empty():
			return "Generation 2.0 replay battlefield document is invalid: %s" % document_failures[0].get("message", "unknown document failure")
		if battlefield_document_signature.is_empty() or stable_battlefield_document_signature(battlefield_document) != battlefield_document_signature:
			return "Generation 2.0 replay battlefield document signature differs"
	if actions.is_empty(): return "Replay has no ordered_records"
	for index in actions.size():
		var issue := ReplayRecordTools.validate_action_record(actions[index], schema_version)
		if not issue.is_empty(): return "Replay record %d is invalid: %s" % [index, issue]
	return ""

func to_dictionary() -> Dictionary:
	return {
		"schema_version": schema_version,
		"simulation_version": simulation_version,
		"battle_configuration": _configuration_to_data(configuration),
		"battlefield_layout_document": battlefield_document.duplicate(true),
		"battlefield_layout_signature": battlefield_document_signature,
		"generation_seed": int(configuration.get("seed", 1)),
		"initial_state_fingerprint": initial_state_fingerprint,
		"expected_result": int(expected_result),
		"ordered_records": actions.duplicate(true),
	}

static func from_dictionary(data: Dictionary) -> BattleReplayRecording:
	var replay := BattleReplayRecording.new()
	replay.schema_version = int(data.get("schema_version", -1))
	replay.simulation_version = String(data.get("simulation_version", "prototype-1" if replay.schema_version == LEGACY_SCHEMA_VERSION else "unknown"))
	replay.configuration = _configuration_from_data(data.get("battle_configuration", data.get("configuration", {})))
	var encoded_document = data.get("battlefield_layout_document", {})
	if encoded_document is Dictionary: replay.battlefield_document = encoded_document.duplicate(true)
	replay.battlefield_document_signature = String(data.get("battlefield_layout_signature", ""))
	replay.initial_state_fingerprint = String(data.get("initial_state_fingerprint", ""))
	replay.expected_result = int(data.get("expected_result", TurnManager.BattleResult.ONGOING)) as TurnManager.BattleResult
	var records: Array = data.get("ordered_records", data.get("actions", []))
	for record in records:
		if record is Dictionary: replay.actions.append(record.duplicate(true))
	replay.validation_error = replay.validation_message()
	return replay

func capture_battlefield_document(document: BattlefieldLayoutDocument) -> void:
	battlefield_document.clear()
	battlefield_document_signature = ""
	if document == null: return
	# Normalize through the persistence representation once. Godot JSON restores
	# all numbers through Variant's JSON number type, so hashing the in-memory
	# pre-serialization dictionary would reject an otherwise identical reload.
	var normalized = JSON.parse_string(JSON.stringify(document.to_dictionary()))
	if normalized is Dictionary: battlefield_document = normalized
	battlefield_document_signature = stable_battlefield_document_signature(battlefield_document)

static func stable_battlefield_document_signature(encoded: Dictionary) -> String:
	var normalized = JSON.parse_string(JSON.stringify(encoded))
	return JSON.stringify(normalized if normalized is Dictionary else encoded).sha256_text()

func save_json(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		validation_error = "Could not open replay for writing: %s" % error_string(FileAccess.get_open_error())
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dictionary(), "\t", false))
	return OK

static func load_json(path: String) -> BattleReplayRecording:
	var replay := BattleReplayRecording.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		replay.schema_version = -1
		replay.validation_error = "Could not open replay: %s" % error_string(FileAccess.get_open_error())
		return replay
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		replay.schema_version = -1
		replay.validation_error = "Replay JSON root must be an object"
		return replay
	return from_dictionary(parsed)

static func _configuration_to_data(source: Dictionary) -> Dictionary:
	var size: Vector2i = source.get("map_size", Vector2i(32, 24))
	return {
		"player_count": int(source.get("player_count", 2)),
		"enemy_count": int(source.get("enemy_count", 2)),
		"ally_count": int(source.get("ally_count", 0)),
		"player_archetypes": _string_array(source.get("player_archetypes", [])),
		"enemy_archetypes": _string_array(source.get("enemy_archetypes", [])),
		"ally_archetypes": _string_array(source.get("ally_archetypes", [])),
		# A missing flag identifies a configuration authored before SP existed.
		"supply_points_enabled": bool(source.get("supply_points_enabled", false)),
		"aim_enabled": bool(source.get("aim_enabled", false)),
		"shield_enabled": bool(source.get("shield_enabled", false)),
		"overwatch_enabled": bool(source.get("overwatch_enabled", false)),
		"conditions_enabled": bool(source.get("conditions_enabled", false)),
		"tactical_tempo_enabled": bool(source.get("tactical_tempo_enabled", false)),
		"generated_map": bool(source.get("generated_map", false)),
		"battlefield_preset": int(source.get("battlefield_preset", BattleConfiguration.BattlefieldPreset.LEGACY)),
		"seed": int(source.get("seed", 1)),
		"map_size": [size.x, size.y],
		"include_vip": bool(source.get("include_vip", false)),
		"vip_behavior": int(source.get("vip_behavior", MissionActor.VIPBehavior.PLAYER_CONTROLLED)),
		"mission": _mission_to_data(source.get("mission")),
		"difficulty": int(source.get("difficulty", AIDifficultyPolicy.Tier.NORMAL)),
		"player_commander": int(source.get("player_commander", AICommanderPolicy.Profile.DEFAULT)),
		"enemy_commander": int(source.get("enemy_commander", AICommanderPolicy.Profile.DEFAULT)),
		"refinery": bool(source.get("refinery", false)),
		"industrial_warehouse": bool(source.get("industrial_warehouse", false)),
	}

static func _configuration_from_data(data: Dictionary) -> Dictionary:
	if data.get("map_size") is Vector2i:
		return data.duplicate(true)
	var raw_size: Array = data.get("map_size", [32, 24])
	var mission_data = data.get("mission")
	return {
		"player_count": int(data.get("player_count", 2)),
		"enemy_count": int(data.get("enemy_count", 2)),
		"ally_count": int(data.get("ally_count", 0)),
		"player_archetypes": _name_array(data.get("player_archetypes", [])),
		"enemy_archetypes": _name_array(data.get("enemy_archetypes", [])),
		"ally_archetypes": _name_array(data.get("ally_archetypes", [])),
		"supply_points_enabled": bool(data.get("supply_points_enabled", false)),
		"aim_enabled": bool(data.get("aim_enabled", false)),
		"shield_enabled": bool(data.get("shield_enabled", false)),
		"overwatch_enabled": bool(data.get("overwatch_enabled", false)),
		"conditions_enabled": bool(data.get("conditions_enabled", false)),
		"tactical_tempo_enabled": bool(data.get("tactical_tempo_enabled", false)),
		"generated_map": bool(data.get("generated_map", false)),
		"battlefield_preset": int(data.get("battlefield_preset", BattleConfiguration.BattlefieldPreset.LEGACY)),
		"seed": int(data.get("seed", 1)),
		"map_size": Vector2i(int(raw_size[0]), int(raw_size[1])) if raw_size.size() == 2 else Vector2i(32, 24),
		"include_vip": bool(data.get("include_vip", false)),
		"vip_behavior": int(data.get("vip_behavior", MissionActor.VIPBehavior.PLAYER_CONTROLLED)),
		"mission": _mission_from_data(mission_data) if mission_data is Dictionary else mission_data,
		"difficulty": int(data.get("difficulty", AIDifficultyPolicy.Tier.NORMAL)),
		"player_commander": int(data.get("player_commander", AICommanderPolicy.Profile.DEFAULT)),
		"enemy_commander": int(data.get("enemy_commander", AICommanderPolicy.Profile.DEFAULT)),
		"refinery": bool(data.get("refinery", false)),
		"industrial_warehouse": bool(data.get("industrial_warehouse", false)),
	}

static func _string_array(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if values is Array:
		for value in values: result.append(String(value))
	return result

static func _name_array(values: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if values is Array:
		for value in values: result.append(StringName(value))
	return result

static func _mission_to_data(mission: MissionDefinition) -> Variant:
	if mission == null: return null
	var objectives: Array[Dictionary] = []
	for objective in mission.objectives:
		objectives.append({
			"objective_id": String(objective.objective_id), "kind": int(objective.kind),
			"title": objective.title, "description": objective.description,
			"required": objective.required, "target_amount": objective.target_amount,
			"target_ids": Array(objective.target_ids).map(func(value): return String(value)),
			"zone_id": String(objective.zone_id), "pursuing_factions": objective.pursuing_factions,
		})
	return {"mission_id": String(mission.mission_id), "title": mission.title, "objectives": objectives}

static func _mission_from_data(data: Dictionary) -> MissionDefinition:
	var mission := MissionDefinition.new()
	mission.mission_id = StringName(data.get("mission_id", ""))
	mission.title = String(data.get("title", "Mission"))
	for raw in data.get("objectives", []):
		if not raw is Dictionary: continue
		var objective := MissionObjectiveDefinition.new()
		objective.objective_id = StringName(raw.get("objective_id", ""))
		objective.kind = int(raw.get("kind", 0)) as MissionObjectiveDefinition.Kind
		objective.title = String(raw.get("title", "Objective"))
		objective.description = String(raw.get("description", ""))
		objective.required = bool(raw.get("required", true))
		objective.target_amount = int(raw.get("target_amount", 1))
		for target in raw.get("target_ids", []): objective.target_ids.append(StringName(target))
		objective.zone_id = StringName(raw.get("zone_id", ""))
		objective.pursuing_factions = int(raw.get("pursuing_factions", 0))
		mission.objectives.append(objective)
	return mission
