class_name BattlefieldLayoutDocumentCompiler
extends RefCounted
## One construction boundary for generated and edited Map Editor documents.
## Module effects compile through EnvironmentModuleMapWriter; MapData remains
## the sole tactical authority.

static func compile(source: BattlefieldLayoutDocument, cell_size := 1.0, legacy_spawn_capacity := 5) -> Dictionary:
	var errors := source.validate()
	if not errors.is_empty(): return {"ok": false, "data": null, "document": source, "errors": errors, "repairs": []}
	var document := BattlefieldLayoutDocument.from_dictionary(source.to_dictionary())
	var encoded_size: Array = document.spatial_layout.map_size
	var map_size := Vector2i(int(encoded_size[0]), int(encoded_size[1]))
	var seed := int(document.provenance.get("generation_seed", 0)) if bool(document.provenance.get("has_generation_seed", false)) else 0
	var spawn_capacity := _maximum_deployment_count(document, legacy_spawn_capacity)
	var data := FlatMapGenerator.generate(map_size.x, map_size.y, cell_size, seed, spawn_capacity)
	document.restore_mission_to_map(data)
	var catalog := IndustrialModuleCatalog.create()
	var layout := document.to_module_layout(catalog)
	if not layout.errors.is_empty():
		for message in layout.errors: errors.append({"code": "LAYOUT_RECONSTRUCTION_FAILED", "field": "spatial_layout.placements", "reference": "", "message": message})
		return {"ok": false, "data": data, "document": document, "errors": errors, "repairs": []}
	EnvironmentModuleMapWriter.apply(data, layout, catalog, cell_size)
	var deployment := EnvironmentDeploymentResolver.repair(data, EnvironmentDeploymentResolver.road_anchors(layout, catalog))
	for failure in deployment.failures: errors.append({"code": failure.code, "field": "mission_context.zones", "reference": failure.zone_id, "message": failure.message})
	data.source_kind = "layout_document_%s" % document.provenance.get("origin", "unknown")
	data.environment_modules.assign(layout.placements)
	data.environment_module_seed = seed
	if document.provenance.get("source_origin", document.provenance.get("origin", "")) == "generated" or document.relationships.any(func(value): return value.get("kind", "") == "parcel_template"):
		data.environment_layout_plan = document.to_environment_layout_plan()
	data.rebuild_los_index()
	if errors.is_empty():
		var graph := Pathfinder.new()
		MapGraphBuilder.build(data, graph)
		var validation := MapValidator.validate(data, graph, _required_deployments(document))
		for issue in validation.errors:
			errors.append({"code": issue.code, "field": "compiled_map", "reference": issue.describe(), "message": issue.message})
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
