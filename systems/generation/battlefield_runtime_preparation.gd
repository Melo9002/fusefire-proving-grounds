class_name BattlefieldRuntimePreparation
extends RefCounted
## Shared validated-document boundary; no gameplay activation.

static func compile_document(document: BattlefieldLayoutDocument, config: BattleConfiguration, cell_size := 1.0, context: EnvironmentResolutionContext = null) -> Dictionary:
	var configuration_failures := config.validate_generation_selection()
	if not configuration_failures.is_empty(): return _failure(configuration_failures, document)
	if document == null:
		return _failure([_diagnostic("MISSING_LAYOUT_DOCUMENT", "battlefield_document", "Document-driven battle preparation requires a unified layout document")])
	if document.map_size() != config.map_size:
		return _failure([_diagnostic("DOCUMENT_MAP_SIZE_MISMATCH", "spatial_layout.map_size", "battle configuration requires %s but the document defines %s" % [config.map_size, document.map_size()])], document)
	if document.provenance.has("composition"):
		var active: String = document.provenance.composition.get("plot", {}).get("active_mission", "")
		var expected := MissionObjectiveDefinition.Kind.INTERACT_TERMINAL if active == "terminal" else MissionObjectiveDefinition.Kind.ELIMINATE
		if config.mission == null or not config.mission.objectives.any(func(objective): return objective.kind == expected):
			return _failure([_diagnostic("DOCUMENT_MISSION_MISMATCH", "mission", "Battle mission does not match the accepted plot's active mission")], document)
	var compiled := BattlefieldLayoutDocumentCompiler.compile(document, cell_size, maxi(5, maxi(config.player_count, maxi(config.enemy_count, config.ally_count))), context)
	if not compiled.ok: return _failure(compiled.errors, compiled.document)
	var data: MapData = compiled.data
	var deployment_failures := _deployment_failures(data, config)
	if not deployment_failures.is_empty(): return _failure(deployment_failures, compiled.document)
	return {
		"ok": true,
		"data": data,
		"document": compiled.document,
		"errors": [],
		"repairs": compiled.repairs,
	}

static func _deployment_failures(data: MapData, config: BattleConfiguration) -> Array[Dictionary]:
	var failures: Array[Dictionary] = []
	var requirements := {
		TacticalUnit.Faction.PLAYER: config.player_count,
		TacticalUnit.Faction.ALLY: config.ally_count,
		TacticalUnit.Faction.ENEMY: config.enemy_count,
	}
	for faction in requirements:
		var available := data.get_spawn_cells(faction).size()
		var required: int = requirements[faction]
		if available < required:
			failures.append(_diagnostic("INSUFFICIENT_DEPLOYMENT", "mission_context.zones", "faction %d requires %d deployment cells but the document compiled %d" % [faction, required, available], str(faction)))
	return failures

static func _failure(errors: Array, document: BattlefieldLayoutDocument = null) -> Dictionary:
	return {"ok": false, "data": null, "document": document, "errors": errors.duplicate(true), "repairs": []}

static func _diagnostic(code: String, field: String, message: String, source_reference := "") -> Dictionary:
	return {"code": code, "field": field, "reference": source_reference, "message": message}
