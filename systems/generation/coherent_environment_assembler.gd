class_name CoherentEnvironmentAssembler
extends RefCounted

const SOURCE_KIND := "generated_modular_coherent"
const MACRO_SIZE := 10
const ENVIRONMENTS: Array[StringName] = [&"industrial_district", &"commercial_street", &"mixed_service"]
const Streetscape = preload("res://systems/generation/road_streetscape_profile.gd")
const BuildingProfiles = preload("res://systems/generation/industrial_building_placement_profiles.gd")
const ParcelContract = preload("res://systems/generation/environment_parcel_spatial_contract.gd")
const ReservationLedger = preload("res://systems/generation/environment_spatial_reservation_ledger.gd")
const RelationshipValidator = preload("res://systems/generation/environment_parcel_relationship_validator.gd")
const CandidateSearch = preload("res://systems/generation/environment_parcel_candidate_search.gd")
# Compatibility name retained for existing bounded-search assertions.
const MAX_TEMPLATE_ATTEMPTS := CandidateSearch.MAX_CANDIDATE_ATTEMPTS_PER_PARCEL

static func apply(data: MapData, cell_size: float, map_seed: int, environment_id: StringName = &"industrial_district") -> EnvironmentModuleLayout:
	var catalog := IndustrialModuleCatalog.create()
	var plan := EnvironmentLayoutPlan.new(environment_id, map_seed)
	plan.macro_size = MACRO_SIZE
	plan.search_budget = CandidateSearch.configuration()
	var layout := EnvironmentModuleLayout.new(&"coherent_%s" % environment_id, map_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed ^ 0x23C0A11
	if data.map_size.x < MACRO_SIZE * 4 or data.map_size.y < MACRO_SIZE * 3:
		layout.errors.append("Coherent assembly requires at least a 40 x 30 map.")
		return layout
	if environment_id not in ENVIRONMENTS:
		layout.errors.append("Unknown environment identity: %s" % environment_id)
		return layout
	if not _build_road_plot(layout, plan, catalog, data.map_size, rng):
		return layout
	# Furniture used to run before parcel planning and consumed one variation draw
	# per straight road. Preserve that established parcel stream while deferring
	# furniture commitment: its cloned stream owns presentation-only variation.
	var streetscape_rng := RandomNumberGenerator.new()
	streetscape_rng.state = rng.state
	_advance_past_streetscape_variations(rng, layout, catalog)
	var reservations := ReservationLedger.from_map(data)
	if not reservations.validate_map_bounds(data.map_size) or not reservations.failures.is_empty():
		for failure in reservations.failures: layout.errors.append("%s: %s" % [failure.code, failure.message])
		return layout
	var parcels := _derive_parcels(plan, layout, catalog, data.map_size, rng)
	var populated := 0
	for parcel in parcels:
		var templates := _template_candidates(environment_id, populated, parcel, rng)
		var specifications := CandidateSearch.specifications(parcel, templates, catalog)
		var search_report := {"parcel_id": String(parcel.id), "available_candidates": specifications.size(), "attempts": 0, "accepted_candidate": "", "outcome": ""}
		var accepted := false
		for specification in specifications:
			if int(search_report.attempts) >= CandidateSearch.MAX_CANDIDATE_ATTEMPTS_PER_PARCEL: break
			var template_id: StringName = specification.template_id
			plan.search_attempts += 1
			search_report.attempts = int(search_report.attempts) + 1
			var result := _evaluate_candidate(layout, reservations, parcel, specification, catalog, data.map_size, map_seed)
			plan.optional_dressing_failures += int(result.get("optional_failures", 0))
			if int(result.get("optional_failures", 0)) > 0:
				plan.decisions.append("%s candidate %s rejected %d optional dressing placement(s)" % [parcel.id, _candidate_label(specification), result.optional_failures])
			if not result.ok:
				var rejection := _candidate_rejection(parcel, specification, result)
				plan.candidate_rejections.append(rejection)
				plan.rejected_candidates.append("%s rejected %s: %s %s" % [parcel.id, template_id, rejection.code, rejection.message])
				continue
			layout = result.layout
			reservations = result.reservations
			parcel.template = template_id
			parcel.rotation = int(specification.rotation)
			parcel.selected_frontage_id = str(specification.frontage_id)
			parcel.placement_offset = int(specification.tangent_offset)
			parcel.occupants = _occupant_records(template_id, result.batch)
			search_report.accepted_candidate = _candidate_label(specification)
			search_report.outcome = "intentional_buffer" if template_id == &"district_buffer" else "functional_placement"
			plan.decisions.append("%s -> %s r%d frontage=%s offset=%d" % [parcel.id, template_id, parcel.rotation, parcel.selected_frontage_id, parcel.placement_offset])
			accepted = true
			if template_id != &"district_buffer": populated += 1
			break
		if not accepted:
			plan.fallback_used = true
			var exhausted := CandidateSearch.budget_exhausted(specifications.size(), int(search_report.attempts), false)
			if exhausted:
				plan.search_budget_exhaustions += 1
				parcel.fallback_reason = "SEARCH_BUDGET_EXHAUSTED"
				search_report.outcome = "search_budget_exhausted"
			else:
				parcel.fallback_reason = "NO_COMPATIBLE_CANDIDATE" if specifications.is_empty() else "PROVEN_INCOMPATIBLE_WITHIN_SUPPORTED_CHOICES"
				search_report.outcome = str(parcel.fallback_reason).to_lower()
			parcel.template = &"district_buffer"
			parcel.rotation = 0
			parcel.occupants = []
			plan.decisions.append("%s -> district_buffer fallback: %s" % [parcel.id, parcel.fallback_reason])
		plan.parcel_search_reports.append(search_report)
		plan.parcels.append(parcel)
	# Optional presentation content is subordinate to mission and parcel access.
	# Running it last avoids committing decorations before frontage is known.
	_decorate_road_network(layout, plan, catalog, data.map_size, streetscape_rng, reservations)
	plan.reservations.assign(reservations.reservations.duplicate(true))
	EnvironmentModuleMapWriter.apply(data, layout, catalog, cell_size)
	var relationship_graph := Pathfinder.new()
	MapGraphBuilder.build(data, relationship_graph)
	for parcel in plan.parcels:
		var template_id := String(parcel.get("template", ""))
		var frontage := RelationshipValidator.select_frontage(parcel, template_id)
		for failure in RelationshipValidator.validate_tactical(parcel, template_id, data, relationship_graph, frontage):
			plan.relationship_failures.append(failure)
			layout.errors.append("%s: %s" % [failure.code, failure.message])
	var deployment_result := EnvironmentDeploymentResolver.repair(data, EnvironmentDeploymentResolver.plan_anchors(plan))
	for repair in deployment_result.repairs:
		plan.decisions.append("deployment %s moved %s -> %s" % [repair.zone_id, repair.from, repair.to])
	for failure in deployment_result.failures:
		layout.errors.append("%s: %s needs %d deployment cells but placed %d" % [failure.code, failure.zone_id, failure.required, failure.placed])
	data.source_kind = "%s_%s" % [SOURCE_KIND, environment_id]
	data.environment_modules.assign(layout.placements)
	data.environment_module_seed = map_seed
	data.environment_layout_plan = plan
	data.rebuild_los_index()
	return layout

static func _build_road_plot(layout: EnvironmentModuleLayout, plan: EnvironmentLayoutPlan, catalog: Dictionary, map_size: Vector2i, rng: RandomNumberGenerator) -> bool:
	var columns := floori(float(map_size.x) / float(MACRO_SIZE))
	var rows := floori(float(map_size.y) / float(MACRO_SIZE))
	var center := Vector2i(rng.randi_range(1, columns - 2), rng.randi_range(1, rows - 2))
	var use_crossroad := plan.environment_id == &"commercial_street" or rng.randi_range(0, 1) == 0
	var intersection_id: StringName = &"road_crossroad" if use_crossroad else &"road_intersection_t"
	var intersection_rotation := rng.randi_range(0, 3) if not use_crossroad else 0
	plan.topology = &"crossroad" if use_crossroad else &"t_junction"
	var intersection := EnvironmentModulePlacement.new(intersection_id, center * MACRO_SIZE, intersection_rotation)
	if not layout.try_add(catalog[intersection_id], intersection, map_size):
		return false
	plan.road_cells.append(center)
	var directions: Array[Vector2i] = []
	for connection in layout.world_connections(catalog[intersection_id], intersection):
		var direction: Vector2i = connection.direction
		if connection.type == EnvironmentModuleConnection.Type.ROAD and direction not in directions:
			directions.append(direction)
	for direction in directions:
		var macro := center + direction
		while macro.x >= 0 and macro.y >= 0 and macro.x < columns and macro.y < rows:
			var rotation := 0 if direction.y != 0 else 1
			var road := EnvironmentModulePlacement.new(&"road_straight", macro * MACRO_SIZE, rotation)
			if not layout.try_add(catalog.road_straight, road, map_size):
				return false
			plan.road_cells.append(macro)
			macro += direction
	plan.decisions.append("road %s at macro %s with %d approaches" % [plan.topology, center, directions.size()])
	return _road_network_connected(layout, catalog)

static func _decorate_road_network(layout: EnvironmentModuleLayout, plan: EnvironmentLayoutPlan, catalog: Dictionary, map_size: Vector2i, rng: RandomNumberGenerator, reservations) -> void:
	# Furniture is attached to authored slots in the road cross-section. Reviewed
	# kit assets give each identity character while the inner sidewalk lane,
	# entrances, and carriageway remain unobstructed.
	var straight_index := 0
	var fixture_count := 0
	var obstacle_count := 0
	var skipped_count := 0
	for placement in layout.placements.duplicate():
		var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
		if definition.module_type == EnvironmentModuleDefinition.ModuleType.INTERSECTION:
			var signal_id := _intersection_fixture_id(plan.environment_id, placement.component_id)
			var seen_directions: Dictionary = {}
			for connection in definition.connections:
				if connection.type != EnvironmentModuleConnection.Type.ROAD or seen_directions.has(connection.direction):
					continue
				seen_directions[connection.direction] = true
				var fixture := Streetscape.approach_fixture(connection.direction)
				var local_cell: Vector2i = definition.rotate_cell(fixture.cell, placement.rotation)
				var yaw := posmod(int(fixture.yaw) + placement.rotation, 4)
				var signal_placement := EnvironmentModulePlacement.new(signal_id, placement.origin + local_cell, yaw)
				if _try_add_reserved(layout, catalog[signal_id], signal_placement, map_size, reservations, "road_furniture"):
					fixture_count += 1
				else:
					skipped_count += 1
					_record_skipped_streetscape(plan, signal_placement)
		elif definition.module_type == EnvironmentModuleDefinition.ModuleType.ROAD:
			var fixture := Streetscape.straight_fixture_slot(straight_index)
			var fixture_id := _straight_fixture_id(plan.environment_id, straight_index)
			var fixture_cell: Vector2i = definition.rotate_cell(fixture.cell, placement.rotation)
			var local_yaw := int(fixture.inward_yaw) if fixture_id == &"street_light" else int(fixture.yaw)
			var fixture_yaw := posmod(local_yaw + placement.rotation, 4)
			var road_fixture := EnvironmentModulePlacement.new(fixture_id, placement.origin + fixture_cell, fixture_yaw, rng.randi_range(0, 1))
			if _try_add_reserved(layout, catalog[fixture_id], road_fixture, map_size, reservations, "road_furniture"):
				fixture_count += 1
			else:
				skipped_count += 1
				_record_skipped_streetscape(plan, road_fixture)
			if _should_add_street_obstacle(plan.environment_id, straight_index):
				var obstacle := Streetscape.straight_fixture_slot(straight_index, true)
				var obstacle_cell: Vector2i = definition.rotate_cell(obstacle.cell, placement.rotation)
				var obstacle_yaw := posmod(int(obstacle.yaw) + placement.rotation, 4)
				var barrier := EnvironmentModulePlacement.new(&"construction_barrier_vault", placement.origin + obstacle_cell, obstacle_yaw)
				if _try_add_reserved(layout, catalog.construction_barrier_vault, barrier, map_size, reservations, "road_furniture"):
					obstacle_count += 1
				else:
					skipped_count += 1
					_record_skipped_streetscape(plan, barrier)
			straight_index += 1
	plan.decisions.append("streetscape placed %d reviewed kit fixtures and %d deliberate tactical barriers" % [fixture_count, obstacle_count])
	if skipped_count > 0: plan.decisions.append("streetscape skipped %d optional fixtures to preserve required reservations" % skipped_count)

static func _record_skipped_streetscape(plan: EnvironmentLayoutPlan, placement: EnvironmentModulePlacement) -> void:
	plan.decisions.append("streetscape skipped %s to preserve required access or occupied parcel geometry" % placement.signature())

static func _intersection_fixture_id(environment_id: StringName, intersection_id: StringName) -> StringName:
	if environment_id == &"commercial_street" or (environment_id == &"mixed_service" and intersection_id == &"road_crossroad"):
		return &"traffic_signal"
	return &"stop_sign"

static func _advance_past_streetscape_variations(rng: RandomNumberGenerator, layout: EnvironmentModuleLayout, catalog: Dictionary) -> void:
	for placement in layout.placements:
		var definition: EnvironmentModuleDefinition = catalog.get(placement.component_id)
		if definition != null and definition.module_type == EnvironmentModuleDefinition.ModuleType.ROAD:
			rng.randi_range(0, 1)

static func _straight_fixture_id(environment_id: StringName, index: int) -> StringName:
	if environment_id == &"commercial_street":
		return &"street_light"
	if environment_id == &"industrial_district":
		return &"utility_pole" if posmod(index, 3) != 1 else &"street_light"
	return &"street_light" if posmod(index, 2) == 0 else &"utility_pole"

static func _should_add_street_obstacle(environment_id: StringName, index: int) -> bool:
	if environment_id == &"industrial_district":
		return posmod(index, 5) == 2
	if environment_id == &"mixed_service":
		return posmod(index, 6) == 3
	return false

static func _road_network_connected(layout: EnvironmentModuleLayout, catalog: Dictionary) -> bool:
	var roads: Array[EnvironmentModulePlacement] = []
	for placement in layout.placements:
		var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
		if definition.module_type in [EnvironmentModuleDefinition.ModuleType.ROAD, EnvironmentModuleDefinition.ModuleType.INTERSECTION]:
			roads.append(placement)
	if roads.is_empty():
		return false
	var reached: Dictionary = {roads[0]: true}
	var frontier: Array[EnvironmentModulePlacement] = [roads[0]]
	while not frontier.is_empty():
		var current: EnvironmentModulePlacement = frontier.pop_back()
		for neighbor in roads:
			if reached.has(neighbor) or not layout.placements_connect(current, neighbor, catalog):
				continue
			reached[neighbor] = true
			frontier.append(neighbor)
	return reached.size() == roads.size()

static func _derive_parcels(plan: EnvironmentLayoutPlan, layout: EnvironmentModuleLayout, catalog: Dictionary, map_size: Vector2i, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var road_lookup: Dictionary = {}
	for road_cell in plan.road_cells:
		road_lookup[road_cell] = true
	var road_cell_owners := _road_cell_owners(layout, catalog)
	var columns := floori(float(map_size.x) / float(MACRO_SIZE))
	var rows := floori(float(map_size.y) / float(MACRO_SIZE))
	var consumed: Dictionary = {}
	var index := 0
	# XCOM's useful lesson is that a parcel is an authored complete space, not
	# necessarily one grid tile. Reserve several non-overlapping 2x2 parcels for
	# complete buildings and their frontage, then fill the remaining single lots.
	var large_origins: Array[Vector2i] = []
	for z in rows - 1:
		for x in columns - 1:
			var origin := Vector2i(x, z)
			var cells := [origin, origin + Vector2i.RIGHT, origin + Vector2i.DOWN, origin + Vector2i.ONE]
			var valid := true
			for cell in cells:
				if road_lookup.has(cell):
					valid = false
					break
			if valid and not _road_edges_for_macro_rect(origin, Vector2i(2, 2), road_lookup).is_empty():
				large_origins.append(origin)
	_shuffle_vector_cells(large_origins, rng)
	var large_target := 3
	match plan.environment_id:
		&"industrial_district": large_target = 4
		&"mixed_service": large_target = 3
	var large_count := 0
	for chosen in large_origins:
		if large_count >= large_target:
			break
		var overlaps := false
		for dz in 2:
			for dx in 2:
				if consumed.has(chosen + Vector2i(dx, dz)):
					overlaps = true
		if overlaps:
			continue
		for dz in 2:
			for dx in 2:
				consumed[chosen + Vector2i(dx, dz)] = true
		var bounds := Rect2i(chosen * MACRO_SIZE, Vector2i(MACRO_SIZE * 2, MACRO_SIZE * 2))
		var frontages := ParcelContract.frontage_spans(bounds, road_cell_owners, "parcel_%02d" % index)
		result.append({
			"id": StringName("parcel_%02d" % index),
			"bounds": bounds,
			"road_edges": ParcelContract.directions_for_spans(frontages),
			"frontage_spans": frontages,
			"occupants": [],
			"template": &"unassigned", "rotation": 0, "boundary": _touches_map_boundary(bounds, map_size),
		})
		index += 1
		large_count += 1
	for z in rows:
		for x in columns:
			var macro := Vector2i(x, z)
			if road_lookup.has(macro) or consumed.has(macro):
				continue
			var bounds := Rect2i(macro * MACRO_SIZE, Vector2i(MACRO_SIZE, MACRO_SIZE))
			var frontages := ParcelContract.frontage_spans(bounds, road_cell_owners, "parcel_%02d" % index)
			result.append({
				"id": StringName("parcel_%02d" % index),
				"bounds": bounds,
				"road_edges": ParcelContract.directions_for_spans(frontages),
				"frontage_spans": frontages,
				"occupants": [],
				"template": &"unassigned",
				"rotation": 0,
				"boundary": _touches_map_boundary(Rect2i(macro * MACRO_SIZE, Vector2i(MACRO_SIZE, MACRO_SIZE)), map_size),
			})
			index += 1
	return result

static func _road_cell_owners(layout: EnvironmentModuleLayout, catalog: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for placement in layout.placements:
		var definition: EnvironmentModuleDefinition = catalog.get(placement.component_id)
		if definition == null or definition.module_type not in [EnvironmentModuleDefinition.ModuleType.ROAD, EnvironmentModuleDefinition.ModuleType.INTERSECTION]:
			continue
		for cell in layout.world_cells(definition, placement):
			result[cell] = placement.signature()
	return result

static func _occupant_records(template_id: StringName, placements: Array[EnvironmentModulePlacement]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for placement in placements:
		result.append({
			"placement_signature": placement.signature(),
			"required": _occupant_is_required(template_id, placement.component_id),
		})
	result.sort_custom(func(a, b): return str(a.placement_signature) < str(b.placement_signature))
	return result

static func _occupant_is_required(template_id: StringName, component_id: StringName) -> bool:
	if template_id == &"equipment_compound":
		return component_id in [&"paved_courtyard", &"factory_pipe_receiver_unit"]
	if String(template_id).begins_with("building_frontage/"):
		return component_id == StringName(String(template_id).trim_prefix("building_frontage/")) or component_id == &"paved_courtyard"
	return component_id not in [&"street_light", &"service_dumpster", &"cargo_container", &"yard_fence", &"construction_barrier_vault"]

static func _touches_map_boundary(bounds: Rect2i, map_size: Vector2i) -> bool:
	return bounds.position.x == 0 or bounds.position.y == 0 or bounds.end.x == map_size.x or bounds.end.y == map_size.y

static func _road_edges_for_macro_rect(origin: Vector2i, size: Vector2i, road_lookup: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var touches := false
		if direction.y != 0:
			var z := origin.y - 1 if direction == Vector2i.UP else origin.y + size.y
			for x in range(origin.x, origin.x + size.x):
				if road_lookup.has(Vector2i(x, z)):
					touches = true
		else:
			var x := origin.x - 1 if direction == Vector2i.LEFT else origin.x + size.x
			for z in range(origin.y, origin.y + size.y):
				if road_lookup.has(Vector2i(x, z)):
					touches = true
		if touches:
			result.append(direction)
	return result

static func _template_candidates(environment_id: StringName, parcel_index: int, parcel: Dictionary, rng: RandomNumberGenerator) -> Array[StringName]:
	var result: Array[StringName]
	var bounds: Rect2i = parcel.bounds
	if bounds.size.x > MACRO_SIZE or bounds.size.y > MACRO_SIZE:
		var buildings := BuildingProfiles.fitting_module_ids(bounds.size, environment_id)
		_shuffle(buildings, rng)
		for module_id in buildings.slice(0, mini(CandidateSearch.MAX_TEMPLATE_CHOICES - 1, buildings.size())):
			result.append(StringName("building_frontage/%s" % module_id))
		if environment_id != &"commercial_street":
			result.append(&"industrial_yard_block")
		return result
	var has_frontage: bool = not (parcel.road_edges as Array).is_empty()
	if not has_frontage:
		# This reserved service/buffer land is intentionally unbuilt. Naming that
		# purpose in the plan distinguishes it from a failed or forgotten parcel.
		result = [&"district_buffer"]
	elif parcel_index == 0:
		match environment_id:
			&"industrial_district": result = [&"loading_bay", &"equipment_compound", &"staging_pad"]
			&"commercial_street": result = [&"service_alley", &"public_forecourt"]
			_: result = [&"equipment_compound", &"loading_bay", &"service_alley"]
	else:
		match environment_id:
			&"industrial_district": result = [&"loading_bay", &"equipment_compound", &"service_alley", &"staging_pad"]
			&"commercial_street": result = [&"service_alley", &"public_forecourt"]
			_: result = [&"loading_bay", &"equipment_compound", &"service_alley", &"staging_pad"]
	_shuffle(result, rng)
	return result

static func _evaluate_candidate(source_layout: EnvironmentModuleLayout, source_reservations, parcel: Dictionary, specification: Dictionary, catalog: Dictionary, map_size: Vector2i, map_seed: int) -> Dictionary:
	var template_id: StringName = specification.template_id
	var frontage: Dictionary = specification.frontage
	var candidate_rng := RandomNumberGenerator.new()
	candidate_rng.seed = CandidateSearch.candidate_seed(map_seed, String(parcel.id), specification)
	var batch := _template_placements(template_id, parcel.bounds, int(specification.rotation), candidate_rng, int(specification.tangent_offset))
	var initial_optional := _optional_occupant_count(template_id, batch)
	var candidate := _clone_layout(source_layout, catalog, map_size)
	if candidate == null: return _candidate_failure("CANDIDATE_REPLAY_FAILED", "existing accepted layout could not be replayed")
	var candidate_reservations = source_reservations.duplicate_ledger()
	var access_ok := _reserve_parcel_access(candidate_reservations, parcel, template_id, frontage, batch, catalog)
	if not access_ok:
		var failure: Dictionary = candidate_reservations.failures.back() if not candidate_reservations.failures.is_empty() else {}
		return _candidate_failure(str(failure.get("code", "MISSING_REQUIRED_ACCESS")), str(failure.get("message", "required access could not be reserved")))
	if not _try_batch(candidate, batch, catalog, map_size, candidate_reservations, "parcel:%s" % parcel.id, template_id):
		var message: String = candidate.errors.back() if not candidate.errors.is_empty() else "required placement was rejected"
		return _candidate_failure(_placement_failure_code(message), message, initial_optional - _optional_occupant_count(template_id, batch))
	var checked_parcel := parcel.duplicate(true)
	checked_parcel["rotation"] = int(specification.rotation)
	checked_parcel["selected_frontage_id"] = str(specification.frontage_id)
	var relationship_failures := RelationshipValidator.validate_geometry(checked_parcel, String(template_id), batch, catalog, frontage)
	var optional_removals := initial_optional - _optional_occupant_count(template_id, batch)
	while not relationship_failures.is_empty() and optional_removals < CandidateSearch.MAX_OPTIONAL_REMOVALS_PER_CANDIDATE:
		var optional_index := _blocking_optional_index(template_id, batch, relationship_failures)
		if optional_index < 0: break
		batch.pop_at(optional_index)
		optional_removals += 1
		candidate = _clone_layout(source_layout, catalog, map_size)
		candidate_reservations = source_reservations.duplicate_ledger()
		access_ok = _reserve_parcel_access(candidate_reservations, parcel, template_id, frontage, batch, catalog)
		if not access_ok or not _try_batch(candidate, batch, catalog, map_size, candidate_reservations, "parcel:%s" % parcel.id, template_id): break
		relationship_failures = RelationshipValidator.validate_geometry(checked_parcel, String(template_id), batch, catalog, frontage)
	if not relationship_failures.is_empty():
		var failure: Dictionary = relationship_failures[0]
		return _candidate_failure(str(failure.get("code", "FUNCTIONAL_RELATIONSHIP_FAILED")), str(failure.get("message", "functional relationship failed")), optional_removals)
	if not access_ok:
		return _candidate_failure("ACCESS_RESERVATION_FAILED", "required access could not be reconstructed after optional rejection", optional_removals)
	if candidate == null or not candidate.errors.is_empty():
		var message: String = candidate.errors.back() if candidate != null and not candidate.errors.is_empty() else "candidate reconstruction failed"
		return _candidate_failure(_placement_failure_code(message), message, optional_removals)
	return {"ok": true, "layout": candidate, "reservations": candidate_reservations, "batch": batch, "optional_failures": optional_removals}

static func _blocking_optional_index(template_id: StringName, batch: Array[EnvironmentModulePlacement], failures: Array[Dictionary]) -> int:
	for failure in failures:
		var blocked_ref := str(failure.get("reference", ""))
		for index in batch.size():
			if batch[index].signature() == blocked_ref and not _occupant_is_required(template_id, batch[index].component_id): return index
	return -1

static func _optional_occupant_count(template_id: StringName, batch: Array[EnvironmentModulePlacement]) -> int:
	var count := 0
	for placement in batch:
		if not _occupant_is_required(template_id, placement.component_id): count += 1
	return count

static func _candidate_failure(code: String, message: String, optional_failures := 0) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "optional_failures": optional_failures}

static func _candidate_rejection(parcel: Dictionary, specification: Dictionary, result: Dictionary) -> Dictionary:
	return {
		"parcel_id": String(parcel.id),
		"template_id": String(specification.template_id),
		"frontage_id": str(specification.frontage_id),
		"rotation": int(specification.rotation),
		"tangent_offset": int(specification.tangent_offset),
		"code": str(result.get("code", "UNKNOWN_REJECTION")),
		"message": str(result.get("message", "candidate rejected")),
	}

static func _placement_failure_code(message: String) -> String:
	var prefix := message.get_slice(":", 0).strip_edges()
	return prefix if prefix.to_upper() == prefix and not prefix.contains(" ") else "PLACEMENT_CONFLICT"

static func _candidate_label(specification: Dictionary) -> String:
	return "%s@%s:r%d:o%d" % [specification.template_id, specification.frontage_id, specification.rotation, specification.tangent_offset]

static func _template_placements(template_id: StringName, parcel: Rect2i, rotation: int, rng: RandomNumberGenerator, tangent_offset := 0) -> Array[EnvironmentModulePlacement]:
	var local: Array[EnvironmentModulePlacement] = []
	var catalog := IndustrialModuleCatalog.create()
	var template_name := String(template_id)
	if template_name.begins_with("building_frontage/"):
		var shell_id := StringName(template_name.trim_prefix("building_frontage/"))
		local = _semantic_frontage_placements(parcel.size, catalog, rng, shell_id, tangent_offset)
	match template_id:
		&"district_buffer":
			local = []
		&"industrial_yard_block":
			local = [
				EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i.ZERO),
				EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i(10, 0)),
				EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i(0, 10)),
				EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i(10, 10)),
				EnvironmentModulePlacement.new(&"industrial_loading_canopy", Vector2i(1, 1)),
				EnvironmentModulePlacement.new(&"machine_cover_cluster", Vector2i(11, 11)),
				EnvironmentModulePlacement.new(&"cargo_container", Vector2i(1, 17), 1, rng.randi_range(0, 2)),
			]
		&"loading_bay":
			local = [
				EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i.ZERO),
				EnvironmentModulePlacement.new(&"industrial_loading_canopy", Vector2i(1, 2)),
			]
		&"equipment_compound":
			# The bounded Phase 3 parcel carries actual service/operator relations;
			# the outer parcel rotation still aligns its west access edge to the road.
			local = IndustrialEquipmentParcelDefinition.new().placements()
		&"service_alley":
			local = [EnvironmentModulePlacement.new(&"paved_alley", Vector2i(3, 0)), EnvironmentModulePlacement.new(&"service_dumpster", Vector2i(0, 4)), EnvironmentModulePlacement.new(&"construction_barrier_vault", Vector2i(8, 6))]
		&"staging_pad":
			local = [EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i.ZERO), EnvironmentModulePlacement.new(&"cargo_container", Vector2i(1, 2)), EnvironmentModulePlacement.new(&"construction_barrier_vault", Vector2i(7, 7))]
		&"public_forecourt":
			local = [EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i.ZERO), EnvironmentModulePlacement.new(&"street_light", Vector2i(1, 8), 0, rng.randi_range(0, 1)), EnvironmentModulePlacement.new(&"street_light", Vector2i(8, 8), 0, rng.randi_range(0, 1))]
		_:
			if local.is_empty() and template_id != &"district_buffer":
				return []
	var result: Array[EnvironmentModulePlacement] = []
	for placement in local:
		result.append(_rotate_into_parcel(placement, catalog[placement.component_id], parcel, rotation))
	return result

