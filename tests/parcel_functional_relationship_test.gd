extends SceneTree

const Validator = preload("res://systems/generation/environment_parcel_relationship_validator.gd")
const ParcelContract = preload("res://systems/generation/environment_parcel_spatial_contract.gd")
const LayoutStore = preload("res://tools/map_editor_layout_store.gd")

var failures := 0
var catalog := IndustrialModuleCatalog.create()

func _init() -> void:
	_test_frontage_contracts()
	_test_pedestrian_geometry_and_tactics()
	_test_loading_and_service_contracts()
	_test_required_and_optional_occupants()
	_test_document_lifecycle()
	print("Parcel functional relationships: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_frontage_contracts() -> void:
	var parcel := _parcel("frontage", Rect2i(10, 10, 20, 20), Vector2i.DOWN, 20)
	var template := "building_frontage/industrial_shell_i"
	var span := Validator.select_frontage(parcel, template)
	check(not span.is_empty() and Validator.rotation_for_frontage(template, span) == 0, "a complete shell resolves its actual street boundary and canonical frontage rotation")
	var placements := _building_placements(parcel.bounds)
	check(Validator.validate_geometry(parcel, template, placements, catalog, span).is_empty(), "sealed exterior frontage satisfies the supported two-cell pedestrian apron")

	var partial := _parcel("partial", Rect2i(10, 10, 20, 20), Vector2i.DOWN, 1)
	var partial_span: Dictionary = partial.frontage_spans[0]
	check(_has_code(Validator.validate_geometry(partial, template, placements, catalog, partial_span), "INSUFFICIENT_FRONTAGE_WIDTH"), "a one-cell road touch is insufficient for the selected building frontage")

	var wrong := parcel.duplicate(true)
	wrong.rotation = 2
	check(_has_code(Validator.validate_geometry(wrong, template, placements, catalog, span), "INVALID_FRONTAGE_ORIENTATION"), "a building entrance facing away from its referenced street is rejected")

func _test_pedestrian_geometry_and_tactics() -> void:
	var parcel := _parcel("pedestrian", Rect2i(10, 10, 20, 20), Vector2i.DOWN, 20)
	var template := "building_frontage/industrial_shell_i"
	var span: Dictionary = parcel.frontage_spans[0]
	var placements := _building_placements(parcel.bounds)
	var blocked := placements.duplicate()
	blocked.append(EnvironmentModulePlacement.new(&"cargo_container", Vector2i(19, 27)))
	check(_has_code(Validator.validate_geometry(parcel, template, blocked, catalog, span), "BLOCKED_PEDESTRIAN_APPROACH"), "real obstacle geometry across the frontage apron is detected")
	blocked = blocked.filter(func(value): return value.component_id != &"cargo_container")
	check(Validator.validate_geometry(parcel, template, blocked, catalog, span).is_empty(), "rejecting optional dressing independently restores the complete required frontage")

	var data := FlatMapGenerator.generate(40, 40, 1.0, 5303)
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	check(Validator.validate_tactical(parcel, template, data, graph, span).is_empty(), "clear physical frontage also has a valid MapData pedestrian route")
	var blocked_cell := Vector3i(19, 0, 29)
	data.get_cell(blocked_cell).walkable = false
	data.get_cell(blocked_cell).can_stop = false
	graph = Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	check(_has_code(Validator.validate_tactical(parcel, template, data, graph, span), "MISSING_TACTICAL_ACCESS"), "physical frontage and tactical disconnection are reported separately")

func _test_loading_and_service_contracts() -> void:
	var loading := _parcel("loading", Rect2i(10, 10, 10, 10), Vector2i.DOWN, 10)
	var loading_span: Dictionary = loading.frontage_spans[0]
	var loading_placements: Array[EnvironmentModulePlacement] = [
		EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i(10, 10)),
		EnvironmentModulePlacement.new(&"industrial_loading_canopy", Vector2i(11, 12)),
	]
	check(Validator.validate_geometry(loading, "loading_bay", loading_placements, catalog, loading_span).is_empty(), "loading bay has a compatible four-cell geometric approach")
	var blocked_loading := loading_placements.duplicate()
	blocked_loading.append(EnvironmentModulePlacement.new(&"cargo_container", Vector2i(14, 17)))
	check(_has_code(Validator.validate_geometry(loading, "loading_bay", blocked_loading, catalog, loading_span), "BLOCKED_LOADING_CLEARANCE"), "cargo across the authored loading band invalidates loading access")

	var service := _parcel("service", Rect2i(10, 10, 10, 10), Vector2i.LEFT, 10)
	var service_span: Dictionary = service.frontage_spans[0]
	var equipment := IndustrialEquipmentParcelDefinition.new()
	var service_placements := equipment.placements(service.bounds.position, false, 0)
	check(Validator.validate_geometry(service, "equipment_compound", service_placements, catalog, service_span).is_empty(), "certified operator route reaches the selected west service frontage")
	var blocked_service := service_placements.duplicate()
	blocked_service.append(EnvironmentModulePlacement.new(&"cargo_container", Vector2i(10, 13), 1))
	check(_has_code(Validator.validate_geometry(service, "equipment_compound", blocked_service, catalog, service_span), "MISSING_SERVICE_CLEARANCE"), "equipment service-region obstruction is rejected")

