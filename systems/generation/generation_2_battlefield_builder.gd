class_name Generation2BattlefieldBuilder
extends RefCounted
## Narrow runtime boundary shared with the Map Editor document pipeline.
## It prepares validated tactical data; BattleLevel remains responsible for
## presentation, combatant spawning, and activating the playable battle.

static func build(config: BattleConfiguration, cell_size := 1.0) -> Dictionary:
	var configuration_failures := config.validate_generation_selection()
	if not configuration_failures.is_empty(): return _failure(configuration_failures)
	var spawn_capacity := maxi(5, maxi(config.player_count, maxi(config.enemy_count, config.ally_count)))
	var generated := FlatMapGenerator.generate(
		config.map_size.x,
		config.map_size.y,
		cell_size,
		config.battle_seed,
		spawn_capacity
	)
	var layout := CoherentEnvironmentAssembler.apply(generated, cell_size, config.battle_seed, BattleConfiguration.GENERATION_2_ENVIRONMENT)
	if not layout.errors.is_empty():
		var assembly_failures: Array[Dictionary] = []
		for message in layout.errors: assembly_failures.append(_diagnostic("COHERENT_ASSEMBLY_FAILED", "generation", message))
		return _failure(assembly_failures)
	var plan: EnvironmentLayoutPlan = generated.environment_layout_plan
	if plan == null:
		return _failure([_diagnostic("MISSING_GENERATION_PLAN", "generation", "coherent generation did not produce an environment plan")])
	if not plan.relationship_failures.is_empty():
		return _failure(_relationship_diagnostics(plan.relationship_failures))
	var document := BattlefieldLayoutDocument.from_generated(generated, "runtime_%s_%d" % [BattleConfiguration.GENERATION_2_ENVIRONMENT, config.battle_seed])
	return compile_document(document, config, cell_size)

static func compile_document(document: BattlefieldLayoutDocument, config: BattleConfiguration, cell_size := 1.0) -> Dictionary:
	var configuration_failures := config.validate_generation_selection()
	if not configuration_failures.is_empty(): return _failure(configuration_failures, document)
	var compiled := BattlefieldLayoutDocumentCompiler.compile(document, cell_size, maxi(5, maxi(config.player_count, maxi(config.enemy_count, config.ally_count))))
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

static func _relationship_diagnostics(source: Array[Dictionary]) -> Array[Dictionary]:
	var failures: Array[Dictionary] = []
	for failure in source:
		failures.append(_diagnostic(str(failure.get("code", "RELATIONSHIP_VALIDATION_FAILED")), "relationships", str(failure.get("message", "required spatial relationship failed")), str(failure.get("reference", failure.get("parcel_id", "")))))
	return failures

static func _failure(errors: Array, document: BattlefieldLayoutDocument = null) -> Dictionary:
	return {"ok": false, "data": null, "document": document, "errors": errors.duplicate(true), "repairs": []}

static func _diagnostic(code: String, field: String, message: String, reference := "") -> Dictionary:
	return {"code": code, "field": field, "reference": reference, "message": message}