static func _semantic_frontage_placements(parcel_size: Vector2i, catalog: Dictionary, rng: RandomNumberGenerator, shell_id: StringName, tangent_offset := 0) -> Array[EnvironmentModulePlacement]:
	var result: Array[EnvironmentModulePlacement] = [
		EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i.ZERO),
		EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i(10, 0)),
		EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i(0, 10)),
		EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i(10, 10)),
	]
	if not catalog.has(shell_id):
		return result
	var shell: EnvironmentModuleDefinition = catalog[shell_id]
	var shell_origin := Vector2i(floori(float(parcel_size.x - shell.size.x) * 0.5) + tangent_offset, 0)
	result.append(EnvironmentModulePlacement.new(shell_id, shell_origin))
	# The remaining authored pieces describe a purpose: a lit public frontage,
	# plus either a side service machine, container staging, or waste pickup.
	# Each choice is derived from the actual shell dimensions and must still pass
	# normal footprint, clearance and calibrated-envelope validation.
	if shell.size.x <= 14 and shell.size.y <= 15:
		result.append(EnvironmentModulePlacement.new(&"service_dumpster", Vector2i(0, maxi(2, shell.size.y - 3)), 1))
		result.append(EnvironmentModulePlacement.new(&"street_light", Vector2i(parcel_size.x - 2, parcel_size.y - 2), 2, rng.randi_range(0, 1)))
	else:
		result.append(EnvironmentModulePlacement.new(&"service_dumpster", Vector2i(1, parcel_size.y - 3), 1))
		result.append(EnvironmentModulePlacement.new(&"street_light", Vector2i(parcel_size.x - 2, parcel_size.y - 2), 2, rng.randi_range(0, 1)))
	return result