func _test_required_and_optional_occupants() -> void:
	var parcel := _parcel("equipment", Rect2i(10, 10, 10, 10), Vector2i.LEFT, 10)
	var equipment := IndustrialEquipmentParcelDefinition.new()
	var required_only := equipment.placements(parcel.bounds.position, false, 0)
	check(Validator.validate_geometry(parcel, "equipment_compound", required_only, catalog, parcel.frontage_spans[0]).is_empty(), "optional cargo and fence may be absent without invalidating equipment function")
	var missing := required_only.filter(func(value): return value.component_id != &"factory_pipe_receiver_unit")
	check(_has_code(Validator.validate_geometry(parcel, "equipment_compound", missing, catalog, parcel.frontage_spans[0]), "MISSING_REQUIRED_OCCUPANT"), "missing primary equipment invalidates the parcel")
	check(Validator.contract_for("equipment_compound").classification == "open_equipment_area", "equipment compound remains honestly classified as an open yard")

func _test_document_lifecycle() -> void:
	var data := FlatMapGenerator.generate_coherent_environment(40, 30, 1.0, 2208, &"industrial_district")
	var document := BattlefieldLayoutDocument.from_generated(data, "functional_relationship_2208")
	var access := document.relationships.filter(func(value): return value.get("kind", "") in [ParcelContract.PEDESTRIAN_ACCESS, ParcelContract.LOADING_ACCESS, ParcelContract.SERVICE_CLEARANCE])
	check(not access.is_empty() and access.all(func(value): return not value.get("properties", {}).get("access_cells", []).is_empty()), "documents preserve concrete access cells and frontage requirements")
	var encoded := LayoutStore.encode(document)
	var decoded := LayoutStore.decode(encoded, catalog)
	var relationships_match: bool = decoded.ok and _functional_signature(decoded.document) == _functional_signature(document)
	var parcels_match: bool = decoded.ok and _parcel_signature(decoded.document) == _parcel_signature(document)
	check(decoded.ok and relationships_match and parcels_match, "functional relationships reconstruct deterministically through save/load (relationships=%s parcels=%s): %s" % [relationships_match, parcels_match, decoded.get("errors", [])])
	var edited := document.editable_copy()
	var layout := edited.to_module_layout(catalog)
	var owned_ref := ""
	for parcel in edited.spatial_layout.parcels:
		if not parcel.occupants.is_empty():
			owned_ref = str(parcel.occupants[0].placement_ref)
			break
	var record_index := -1
	for index in edited.spatial_layout.placements.size():
		if edited.spatial_layout.placements[index].placement_id == owned_ref: record_index = index
	if record_index >= 0:
		var record: Dictionary = edited.spatial_layout.placements[record_index]
		var original: Array = record.origin
		var replacement := EnvironmentModulePlacement.new(StringName(record.component_id), Vector2i(int(original[0]), int(original[1])), int(record.rotation), int(record.variation) + 1, int(record.elevation), str(record.placement_id))
		for index in layout.placements.size():
			if layout.placements[index].signature() == EnvironmentModulePlacement.new(StringName(record.component_id), Vector2i(int(original[0]), int(original[1])), int(record.rotation), int(record.variation), int(record.elevation)).signature(): layout.placements[index] = replacement
		edited.apply_edited_layout(layout)
	check(edited.relationships.any(func(value): return value.get("kind", "") in ParcelContract.FUNCTIONAL_RELATIONSHIPS and value.get("validation_state", "") == "requires_revalidation"), "editing preserves required relationships and marks them for revalidation")
	var revalidatable := document.editable_copy()
	var revalidation_layout := revalidatable.to_module_layout(catalog)
	var owned_ids: Dictionary = {}
	for parcel in revalidatable.spatial_layout.parcels:
		for occupant in parcel.occupants: owned_ids[str(occupant.placement_ref)] = true
	for record in revalidatable.spatial_layout.placements:
		if owned_ids.has(str(record.placement_id)): continue
		if String(record.component_id) in ["street_light", "utility_pole", "stop_sign", "traffic_signal"]:
			for placement: EnvironmentModulePlacement in revalidation_layout.placements:
				if placement.component_id == StringName(record.component_id) and placement.origin == Vector2i(int(record.origin[0]), int(record.origin[1])):
					placement.variation += 1
					break
			break
	revalidatable.apply_edited_layout(revalidation_layout)
	var rebuilt := BattlefieldLayoutDocumentCompiler.compile(revalidatable)
	check(rebuilt.ok and rebuilt.document.relationships.filter(func(value): return value.get("kind", "") in ParcelContract.FUNCTIONAL_RELATIONSHIPS).all(func(value): return value.get("validation_state", "") == "validated"), "successful document compilation explicitly revalidates preserved functional relationships: %s" % [rebuilt.errors])

