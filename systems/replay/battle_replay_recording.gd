class_name BattleReplayRecording
extends RefCounted

const BattlefieldCatalogData := preload("res://systems/generation/battlefield_catalog.gd")
const CURRENT_SCHEMA_VERSION := 3
const LEGACY_SCHEMA_VERSION := 2
const SIMULATION_VERSION := "prototype-1.5-action-pipeline"

var schema_version := CURRENT_SCHEMA_VERSION
var simulation_version := SIMULATION_VERSION
var configuration: Dictionary = {}
## Read old document fields only to reject retired recordings explicitly.
## Generator 1 replay data and simulation semantics are unchanged.
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
	if int(configuration.get("battlefield_preset", 0)) != 0 or not battlefield_document.is_empty():
		return "Generator 2 is quarantined; open this recording with the local archived project"
	var battlefield_id := StringName(configuration.get("battlefield_id", &""))
	if BattlefieldCatalogData.uses_population(battlefield_id) \
	and not configuration.get("content_manifest", {}).has("plot_id"):
		return "Replay is missing the recorded plot and parcel choices"
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

func save_json(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dictionary(), "\t", false))
	file.flush()
	return file.get_error()

static func load_json(path: String) -> BattleReplayRecording:
	var replay := BattleReplayRecording.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		replay.schema_version = -1
		replay.validation_error = "Could not open replay: %s" % error_string(FileAccess.get_open_error())
		return replay
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		replay.validation_error = "Invalid replay JSON on line %d. %s" % [parser.get_error_line(), parser.get_error_message()]
		return replay
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		replay.schema_version = -1
		replay.validation_error = "Replay JSON root must be an object"
		return replay
	replay.validation_error = _disk_shape_error(parsed)
	if not replay.validation_error.is_empty():
		return replay
	return from_dictionary(parsed)

## Files selected by a player can contain arbitrary JSON. Guard the nested
## shapes before the existing replay decoder and battle validation run.
static func _disk_shape_error(data: Dictionary) -> String:
	var config: Variant = data.get("battle_configuration", data.get("configuration"))
	if not config is Dictionary or config.is_empty():
		return "Replay has no valid battle_configuration object"
	if not _scalar_fields(data, ["schema_version", "expected_result"], TYPE_INT):
		return "Replay schema_version and expected_result must be integers"
	if not _scalar_fields(config, ["player_count", "enemy_count", "ally_count", "seed", "battlefield_preset", "vip_behavior", "difficulty", "player_commander", "enemy_commander"], TYPE_INT) \
	or not _scalar_fields(config, ["battlefield_id"], TYPE_STRING):
		return "Replay battle_configuration has invalid counts, identifiers or settings"
	if not _coordinate(config.get("map_size", [32, 24]), 2):
		return "Replay battle_configuration.map_size must contain two integers"
	var manifest: Variant = config.get("content_manifest", {})
	if not manifest is Dictionary or not _object_array(manifest.get("placements", [])):
		return "Replay content_manifest must contain a list of placement objects"
	if not _coordinate(manifest.get("map_size", [0, 0]), 2):
		return "Replay content_manifest.map_size must contain two integers"
	for placement: Dictionary in manifest.get("placements", []):
		if not _coordinate(placement.get("origin", [0, 0, 0]), 3) or not _object_array(placement.get("population", [])):
			return "Replay placement has a malformed origin or population list"
		if not _scalar_fields(placement, ["slot_id", "parcel_id"], TYPE_STRING) or not _scalar_fields(placement, ["parcel_revision", "rotation"], TYPE_INT):
			return "Replay placement has an invalid identity, revision or rotation"
	var mission: Variant = config.get("mission")
	if mission != null:
		if not mission is Dictionary or not _object_array(mission.get("objectives", [])) or not _object_array(mission.get("terminals", [])):
			return "Replay mission must contain objective and terminal objects"
		for objective: Dictionary in mission.get("objectives", []):
			if not objective.get("target_ids", []) is Array:
				return "Replay mission objective target_ids must be a list"
		for terminal: Dictionary in mission.get("terminals", []):
			if not _coordinate(terminal.get("grid_position", [-1, -1, -1]), 3):
				return "Replay mission terminal grid_position must contain three integers"
	var records: Variant = data.get("ordered_records", data.get("actions", []))
	if not _object_array(records):
		return "Replay ordered_records must contain action objects"
	for index in records.size():
		var record: Dictionary = records[index]
		for field in ["kind", "actor", "expected_state"]:
			if not record.get(field) is String:
				return "Replay action %d field %s must be text" % [index, field]
		var request: Variant = record.get("request", {})
		if not request is Dictionary or not record.get("resolved", {}) is Dictionary:
			return "Replay action %d request and resolved result must be objects" % index
		if not _scalar_fields(record, ["record_index", "schema_version", "base_revision", "committed_revision"], TYPE_INT) \
		or not _scalar_fields(request, ["schema_version", "expected_revision", "source"], TYPE_INT) \
		or not _scalar_fields(request, ["kind", "actor_id", "target_id"], TYPE_STRING):
			return "Replay action %d has invalid revisions or identifiers" % index
		if not request.get("details", {}) is Dictionary or (request.has("destination") and not _coordinate(request.destination, 3)):
			return "Replay action %d has a malformed request" % index
	return ""

static func _object_array(value: Variant) -> bool:
	return value is Array and value.all(func(item): return item is Dictionary)