static func _rotate_into_parcel(placement: EnvironmentModulePlacement, definition: EnvironmentModuleDefinition, parcel: Rect2i, rotation: int) -> EnvironmentModulePlacement:
	var transformed: Array[Vector2i] = []
	for cell in definition.rotated_cells(definition.footprint_cells, placement.rotation):
		var point := placement.origin + cell
		for _step in posmod(rotation, 4):
			point = Vector2i(parcel.size.y - 1 - point.y, point.x)
		transformed.append(point)
	var minimum := transformed[0]
	for point in transformed:
		minimum.x = mini(minimum.x, point.x)
		minimum.y = mini(minimum.y, point.y)
	return EnvironmentModulePlacement.new(placement.component_id, parcel.position + minimum, placement.rotation + rotation, placement.variation, placement.elevation)

static func _try_batch(layout: EnvironmentModuleLayout, batch: Array[EnvironmentModulePlacement], catalog: Dictionary, map_size: Vector2i, reservations = null, owner_ref := "", template_id: StringName = &"") -> bool:
	var accepted: Array[EnvironmentModulePlacement] = []
	for placement in batch:
		var required := _occupant_is_required(template_id, placement.component_id)
		if reservations != null:
			var reserved: Dictionary = reservations.placement_allowed(catalog[placement.component_id], placement, layout, owner_ref)
			if not reserved.ok:
				if not required: continue
				layout.errors.append("%s: %s" % [reserved.code, reserved.message])
				return false
		var error_count := layout.errors.size()
		if not layout.try_add(catalog[placement.component_id], placement, map_size):
			if not required:
				layout.errors.resize(error_count)
				continue
			return false
		accepted.append(placement)
	batch.assign(accepted)
	return true

