extends SceneTree

const Validator = preload("res://systems/generation/environment_parcel_relationship_validator.gd")
const Search = preload("res://systems/generation/environment_parcel_candidate_search.gd")
const Reservations = preload("res://systems/generation/environment_spatial_reservation_ledger.gd")
const LayoutStore = preload("res://tools/map_editor_layout_store.gd")

const ELONGATED_SIZES := [Vector2i(20, 10), Vector2i(10, 20)]
const CASES := [
	[&"industrial_district", 17],
	[&"mixed_service", 11027],
	[&"commercial_street", 7319],
]

var failures := 0
var catalog := IndustrialModuleCatalog.create()

func _init() -> void:
	_test_rectangular_recipe_rotations()
	_test_relationship_and_transaction_boundaries()
	_test_seed_matrix_and_persistence()
	print("Coherent parcel-size expansion: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_rectangular_recipe_rotations() -> void:
	var cases := [
		[Rect2i(5, 7, 20, 10), Vector2i.DOWN, 0],
		[Rect2i(5, 7, 10, 20), Vector2i.LEFT, 1],
		[Rect2i(5, 7, 20, 10), Vector2i.UP, 2],
		[Rect2i(5, 7, 10, 20), Vector2i.RIGHT, 3],
	]
	for item in cases:
		var bounds: Rect2i = item[0]
		var direction: Vector2i = item[1]
		var rotation: int = item[2]
		var parcel := _parcel("rotation_%d" % rotation, bounds, direction)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7200 + rotation
		var placements := CoherentEnvironmentAssembler._template_placements(&"loading_service_strip", bounds, rotation, rng)
		check(placements.size() == 5, "rotation %d reconstructs every authored strip occupant" % rotation)
		check(_placements_fit(placements, bounds), "rotation %d keeps rectangular occupants inside %s" % [rotation, bounds])
		check(Validator.validate_geometry(parcel, "loading_service_strip", placements, catalog, parcel.frontage_spans[0]).is_empty(), "rotation %d preserves its exact loading frontage and clear approach" % rotation)
	check(CoherentEnvironmentAssembler._template_placements(&"loading_service_strip", Rect2i(0, 0, 20, 20), 0, RandomNumberGenerator.new()).is_empty(), "unsupported square/strip combination is rejected rather than stretched")

func _test_relationship_and_transaction_boundaries() -> void:
	var parcel := _parcel("relationship", Rect2i(0, 0, 20, 10), Vector2i.DOWN)
	var rng := RandomNumberGenerator.new()
	rng.seed = 72
	var placements := CoherentEnvironmentAssembler._template_placements(&"loading_service_strip", parcel.bounds, 0, rng)
	var required_only: Array[EnvironmentModulePlacement] = []
	for placement: EnvironmentModulePlacement in placements:
		if placement.component_id not in [&"cargo_container", &"construction_barrier_vault"]: required_only.append(placement)
	check(Validator.validate_geometry(parcel, "loading_service_strip", required_only, catalog, parcel.frontage_spans[0]).is_empty(), "optional cargo and barrier may fail independently without invalidating the loading strip")
	var blocked := required_only.duplicate()
	blocked.append(EnvironmentModulePlacement.new(&"construction_barrier_vault", Vector2i(9, 7)))
	check(_has_code(Validator.validate_geometry(parcel, "loading_service_strip", blocked, catalog, parcel.frontage_spans[0]), "BLOCKED_LOADING_CLEARANCE"), "an obstacle in the four-cell-deep service lane invalidates loading access")

	var reservation_ledger := Reservations.new()
	reservation_ledger.try_reserve({"reservation_id": "external_service", "owner_ref": "other_parcel", "role": Reservations.LOADING_SERVICE_APPROACH, "purpose": "fixture", "cells": [Vector2i(0, 1)], "required": true})
	var source := EnvironmentModuleLayout.new(&"rectangular_transaction", 72)
	var specification := Search.specifications(parcel, [&"loading_service_strip"], catalog)[0]
	var result := CoherentEnvironmentAssembler._evaluate_candidate(source, reservation_ledger, parcel, specification, catalog, Vector2i(30, 20), 72)
	check(not result.ok and result.code == "RESERVED_REGION_BLOCKED", "a conflicting external reservation rejects the elongated candidate with its real cause")
	check(source.placements.is_empty() and reservation_ledger.reservations.size() == 1 and reservation_ledger.failures.is_empty(), "rectangular candidate rejection leaves placements and reservations transactional")

func _test_seed_matrix_and_persistence() -> void:
	for item in CASES:
		var environment_id: StringName = item[0]
		var map_seed: int = item[1]
		var started := Time.get_ticks_usec()
		var first := FlatMapGenerator.generate_coherent_environment(60, 50, 1.0, map_seed, environment_id)
		var repeated := FlatMapGenerator.generate_coherent_environment(60, 50, 1.0, map_seed, environment_id)
		var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
		var plan: EnvironmentLayoutPlan = first.environment_layout_plan
		var repeated_plan: EnvironmentLayoutPlan = repeated.environment_layout_plan
		var label := "%s seed %d" % [environment_id, map_seed]
		var sizes := _parcel_size_counts(plan)
		check(int(sizes.get("10x10", 0)) > 0 and int(sizes.get("20x20", 0)) > 0, "%s preserves established 10x10 and 20x20 parcels" % label)
		var elongated := plan.parcels.filter(func(parcel): return (parcel.bounds as Rect2i).size in ELONGATED_SIZES)
		if environment_id in [&"industrial_district", &"mixed_service"]:
			check(elongated.size() == 1 and elongated[0].template == &"loading_service_strip", "%s selects exactly one curated elongated loading/service parcel" % label)
			check(elongated[0].occupants.filter(func(value): return value.required).size() >= 3, "%s records required paving and canopy ownership" % label)
			check(elongated[0].frontage_spans.any(func(span): return int(span.width_cells) >= 4), "%s retains its measured road-adjacent frontage interval" % label)
		else:
			check(elongated.is_empty(), "%s does not receive an unsupported industrial strip" % label)
		check(plan.signature() == repeated_plan.signature() and _placement_signature(first) == _placement_signature(repeated), "%s remains deterministic with the additional parcel choice" % label)
		check(plan.parcel_search_reports.all(func(report): return int(report.attempts) <= Search.MAX_CANDIDATE_ATTEMPTS_PER_PARCEL), "%s remains inside the fixed candidate budget" % label)
		check(plan.relationship_failures.is_empty() and _tactical_errors(first).is_empty(), "%s preserves functional relationships, deployment, and tactical authority" % label)
		var document := BattlefieldLayoutDocument.from_generated(first, "parcel_size_%s_%d" % [environment_id, map_seed])
		var encoded := LayoutStore.encode(document)
		var decoded := LayoutStore.decode(encoded, catalog)
		check(decoded.ok and _document_parcel_signature(decoded.document) == _document_parcel_signature(document), "%s preserves rectangular bounds, ownership, configuration, and frontage through save/load" % label)
		var compiled := BattlefieldLayoutDocumentCompiler.compile(decoded.document) if decoded.ok else {"ok": false, "errors": decoded.get("errors", [])}
		check(compiled.ok, "%s reconstructs the expanded layout document: %s" % [label, compiled.get("errors", [])])
		print("[ParcelSize] %s | %.2f ms for two builds | sizes=%s | %s" % [label, elapsed_ms, JSON.stringify(sizes), JSON.stringify(plan.generation_summary())])

func _parcel(id: String, bounds: Rect2i, direction: Vector2i) -> Dictionary:
	var start := bounds.position
	var width := bounds.size.x if direction.y != 0 else bounds.size.y
	if direction == Vector2i.DOWN: start = Vector2i(bounds.position.x, bounds.end.y)
	elif direction == Vector2i.RIGHT: start = Vector2i(bounds.end.x, bounds.position.y)
	var tangent := Vector2i.RIGHT if direction.y != 0 else Vector2i.DOWN
	return {"id": StringName(id), "bounds": bounds, "road_edges": [direction], "rotation": Validator.rotation_for_frontage("loading_service_strip", {"outward_direction": [direction.x, direction.y]}), "frontage_spans": [{"frontage_id": id + "_frontage", "outward_direction": [direction.x, direction.y], "start": [start.x, start.y], "end": [start.x + tangent.x * width, start.y + tangent.y * width], "width_cells": width, "clearance_depth_cells": 1, "road_refs": ["road"]}]}

func _placements_fit(placements: Array[EnvironmentModulePlacement], bounds: Rect2i) -> bool:
	for placement in placements:
		var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
		for cell in definition.rotated_cells(definition.footprint_cells, placement.rotation):
			if not bounds.has_point(placement.origin + cell): return false
	return true

func _parcel_size_counts(plan: EnvironmentLayoutPlan) -> Dictionary:
	var result := {}
	for parcel in plan.parcels:
		var size: Vector2i = parcel.bounds.size
		var key := "%dx%d" % [size.x, size.y]
		result[key] = int(result.get(key, 0)) + 1
	return result

func _placement_signature(data: MapData) -> String:
	var values: Array[String] = []
	for placement: EnvironmentModulePlacement in data.environment_modules: values.append(placement.signature())
	return "|".join(values)

func _document_parcel_signature(document: BattlefieldLayoutDocument) -> String:
	var values: Array[String] = []
	for parcel in document.spatial_layout.parcels:
		values.append("%s:%s:%s:%s:%s:%s" % [parcel.parcel_id, JSON.stringify(_canonical(parcel.bounds)), parcel.get("configuration_id", "standard"), parcel.template_id, JSON.stringify(_canonical(parcel.frontage_spans)), JSON.stringify(_canonical(parcel.occupants))])
	values.sort()
	return "|".join(values)

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

func _tactical_errors(data: MapData) -> Array:
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	return MapValidator.validate(data, graph, {MapZoneData.Kind.DEPLOYMENT: 5}).errors

func _has_code(values: Array, code: String) -> bool:
	return values.any(func(value): return value.get("code", "") == code)

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
