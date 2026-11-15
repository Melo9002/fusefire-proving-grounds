extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	for dimensions in FlatMapGenerator.MAP_SIZES:
		for map_seed in range(1, 101):
			var data := FlatMapGenerator.generate_with_cover(dimensions.x, dimensions.y, 1.0, map_seed)
			var repeated := FlatMapGenerator.generate_with_cover(dimensions.x, dimensions.y, 1.0, map_seed)
			check(not data.platforms.is_empty(), "Every supported map generates an elevated platform")
			check(data.hills.size() == (1 if dimensions == Vector2i(40, 30) else 0), "Only the large map generates one hill")
			check(_signature(data) == _signature(repeated), "The same seed reproduces generated elevations")
			var graph := Pathfinder.new()
			MapGraphBuilder.build(data, graph)
			check(MapValidator.validate(data, graph).is_valid(), "Generated elevation passes map validation")
			for platform in data.platforms:
				check(platform.cells.size() == platform.footprint.size.x * platform.footprint.size.y, "Platform data covers its footprint")
				_check_platform_support_cells(data, platform)
				for position in platform.cells:
					var cell := data.get_cell(position)
					check(cell != null and cell.walkable and cell.can_stop, "Elevated platform cell is a legal stopping cell")
					check(graph.grid_to_id_map.has(position), "Elevated platform cell enters the path graph")
				var route := graph.calculate_3d_path(platform.cells[0], platform.cells[-1])
				check(not route.is_empty(), "Platform surface has internal pathfinding")
			for hill in data.hills:
				_check_hill(data, graph, hill)
	_check_invalid_platform_is_rejected()

	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	# Explicit historical fixture: this suite protects generated structure geometry.
	var config := BattleConfiguration.new()
	config.player_count = 2
	config.enemy_count = 2
	config.ally_count = 0
	config.generated_map = true
	config.battle_seed = 12345
	config.map_size = Vector2i(32,24)
	config.select_battlefield(BattlefieldCatalog.GENERATED_COVER)
	level.configure_battle(config)
	root.add_child(level)
	await create_timer(0.2).timeout
	var data := level.battle_controller.grid_manager.map_data
	var terrain := level.get_node("GeneratedTerrain")
	var rendered := terrain.get_children().filter(func(child: Node) -> bool: return child.name.begins_with("Platform_"))
	check(rendered.size() == data.platforms.size(), "Presenter creates one structure per platform record")
	for platform_node in rendered:
		var meshes: Array[MeshInstance3D] = []
		for child in platform_node.get_children():
			if child is MeshInstance3D:
				meshes.append(child)
		check(meshes.size() == 5, "Platform presentation contains one deck and four supports")
		for support in meshes.slice(1):
			check(support.position.y < meshes[0].position.y, "Platform supports remain below the deck")
	for platform in data.platforms:
		var point := data.get_cell(platform.cells[0]).world_position
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.4, point - Vector3.UP * 0.4, 2)
		var hit := level.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and level.battle_controller.grid_manager.world_to_grid(hit.position) == platform.cells[0], "Platform click surface resolves to its elevated cell")
	level.queue_free()
	await process_frame
	await _check_large_map_hill_presentation()

	print("Generated elevation: 300 seeds across three sizes; %d failures" % failures)
	quit(1 if failures else 0)

func _check_invalid_platform_is_rejected() -> void:
	var data := FlatMapGenerator.generate_with_cover(32, 24, 1.0, 8080)
	var platform: GeneratedPlatformData = data.platforms[0]
	data.get_cell(platform.cells[0]).can_stop = false
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	var validation := MapValidator.validate(data, graph)
	check(validation.has_code("PLATFORM_CELL_INVALID"), "Validation rejects an unusable platform surface")

func _check_platform_support_cells(data: MapData, platform: GeneratedPlatformData) -> void:
	var footprint := platform.footprint
	var corners: Array[Vector2i] = [
		footprint.position,
		Vector2i(footprint.end.x - 1, footprint.position.y),
		Vector2i(footprint.position.x, footprint.end.y - 1),
		footprint.end - Vector2i.ONE,
	]
	for corner in corners:
		var ground := data.get_cell(Vector3i(corner.x, 0, corner.y))
		check(not ground.walkable and not ground.can_stop, "Platform support ground cell cannot be occupied")

func _check_hill(data: MapData, graph: Pathfinder, hill: GeneratedHillData) -> void:
	check(hill.surface_cells.size() == 49, "Large-map hill covers a 7 by 7 footprint")
	var levels: Dictionary = {}
	for position in hill.surface_cells:
		levels[position.y] = true
		var surface := data.get_cell(position)
		var base := data.get_cell(Vector3i(position.x, 0, position.z))
		check(surface != null and surface.walkable and surface.can_stop, "Hill surface is legal terrain")
		check(base != null and not base.walkable and base.blocks_line_of_sight, "Hill has solid terrain beneath its surface")
	check(levels.has(1) and levels.has(2) and levels.has(3), "Hill contains three elevation tiers")
	var outside := Vector3i(hill.footprint.position.x - 1, 0, hill.footprint.position.y)
	var summit: Vector3i = hill.surface_cells.filter(func(position: Vector3i) -> bool: return position.y == 3)[0]
	check(not graph.calculate_3d_path(outside, summit).is_empty(), "Hill summit is reachable through ordinary one-level terrain steps")

func _check_large_map_hill_presentation() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	# Explicit historical fixture: this suite protects generated structure geometry.
	var config := BattleConfiguration.new()
	config.player_count = 2
	config.enemy_count = 2
	config.ally_count = 0
	config.generated_map = true
	config.battle_seed = 54321
	config.map_size = Vector2i(40,30)
	config.select_battlefield(BattlefieldCatalog.GENERATED_COVER)
	level.configure_battle(config)
	root.add_child(level)
	await create_timer(0.2).timeout
	var grid := level.battle_controller.grid_manager
	var terrain := level.get_node("GeneratedTerrain")
	var hill_nodes := terrain.get_children().filter(func(child: Node) -> bool: return child.name.begins_with("Hill_"))
	check(hill_nodes.size() == 1, "Large-map presenter creates one hill structure")
	var hill_mesh := hill_nodes[0].get_child(0) as MeshInstance3D
	check(hill_mesh.mesh.get_aabb().position.y >= GeneratedTerrainPresenter.HILL_SKIRT_CLEARANCE - 0.001, "Hill skirt remains above the floor to avoid z-fighting")
	var hill: GeneratedHillData = grid.map_data.hills[0]
	var summit: Vector3i = hill.surface_cells.filter(func(position: Vector3i) -> bool: return position.y == 3)[0]
	var point := grid.map_data.get_cell(summit).world_position
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.4, point - Vector3.UP * 0.4, 2)
	var hit := level.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and grid.world_to_grid(hit.position) == summit, "Hill summit click surface resolves to its elevated cell")
	level.queue_free()
	await process_frame

func _signature(data: MapData) -> Array[String]:
	var signature: Array[String] = []
	for platform in data.platforms:
		signature.append("%s:%d:%s" % [platform.footprint, platform.elevation_level, platform.cells])
	for hill in data.hills:
		signature.append("hill:%s:%s" % [hill.footprint, hill.surface_cells])
	signature.sort()
	return signature
