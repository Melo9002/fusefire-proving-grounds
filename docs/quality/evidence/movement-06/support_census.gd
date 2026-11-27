extends SceneTree
## Compare machine-readable normalized point/edge records from two checkouts.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if "placement-only" in OS.get_cmdline_user_args():
		_measure_placement()
		quit()
		return
	for id in [BattlefieldCatalog.SERVICE_DEPOT, BattlefieldCatalog.FREIGHT_YARD,
		BattlefieldCatalog.FLEET_STATION, BattlefieldCatalog.TACTICAL_TEST_RANGE,
		BattlefieldCatalog.CONTEXTUAL_BAY, BattlefieldCatalog.PARKING_GARAGE, &"partial_support"]:
		for seed_value in ([16, 17, 950507647] if id in BattlefieldCatalog.PLAYABLE else [16]):
			_measure(id, seed_value)
	quit()

func _make(id: StringName, seed_value: int) -> MapData:
	if id != &"partial_support":
		return BattlefieldCatalog.generate(id, Vector2i(40, 40), seed_value, 1.0)
	var data := _partial_fixture(seed_value)
	SurfaceNavigation.resolve_map(data, 1.0)
	return data

func _partial_fixture(seed_value: int) -> MapData:
	var data := TacticalMapBuilder.generate(7, 7, 1.0, seed_value)
	data.surface_placement_enabled = true
	data.get_cell(Vector3i(4, 0, 3)).support_surface = false
	data.movement_parts.append(AABB(Vector3(-0.45, 0, -0.10), Vector3(0.46, 1.8, 0.2)))
	return data

func _measure_placement() -> void:
	var legacy_us: Array[int] = []
	var corrected_us: Array[int] = []
	for sample in 224:
		for enabled in ([false, true] if sample % 2 == 0 else [true, false]):
			var data := _partial_fixture(16)
			var start := Time.get_ticks_usec()
			SurfaceNavigation.resolve_map.bind(enabled).call(data, 1.0)
			var elapsed := Time.get_ticks_usec() - start
			if sample >= 24:
				var bucket := corrected_us if enabled else legacy_us
				bucket.append(elapsed)
	print("[SurfacePlacementTiming] ", JSON.stringify({"legacy_us": _timings(legacy_us), "corrected_us": _timings(corrected_us)}))

func _measure(id: StringName, seed_value: int) -> void:
	var key := "%s/%d" % [id, seed_value]
	var compile_us: Array[int] = []
	var graph_us: Array[int] = []
	var graph := Pathfinder.new()
	var data: MapData
	for sample in 6:
		var start := Time.get_ticks_usec()
		data = _make(id, seed_value)
		var built := Time.get_ticks_usec()
		MapGraphBuilder.build(data, graph)
		if sample > 0:
			compile_us.append(built - start)
			graph_us.append(Time.get_ticks_usec() - built)
	var cells := {}
	var edges: Array[String] = []
	var invalid := []
	var stops := 0
	var transit := 0
	for cell: MapCellData in data.cells.values():
		var index: int = graph.grid_to_id_map[cell.grid_position]
		var from := str(cell.grid_position)
		if cell.can_stop and cell.walkable:
			stops += 1
			cells[from] = str((cell.world_position * 10000).round())
			if data.surface_placement_enabled and (not SurfaceNavigation.supported(data, cell.world_position, data.body_radius)
				or not SurfaceNavigation.body_clear(data, cell.world_position)):
				invalid.append(from)
		elif cell.walkable:
			transit += 1
		for neighbor in graph.astar.get_point_connections(index):
			edges.append(from + ">" + str(graph.id_to_grid_map[neighbor]))
	edges.sort()
	var origin: Vector3i = data.get_spawn_cells(TacticalUnit.Faction.PLAYER)[0] if not data.get_spawn_cells(TacticalUnit.Faction.PLAYER).is_empty() else Vector3i(3, 0, 4)
	var options := graph.get_reachable_cells(origin, 5)
	var target: Vector3i = options.back() if not options.is_empty() else origin
	var inventory_us: Array[int] = []
	var route_us: Array[int] = []
	for sample in 112:
		var start := Time.get_ticks_usec()
		graph.get_reachable_cells(origin, 5)
		var queried := Time.get_ticks_usec()
		graph.calculate_3d_path(origin, target)
		if sample >= 12:
			inventory_us.append(queried - start)
			route_us.append(Time.get_ticks_usec() - queried)
	print("[SurfaceCensus] ", JSON.stringify({"case": key, "logical": data.cells.size(), "stops": stops, "transit": transit,
		"errors": data.generation_errors, "invalid": invalid, "points": cells, "edges": edges,
		"signature": SurfaceNavigation.signature(data), "compiler": data.content_manifest.get("compiler_revision", 0),
		"geometry_key": [data.movement_parts.size(), data.curved_parts.size(), data.shot_obstacles.size()],
		"compile_us": _timings(compile_us), "graph_us": _timings(graph_us),
		"inventory_us": _timings(inventory_us), "route_us": _timings(route_us), "options": options.size()}))

func _timings(times: Array[int]) -> Array[int]:
	times.sort()
	return [times[times.size() / 2], times[ceili(times.size() * 0.95) - 1]]
