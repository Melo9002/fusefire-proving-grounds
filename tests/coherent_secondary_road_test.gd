extends SceneTree
## Task 7.1 contract: the certified 60x50 reference scale may add one
## deterministic secondary street. Road openings must connect or terminate at
## the map boundary; rejected topologies remain transactional.

const ReservationLedger = preload("res://systems/generation/environment_spatial_reservation_ledger.gd")

var failures := 0
var catalog := IndustrialModuleCatalog.create()

func _init() -> void:
	_test_secondary_branch_seed_matrix()
	_test_supported_t_intersection_rotations()
	_test_required_reservations_block_branch_candidates()
	_test_invalid_openings_and_transactional_commit()
	_test_legacy_primary_topology_remains_supported()
	print("Coherent secondary roads: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_secondary_branch_seed_matrix() -> void:
	var observed_multiple_frontage_boundaries := false
	for item in [[&"industrial_district", 17], [&"commercial_street", 7319], [&"mixed_service", 11027]]:
		var environment_id: StringName = item[0]
		var map_seed: int = item[1]
		var started := Time.get_ticks_usec()
		var first := FlatMapGenerator.generate_coherent_environment(60, 50, 1.0, map_seed, environment_id)
		var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
		var repeated := FlatMapGenerator.generate_coherent_environment(60, 50, 1.0, map_seed, environment_id)
		var plan: EnvironmentLayoutPlan = first.environment_layout_plan
		var roads := _roads(first)
		var intersections := roads.filter(func(placement): return placement.component_id in [&"road_intersection_t", &"road_crossroad"])
		var label := "%s seed %d" % [environment_id, map_seed]
		check("secondary_branch" in String(plan.topology), "%s selects the bounded secondary-street topology" % label)
		check(intersections.size() == 2, "%s contains one primary and one secondary intersection, got %d" % [label, intersections.size()])
		check(CoherentEnvironmentAssembler._road_network_supported(_road_layout(first), catalog, first.map_size), "%s has no disconnected road components or unsupported interior openings" % label)
		check(_all_road_openings_resolve(first), "%s resolves every logical road opening to a neighbor or map boundary" % label)
		check(plan.signature() == repeated.environment_layout_plan.signature() and _placement_signature(first) == _placement_signature(repeated), "%s reproduces the same secondary street, parcels, and placements" % label)
		check(_frontage_references_resolve(first), "%s frontage spans reference actual accepted road placements" % label)
		observed_multiple_frontage_boundaries = observed_multiple_frontage_boundaries or plan.parcels.any(func(parcel): return parcel.get("frontage_spans", []).size() > 1)
		var document := BattlefieldLayoutDocument.from_generated(first, "secondary_%s_%d" % [environment_id, map_seed])
		var compiled := BattlefieldLayoutDocumentCompiler.compile(document)
		check(document.validate(catalog).is_empty() and compiled.ok, "%s survives unified-document validation and tactical reconstruction: %s" % [label, compiled.errors])
		print("[SecondaryRoad] %s | %.2f ms | %d roads | %s" % [label, elapsed_ms, roads.size(), JSON.stringify(plan.generation_summary())])
	check(observed_multiple_frontage_boundaries, "the representative matrix retains parcels with multiple exact road-facing boundaries")

func _test_supported_t_intersection_rotations() -> void:
	var direction_sets := [
		[Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN],
		[Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT],
		[Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP],
		[Vector2i.UP, Vector2i.DOWN, Vector2i.RIGHT],
	]
	for rotation in 4:
		check(CoherentEnvironmentAssembler._rotation_for_road_directions(catalog.road_intersection_t, direction_sets[rotation]) == rotation, "T-intersection rotation %d resolves its independently enumerated physical openings" % rotation)

func _test_required_reservations_block_branch_candidates() -> void:
	var specs: Array[Dictionary] = []
	var primary: Dictionary = {}
	for macro_x in 6:
		var macro := Vector2i(macro_x, 2)
		specs.append({"macro": macro, "placement": EnvironmentModulePlacement.new(&"road_straight", macro * 10, 1)})
		primary[macro] = true
	var blocked_cells: Array[Vector2i] = []
	for y in [0, 1, 3, 4]:
		for x in 60: blocked_cells.append(Vector2i(x, y * 10 + 5))
	var reservations := ReservationLedger.new()
	check(reservations.try_reserve({
		"reservation_id": "required_branch_guard",
		"owner_ref": "mission:road_guard",
		"role": ReservationLedger.OBJECTIVE_REGION,
		"purpose": "test every perpendicular branch corridor",
		"cells": blocked_cells,
		"required": true,
	}), "required branch-guard reservation is valid")
	var result := CoherentEnvironmentAssembler._select_secondary_branch(specs, primary, catalog, 6, 5, 17, reservations)
	check(result.is_empty(), "secondary streets do not displace required mission reservations")

func _test_invalid_openings_and_transactional_commit() -> void:
	var target := EnvironmentModuleLayout.new(&"transaction_target", 7)
	var incompatible: Array[Dictionary] = [
		{"macro": Vector2i(2, 0), "placement": EnvironmentModulePlacement.new(&"road_straight", Vector2i(20, 0), 0)},
		{"macro": Vector2i(2, 1), "placement": EnvironmentModulePlacement.new(&"road_straight", Vector2i(20, 10), 1)},
	]
	check(not CoherentEnvironmentAssembler._commit_road_specs(target, incompatible, catalog, Vector2i(50, 40)), "incompatible neighboring road openings are rejected")
	check(target.placements.is_empty() and target.errors.is_empty(), "a rejected road topology leaves the accepted layout unchanged")
	var unterminated := EnvironmentModuleLayout.new(&"unterminated", 8)
	var interior := EnvironmentModulePlacement.new(&"road_straight", Vector2i(20, 10), 0)
	check(unterminated.try_add(catalog.road_straight, interior, Vector2i(50, 40)), "interior termination fixture accepts its geometry")
	check(not CoherentEnvironmentAssembler._road_network_supported(unterminated, catalog, Vector2i(50, 40)), "an unmatched road opening inside the map is not treated as a supported termination")

func _test_legacy_primary_topology_remains_supported() -> void:
	var data := FlatMapGenerator.generate_coherent_environment(50, 40, 1.0, 17, &"industrial_district")
	check("secondary_branch" not in String(data.environment_layout_plan.topology), "the established 50x40 primary-road topology remains unchanged")
	check(CoherentEnvironmentAssembler._road_network_supported(_road_layout(data), catalog, data.map_size), "the established primary-road topology satisfies the stricter opening contract")

func _roads(data: MapData) -> Array[EnvironmentModulePlacement]:
	var result: Array[EnvironmentModulePlacement] = []
	for placement: EnvironmentModulePlacement in data.environment_modules:
		var definition: EnvironmentModuleDefinition = catalog.get(placement.component_id)
		if definition != null and definition.module_type in [EnvironmentModuleDefinition.ModuleType.ROAD, EnvironmentModuleDefinition.ModuleType.INTERSECTION]: result.append(placement)
	return result

func _road_layout(data: MapData) -> EnvironmentModuleLayout:
	var layout := EnvironmentModuleLayout.new(&"road_contract_probe", data.environment_layout_plan.generation_seed)
	for placement in _roads(data):
		layout.placements.append(placement)
	return layout

func _all_road_openings_resolve(data: MapData) -> bool:
	var layout := _road_layout(data)
	var roads := _roads(data)
	for placement in roads:
		for opening in layout.world_connections(catalog[placement.component_id], placement):
			if opening.type != EnvironmentModuleConnection.Type.ROAD: continue
			var outside: Vector2i = opening.cell + opening.direction
			if outside.x < 0 or outside.y < 0 or outside.x >= data.map_size.x or outside.y >= data.map_size.y: continue
			var matched := false
			for neighbor in roads:
				if neighbor != placement and layout.placements_connect(placement, neighbor, catalog):
					for candidate in layout.world_connections(catalog[neighbor.component_id], neighbor):
						if candidate.type == EnvironmentModuleConnection.Type.ROAD and candidate.cell == outside and candidate.direction == -opening.direction:
							matched = true
							break
				if matched: break
			if not matched: return false
	return true

func _frontage_references_resolve(data: MapData) -> bool:
	var road_refs: Dictionary = {}
	for placement in _roads(data): road_refs[placement.signature()] = true
	for parcel in data.environment_layout_plan.parcels:
		for span in parcel.get("frontage_spans", []):
			for road_ref in span.get("road_refs", []):
				if not road_refs.has(str(road_ref)): return false
	return true

func _placement_signature(data: MapData) -> String:
	var parts: Array[String] = []
	for placement: EnvironmentModulePlacement in data.environment_modules: parts.append(placement.signature())
	return "|".join(parts)

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
