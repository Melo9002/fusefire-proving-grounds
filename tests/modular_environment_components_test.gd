extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog := IndustrialModuleCatalog.create()
	check(catalog.size() == 9, "The industrial family exposes nine bounded components")

	var connection_layout := EnvironmentModuleLayout.new(&"connection_fixture", 1)
	var first := EnvironmentModulePlacement.new(&"road_straight", Vector2i.ZERO, 1)
	var second := EnvironmentModulePlacement.new(&"road_straight", Vector2i(10, 0), 1)
	check(connection_layout.try_add(catalog[first.component_id], first, Vector2i(30, 20)), "First rotated road is legal")
	check(connection_layout.try_add(catalog[second.component_id], second, Vector2i(30, 20)), "Second rotated road is legal")
	check(connection_layout.placements_connect(first, second, catalog), "Quarter-turn rotation preserves compatible road edges")
	var overlap := EnvironmentModulePlacement.new(&"factory_wall_corner", Vector2i(10, 0))
	check(not connection_layout.try_add(catalog[overlap.component_id], overlap, Vector2i(30, 20)), "A component cannot overlap an existing reserved footprint")

	var first_map := FlatMapGenerator.generate_modular_industrial_sample(40, 30, 1.0, 7319)
	var second_map := FlatMapGenerator.generate_modular_industrial_sample(40, 30, 1.0, 7319)
	check(first_map.source_kind == ModularIndustrialLayoutBuilder.SOURCE_KIND, "Modular industrial generation is explicit and opt-in")
	check(_signature(first_map) == _signature(second_map), "Identical seed and inputs reproduce the module layout and tactical cells")
	check(first_map.environment_modules.size() == 11, "The sample combines structure, ground, cargo and vaultable components")
	var sample_layout := EnvironmentModuleLayout.new(&"sample_connections", 7319)
	for placement in first_map.environment_modules:
		check(sample_layout.try_add(catalog[placement.component_id], placement, first_map.map_size), "Sample placement remains legal: %s" % placement.component_id)
	check(sample_layout.placements_connect(_find(first_map, &"road_straight"), _find(first_map, &"paving_square"), catalog), "Road edge connects explicitly to the paved frontage")
	check(sample_layout.placements_connect(_find(first_map, &"factory_doorway_wide"), _find(first_map, &"paving_square"), catalog), "Doorway exterior connects explicitly to paving")

	var graph := Pathfinder.new()
	MapGraphBuilder.build(first_map, graph)
	var interior := Vector3i(15, 0, 18)
	var doorway := Vector3i(15, 0, 19)
	var pavement := Vector3i(15, 0, 20)
	check(first_map.get_cell(interior).walkable and first_map.get_cell(doorway).walkable and first_map.get_cell(pavement).walkable, "Entrance clearance remains traversable")
	check(not graph.calculate_3d_path(interior, pavement).is_empty(), "The interior reaches exterior paving through the declared doorway")
	var wall := first_map.get_cell(Vector3i(12, 0, 19))
	check(not wall.walkable and wall.cover_type == MapCellData.CoverType.FULL and wall.blocks_line_of_sight, "Wall module writes authoritative blocking cells")
	var cargo := first_map.get_cell(Vector3i(24, 0, 19))
	check(not cargo.walkable and cargo.cover_type == MapCellData.CoverType.FULL, "Cargo module translates its footprint into authoritative cover")
	check(catalog.cargo_container.tactical_role == EnvironmentModuleDefinition.TacticalRole.SOLID_OBSTACLE, "Container semantics explicitly identify a solid tactical obstacle")
	var barrier := first_map.get_cell(Vector3i(22, 0, 24))
	check(barrier.walkable and not barrier.can_stop and barrier.cover_type == MapCellData.CoverType.LOW and barrier.movement_cost == 2, "Vaultable module writes the existing low-cover traversal contract")
	check(catalog.construction_barrier_vault.interaction_at(Vector2i.ZERO) == EnvironmentModuleDefinition.CellInteraction.VAULT, "Vault animation intent is explicit module metadata")
	check(catalog.road_straight.tactical_role == EnvironmentModuleDefinition.TacticalRole.GROUND and catalog.road_straight.cell_effects.is_empty(), "Road visuals remain ordinary tactical ground")
	check(catalog.factory_wall_corner.visuals[0].yaw_quarters == 2, "Outer corner visual faces into both connected wall runs")

	var presented := Node3D.new()
	root.add_child(presented)
	GeneratedTerrainPresenter.build(first_map, presented, 1.0)
	var modular_root := presented.get_node_or_null("ModularEnvironment")
	check(modular_root != null and modular_root.get_child_count() == first_map.environment_modules.size(), "Presenter creates one visual group per module placement")
	presented.queue_free()
	await process_frame
	var preview = load("res://tools/modular_environment_preview.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	preview._frame_camera()
	check(preview.orbit.focus.is_equal_approx(Vector3(0, 4, 0)), "Preview frames the centered MapData world bounds")
	check(preview.content.get_node_or_null("TacticalGrid") != null, "Preview exposes a grid overlay for visual footprint inspection")
	check("VALID" in preview.status.text, "Preview reports the generated modular layout as valid")
	preview.queue_free()
	await process_frame
	print("Modular environment components: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _signature(data: MapData) -> String:
	var modules: Array[String] = []
	for placement in data.environment_modules:
		modules.append(placement.signature())
	var effects: Array[String] = []
	for cell: MapCellData in data.cells.values():
		if cell.cover_type != MapCellData.CoverType.NONE:
			effects.append("%s:%d:%s:%s" % [cell.grid_position, cell.cover_type, cell.walkable, cell.blocks_line_of_sight])
	modules.sort()
	effects.sort()
	return "%s#%s" % ["|".join(modules), "|".join(effects)]

func _find(data: MapData, id: StringName) -> EnvironmentModulePlacement:
	for placement in data.environment_modules:
		if placement.component_id == id:
			return placement
	return null

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