func _parcel(id: String, bounds: Rect2i, direction: Vector2i, width: int) -> Dictionary:
	var start := bounds.position
	if direction == Vector2i.DOWN: start = Vector2i(bounds.position.x, bounds.end.y)
	elif direction == Vector2i.RIGHT: start = Vector2i(bounds.end.x, bounds.position.y)
	var tangent := Vector2i.RIGHT if direction.y != 0 else Vector2i.DOWN
	var finish := start + tangent * width
	return {"id": id, "bounds": bounds, "rotation": 0, "frontage_spans": [{"frontage_id": id + "_frontage", "outward_direction": [direction.x, direction.y], "start": [start.x, start.y], "end": [finish.x, finish.y], "width_cells": width, "clearance_depth_cells": 1, "road_refs": ["road"]}]}

func _building_placements(bounds: Rect2i) -> Array[EnvironmentModulePlacement]:
	var result: Array[EnvironmentModulePlacement] = []
	for offset in [Vector2i.ZERO, Vector2i(10, 0), Vector2i(0, 10), Vector2i(10, 10)]: result.append(EnvironmentModulePlacement.new(&"paved_courtyard", bounds.position + offset))
	result.append(EnvironmentModulePlacement.new(&"industrial_shell_i", bounds.position + Vector2i(4, 0)))
	return result

func _has_code(values: Array, code: String) -> bool:
	return values.any(func(value): return value.get("code", "") == code)

func _functional_signature(document: BattlefieldLayoutDocument) -> String:
	var parts: Array[String] = []
	for value in document.relationships:
		if value.get("kind", "") in ParcelContract.FUNCTIONAL_RELATIONSHIPS:
			parts.append("%s:%s:%s:%s:%s" % [value.get("relationship_id", ""), value.get("kind", ""), value.get("subject_ref", ""), value.get("object_ref", ""), JSON.stringify(_canonical(value.get("properties", {})))])
	parts.sort()
	return "|".join(parts)

func _parcel_signature(document: BattlefieldLayoutDocument) -> String:
	var parts: Array[String] = []
	for parcel in document.spatial_layout.parcels:
		parts.append("%s:%s:%s:%s:%s" % [parcel.get("parcel_id", ""), parcel.get("template_id", ""), int(parcel.get("rotation", 0)), JSON.stringify(_canonical(parcel.get("frontage_spans", []))), JSON.stringify(_canonical(parcel.get("occupants", [])))])
	parts.sort()
	return "|".join(parts)

func _canonical(value):
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = _canonical(value[key])
		return result
	if value is Array:
		var result := []
		for item in value: result.append(_canonical(item))
		return result
	if typeof(value) == TYPE_FLOAT and is_equal_approx(value, roundf(value)): return int(value)
	return value

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
