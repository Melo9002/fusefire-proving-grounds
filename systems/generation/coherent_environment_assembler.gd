class_name CoherentEnvironmentAssembler
extends RefCounted

const SOURCE_KIND := "generated_modular_coherent"
const MACRO_SIZE := 10
const ENVIRONMENTS: Array[StringName] = [&"industrial_district", &"commercial_street", &"mixed_service"]
const MAX_TEMPLATE_ATTEMPTS := 6

static func apply(data: MapData, cell_size: float, map_seed: int, environment_id: StringName = &"industrial_district") -> EnvironmentModuleLayout:
	var catalog := IndustrialModuleCatalog.create()
	var plan := EnvironmentLayoutPlan.new(environment_id, map_seed)
	plan.macro_size = MACRO_SIZE
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
	var parcels := _derive_parcels(plan, data.map_size)
	var populated := 0
	for parcel in parcels:
		var candidates := _template_candidates(environment_id, populated, not parcel.road_edges.is_empty(), rng)
		var accepted := false
		for template_id in candidates.slice(0, mini(MAX_TEMPLATE_ATTEMPTS, candidates.size())):
			plan.search_attempts += 1
			var facing: Vector2i = parcel.road_edges[0] if not parcel.road_edges.is_empty() else Vector2i.DOWN
			var rotation := _rotation_facing(facing)
			var batch := _template_placements(template_id, parcel.bounds, rotation, rng)
			var candidate := _clone_layout(layout, catalog, data.map_size)
			if candidate == null or not _try_batch(candidate, batch, catalog, data.map_size):
				var reason: String = candidate.errors.back() if candidate != null and not candidate.errors.is_empty() else "candidate replay failed"
				plan.rejected_candidates.append("%s rejected %s: %s" % [parcel.id, template_id, reason])
				continue
			layout = candidate
			parcel.template = template_id
			parcel.rotation = rotation
			plan.decisions.append("%s -> %s r%d" % [parcel.id, template_id, rotation])
			accepted = true
			populated += 1
			break
		if not accepted:
			plan.fallback_used = true
			parcel.template = &"open_ground"
			parcel.rotation = 0
			plan.decisions.append("%s -> open_ground fallback" % parcel.id)
		plan.parcels.append(parcel)
	EnvironmentModuleMapWriter.apply(data, layout, catalog, cell_size)
	_repair_deployment_cells(data, plan)
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

static func _derive_parcels(plan: EnvironmentLayoutPlan, map_size: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var road_lookup: Dictionary = {}
	for road_cell in plan.road_cells:
		road_lookup[road_cell] = true
	var columns := floori(float(map_size.x) / float(MACRO_SIZE))
	var rows := floori(float(map_size.y) / float(MACRO_SIZE))
	var index := 0
	for z in rows:
		for x in columns:
			var macro := Vector2i(x, z)
			if road_lookup.has(macro):
				continue
			var edges: Array[Vector2i] = []
			for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				if road_lookup.has(macro + direction):
					edges.append(direction)
			result.append({
				"id": StringName("parcel_%02d" % index),
				"bounds": Rect2i(macro * MACRO_SIZE, Vector2i(MACRO_SIZE, MACRO_SIZE)),
				"road_edges": edges,
				"template": &"unassigned",
				"rotation": 0,
			})
			index += 1
	return result

static func _template_candidates(environment_id: StringName, parcel_index: int, has_frontage: bool, rng: RandomNumberGenerator) -> Array[StringName]:
	var result: Array[StringName]
	if not has_frontage:
		result = [&"courtyard", &"service_alley"]
	elif parcel_index == 0:
		match environment_id:
			&"industrial_district": result = [&"loading_bay", &"workshop", &"yard"]
			&"commercial_street": result = [&"shop", &"courtyard", &"service_alley"]
			_: result = [&"yard", &"shop", &"loading_bay"]
	else:
		match environment_id:
			&"industrial_district": result = [&"loading_bay", &"yard", &"workshop", &"service_alley", &"courtyard"]
			&"commercial_street": result = [&"shop", &"courtyard", &"service_alley", &"workshop"]
			_: result = [&"shop", &"loading_bay", &"yard", &"courtyard", &"service_alley"]
	_shuffle(result, rng)
	return result

static func _template_placements(template_id: StringName, parcel: Rect2i, rotation: int, rng: RandomNumberGenerator) -> Array[EnvironmentModulePlacement]:
	var local: Array[EnvironmentModulePlacement] = []
	match template_id:
		&"shop":
			local = [EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i.ZERO), EnvironmentModulePlacement.new(&"factory_shop_front", Vector2i(1, 9))]
		&"loading_bay":
			local = [
				EnvironmentModulePlacement.new(&"industrial_loading_dock", Vector2i(0, 4)),
				EnvironmentModulePlacement.new(&"cargo_container", Vector2i(1, 4), 0, rng.randi_range(0, 2)),
				EnvironmentModulePlacement.new(&"factory_machine", Vector2i(6, 5)),
			]
		&"yard":
			local = [EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i.ZERO), EnvironmentModulePlacement.new(&"machine_cover_cluster", Vector2i(2, 5)), EnvironmentModulePlacement.new(&"construction_barrier_vault", Vector2i(8, 2))]
		&"workshop":
			local = [EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i.ZERO), EnvironmentModulePlacement.new(&"factory_window_wall", Vector2i(1, 9)), EnvironmentModulePlacement.new(&"factory_doorway_wide", Vector2i(5, 9)), EnvironmentModulePlacement.new(&"factory_machine", Vector2i(4, 5))]
		&"service_alley":
			local = [EnvironmentModulePlacement.new(&"paved_alley", Vector2i(3, 0)), EnvironmentModulePlacement.new(&"construction_barrier_vault", Vector2i(1, 4)), EnvironmentModulePlacement.new(&"construction_barrier_vault", Vector2i(8, 6))]
		_:
			local = [EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i.ZERO)]
	var result: Array[EnvironmentModulePlacement] = []
	var catalog := IndustrialModuleCatalog.create()
	for placement in local:
		result.append(_rotate_into_parcel(placement, catalog[placement.component_id], parcel, rotation))
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

