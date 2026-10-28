class_name BattlefieldLayoutDocumentCompiler
extends RefCounted
## One construction boundary for generated and edited Map Editor documents.
## Module effects compile through EnvironmentModuleMapWriter; MapData remains
## the sole tactical authority.

const RelationshipValidator = preload("res://systems/generation/environment_parcel_relationship_validator.gd")

static func compile(source: BattlefieldLayoutDocument, cell_size := 1.0, legacy_spawn_capacity := 5, context: EnvironmentResolutionContext = null) -> Dictionary:
	if context == null: context = EnvironmentResolutionContext.new()
	var errors := source.validate(context.catalog, context)
	if not errors.is_empty(): return {"ok": false, "data": null, "document": source, "errors": errors, "repairs": []}
	var document := BattlefieldLayoutDocument.from_dictionary(source.to_dictionary())
	var encoded_size: Array = document.spatial_layout.map_size
	var map_size := Vector2i(int(encoded_size[0]), int(encoded_size[1]))
	var generation_seed := int(document.provenance.get("generation_seed", 0)) if bool(document.provenance.get("has_generation_seed", false)) else 0
	var spawn_capacity := _maximum_deployment_count(document, legacy_spawn_capacity)
	var data := FlatMapGenerator.generate(map_size.x, map_size.y, cell_size, generation_seed, spawn_capacity)
	document.restore_mission_to_map(data)
	var catalog := context.catalog
	var layout := document.to_module_layout(catalog)
	if not layout.errors.is_empty():
		for message in layout.errors: errors.append({"code": "LAYOUT_RECONSTRUCTION_FAILED", "field": "spatial_layout.placements", "reference": "", "message": message})
		return {"ok": false, "data": data, "document": document, "errors": errors, "repairs": []}
	data.resolved_environment_modules = context.resolve_layout(layout)
	errors.append_array(context.errors)
	if not errors.is_empty(): return {"ok": false, "data": null, "document": source, "errors": errors, "repairs": []}
	errors.append_array(EnvironmentModuleMapWriter.apply(data, layout, catalog, cell_size))
	if not errors.is_empty():
		return {"ok": false, "data": null, "document": source, "errors": errors, "repairs": []}
	errors.append_array(TacticalPopulationPass.verify(document, data, context))
	if not errors.is_empty(): return {"ok": false, "data": null, "document": source, "errors": errors, "repairs": []}
	var deployment := EnvironmentDeploymentResolver.repair(data, EnvironmentDeploymentResolver.road_anchors(layout, catalog))
	if document.provenance.has("population") and not deployment.repairs.is_empty():
		errors.append({"code": "POPULATION_CHANGED_MISSION", "field": "mission_context", "reference": "", "message": "Population must preserve authored deployments without repair"})
	for failure in deployment.failures: errors.append({"code": failure.code, "field": "mission_context.zones", "reference": failure.zone_id, "message": failure.message})
	data.source_kind = "layout_document_%s" % document.provenance.get("origin", "unknown")
	data.environment_modules.assign(layout.placements)
	data.environment_module_seed = generation_seed
	if document.provenance.get("source_origin", document.provenance.get("origin", "")) == "generated" or document.relationships.any(func(value): return value.get("kind", "") == "parcel_template"):
		data.environment_layout_plan = document.to_environment_layout_plan()
	data.rebuild_los_index()
	if errors.is_empty():
		var graph := Pathfinder.new()
		MapGraphBuilder.build(data, graph)
		var validation := MapValidator.validate(data, graph, _required_deployments(document))
		for issue in validation.errors:
			errors.append({"code": issue.code, "field": "compiled_map", "reference": issue.describe(), "message": issue.message})
		for parcel in document.to_environment_layout_plan().parcels:
			var template_id := str(parcel.get("template", ""))
			var span := RelationshipValidator.select_frontage(parcel, template_id)
			for issue in RelationshipValidator.validate_tactical(parcel, template_id, data, graph, span, catalog):
				errors.append({"code": issue.code, "field": "relationships", "reference": issue.reference, "message": issue.message})
	if errors.is_empty(): document.mark_functional_relationships_validated()
	document.replace_mission_from_map(data)
	data.battlefield_layout_document = document
	return {"ok": errors.is_empty(), "data": data, "document": document, "errors": errors, "repairs": deployment.repairs}

static func _maximum_deployment_count(document: BattlefieldLayoutDocument, fallback: int) -> int:
	var result := 0
	if document.mission_context.get("status", "") == "preserved":
		for zone in document.mission_context.get("zones", []):
			if int(zone.get("kind", -1)) == MapZoneData.Kind.DEPLOYMENT: result = maxi(result, zone.get("cells", []).size())
	return result if result > 0 else fallback

static func _required_deployments(document: BattlefieldLayoutDocument) -> Dictionary:
	var result: Dictionary = {}
	if document.mission_context.get("status", "") != "preserved": return result
	for zone in document.mission_context.get("zones", []):
		if int(zone.get("kind", -1)) != MapZoneData.Kind.DEPLOYMENT: continue
		var faction := int(zone.get("faction", -1))
		result[faction] = int(result.get(faction, 0)) + zone.get("cells", []).size()
	return result