static func _coordinate(value: Variant, length: int) -> bool:
	return value is Array and value.size() == length and value.all(_is_integer)

static func _is_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floorf(float(value))

static func _scalar_fields(data: Dictionary, fields: Array, type: int) -> bool:
	for field in fields:
		if not data.has(field):
			continue
		var value: Variant = data[field]
		if not (_is_integer(value) if type == TYPE_INT else typeof(value) == type):
			return false
	return true

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
		"refinery_2": bool(source.get("refinery_2", false)),
		"loading_yard": bool(source.get("loading_yard", false)),
		"battlefield_id": String(source.get("battlefield_id", BattlefieldCatalogData.GENERATED_COVER)),
		"content_manifest": _manifest_to_data(source.get("content_manifest", {})),
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
		"refinery_2": bool(data.get("refinery_2", false)),
		"loading_yard": bool(data.get("loading_yard", false)),
		"battlefield_id": String(data.get("battlefield_id", BattlefieldCatalogData.GENERATED_COVER)),
		"content_manifest": _manifest_from_data(data.get("content_manifest", {})),
	}

static func _manifest_to_data(manifest: Dictionary) -> Dictionary:
	if manifest.is_empty(): return {}
	var size: Vector2i = manifest.get("map_size", Vector2i.ZERO)
	var placements: Array[Dictionary] = []
	for placement: Dictionary in manifest.get("placements", []):
		var origin: Vector3i = placement.get("origin", Vector3i.ZERO)
		var population: Array[Dictionary] = []
		for choice: Dictionary in placement.get("population", []):
			population.append({"region_id": String(choice.get("region_id", "")), "socket_id": String(choice.get("socket_id", "")), "asset_id": String(choice.get("asset_id", ""))})
			if choice.has("yaw_turns"):
				population[-1].yaw_turns = choice.yaw_turns
		placements.append({"slot_id": String(placement.get("slot_id", "")), "parcel_id": String(placement.get("parcel_id", "")), "parcel_revision": int(placement.get("parcel_revision", 0)), "origin": [origin.x, origin.y, origin.z], "rotation": int(placement.get("rotation", 0)), "population": population})
	var result := {"schema": int(manifest.get("schema", 1)), "plot_id": String(manifest.get("plot_id", "")), "plot_revision": int(manifest.get("plot_revision", 0)), "map_size": [size.x, size.y], "seed": int(manifest.get("seed", 0)), "population_enabled": bool(manifest.get("population_enabled", true)), "placements": placements}
	if manifest.has("compiler_revision"):
		result.compiler_revision = manifest.compiler_revision
	return result

static func _manifest_from_data(manifest: Variant) -> Dictionary:
	if not manifest is Dictionary or manifest.is_empty(): return {}
	var raw_size: Array = manifest.get("map_size", [0, 0])
	var placements: Array[Dictionary] = []
	for placement: Dictionary in manifest.get("placements", []):
		var raw_origin: Array = placement.get("origin", [0, 0, 0])
		var population: Array[Dictionary] = []
		for choice: Dictionary in placement.get("population", []):
			population.append({"region_id": StringName(choice.get("region_id", "")), "socket_id": StringName(choice.get("socket_id", "")), "asset_id": String(choice.get("asset_id", ""))})
			if choice.has("yaw_turns"):
				var yaw: Variant = choice.yaw_turns
				population[-1].yaw_turns = int(yaw) if (yaw is int or yaw is float) and float(yaw) == int(yaw) else yaw
		placements.append({"slot_id": StringName(placement.get("slot_id", "")), "parcel_id": StringName(placement.get("parcel_id", "")), "parcel_revision": int(placement.get("parcel_revision", 0)), "origin": Vector3i(int(raw_origin[0]), int(raw_origin[1]), int(raw_origin[2])), "rotation": int(placement.get("rotation", 0)), "population": population})
	var result := {"schema": int(manifest.get("schema", 1)), "plot_id": StringName(manifest.get("plot_id", "")), "plot_revision": int(manifest.get("plot_revision", 0)), "map_size": Vector2i(int(raw_size[0]), int(raw_size[1])), "seed": int(manifest.get("seed", 0)), "population_enabled": bool(manifest.get("population_enabled", true)), "placements": placements, "errors": []}
	if manifest.has("compiler_revision"):
		var revision: Variant = manifest.compiler_revision
		result.compiler_revision = int(revision) if revision is float and revision == int(revision) else revision
	return result

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
	var terminals: Array[Dictionary] = []
	for terminal in mission.terminals:
		terminals.append({"terminal_id":String(terminal.terminal_id),"objective_id":String(terminal.objective_id),"grid_position":[terminal.grid_position.x,terminal.grid_position.y,terminal.grid_position.z],"initially_activated":terminal.initially_activated})
	return {"mission_id": String(mission.mission_id), "title": mission.title, "objectives": objectives, "terminals":terminals}

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
	for raw in data.get("terminals", []):
		if not raw is Dictionary: continue
		var terminal := MissionTerminalDefinition.new()
		terminal.terminal_id = StringName(raw.get("terminal_id", "terminal"))
		terminal.objective_id = StringName(raw.get("objective_id", ""))
		var position_data: Array = raw.get("grid_position", [-1,-1,-1])
		if position_data.size() == 3: terminal.grid_position = Vector3i(int(position_data[0]),int(position_data[1]),int(position_data[2]))
		terminal.initially_activated = bool(raw.get("initially_activated", false))
		mission.terminals.append(terminal)
	return mission