static func _rotation_facing(direction: Vector2i) -> int:
	match direction:
		Vector2i.DOWN: return 0
		Vector2i.LEFT: return 1
		Vector2i.UP: return 2
		Vector2i.RIGHT: return 3
		_: return 0

static func _try_batch(layout: EnvironmentModuleLayout, batch: Array[EnvironmentModulePlacement], catalog: Dictionary, map_size: Vector2i) -> bool:
	for placement in batch:
		if not layout.try_add(catalog[placement.component_id], placement, map_size):
			return false
	return true

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

static func _repair_deployment_cells(data: MapData, plan: EnvironmentLayoutPlan) -> void:
	# Flat generation establishes faction ownership and desired deployment sides.
	# Parcel occupants may claim one of those cells, so relocate only invalid
	# positions to the nearest legal cell instead of inventing a second spawn
	# system or allowing presentation geometry to decide mission legality.
	var used: Dictionary = {}
	for faction in [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ENEMY, TacticalUnit.Faction.ALLY]:
		for zone in data.get_zones_by_kind(MapZoneData.Kind.DEPLOYMENT):
			if zone.faction != faction:
				continue
			var repaired: Array[Vector3i] = []
			for original in zone.cells:
				var chosen: Vector3i = original
				var cell := data.get_cell(chosen)
				if cell == null or not cell.walkable or not cell.can_stop or used.has(chosen):
					chosen = _nearest_deployment_cell(data, original, used)
					plan.decisions.append("deployment %s moved %s -> %s" % [zone.zone_id, original, chosen])
				if chosen != Vector3i(-1, -1, -1):
					repaired.append(chosen)
					used[chosen] = true
			zone.cells.assign(repaired)

static func _nearest_deployment_cell(data: MapData, origin: Vector3i, used: Dictionary) -> Vector3i:
	var maximum_radius := maxi(data.map_size.x, data.map_size.y)
	for radius in range(1, maximum_radius + 1):
		for dz in range(-radius, radius + 1):
			var remaining := radius - absi(dz)
			for dx in ([-remaining] if remaining == 0 else [-remaining, remaining]):
				var candidate := Vector3i(origin.x + dx, 0, origin.z + dz)
				if candidate.x < 0 or candidate.z < 0 or candidate.x >= data.map_size.x or candidate.z >= data.map_size.y or used.has(candidate):
					continue
				var cell := data.get_cell(candidate)
				if cell != null and cell.walkable and cell.can_stop:
					return candidate
	return Vector3i(-1, -1, -1)