static func _try_add_reserved(layout: EnvironmentModuleLayout, definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, map_size: Vector2i, reservations, owner_ref := "") -> bool:
	var allowed: Dictionary = reservations.placement_allowed(definition, placement, layout, owner_ref)
	if not allowed.ok: return false
	var error_count := layout.errors.size()
	var accepted := layout.try_add(definition, placement, map_size)
	if not accepted: layout.errors.resize(error_count)
	return accepted

static func _reserve_parcel_access(reservations, parcel: Dictionary, template_id: StringName, span := {}, placements: Array = [], catalog: Dictionary = {}) -> bool:
	var role := ParcelContract.reservation_role_for_template(String(template_id))
	if role.is_empty(): return true
	if span.is_empty():
		reservations.failures.append({"code": "MISSING_REQUIRED_ACCESS", "reservation_id": "access_%s" % parcel.id, "message": "%s requires road frontage" % template_id})
		return false
	var checked_parcel := parcel.duplicate(true)
	if not span.is_empty(): checked_parcel["rotation"] = RelationshipValidator.rotation_for_frontage(String(template_id), span)
	var cells := RelationshipValidator.relationship_cells(checked_parcel, String(template_id), placements, catalog, span) if not placements.is_empty() else ReservationLedger.frontage_access_cells(span, parcel.bounds, role)
	return reservations.try_reserve({
		"reservation_id": "access_%s" % parcel.id,
		"owner_ref": "parcel:%s" % parcel.id,
		"role": role,
		"purpose": ParcelContract.relationship_kind_for_template(String(template_id)),
		"cells": cells,
		"required": true,
		"source_ref": "frontage:%s" % span.get("frontage_id", ""),
	})

static func _clone_layout(source: EnvironmentModuleLayout, catalog: Dictionary, map_size: Vector2i) -> EnvironmentModuleLayout:
	var result := EnvironmentModuleLayout.new(source.layout_id, source.generation_seed)
	for placement in source.placements:
		if not result.try_add(catalog[placement.component_id], placement, map_size):
			return null
	return result

static func _shuffle(values: Array[StringName], rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := values[index]
		values[index] = values[swap_index]
		values[swap_index] = held

static func _shuffle_vector_cells(values: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := values[index]
		values[index] = values[swap_index]
		values[swap_index] = held
