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
			check(not data.buildings.is_empty(), "Every supported map size generates a building")
			check(_building_signature(data) == _building_signature(repeated), "Building data reproduces from its seed")
			var graph := Pathfinder.new()
			MapGraphBuilder.build(data, graph)
			check(MapValidator.validate(data, graph).is_valid(), "Building map remains valid and connected")
			for building in data.buildings:
				_check_building(data, graph, building)

	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(2, 2, true, 12345, 1, Vector2i(32, 24))
	root.add_child(level)
	await create_timer(0.2).timeout
	var terrain := level.get_node("GeneratedTerrain")
	var building_nodes := terrain.get_children().filter(func(child: Node) -> bool: return child.name.begins_with("Building_"))
	check(building_nodes.size() == level.battle_controller.grid_manager.map_data.buildings.size(), "Presenter creates one structure per building record")
	for building_node in building_nodes:
		var roof := building_node.get_node_or_null("RoofInputSurface") as StaticBody3D
		check(roof != null and roof.collision_layer == 2, "Generated roofs expose a floor-click surface")
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var building := grid.map_data.buildings[0]
	for position in building.stair_cells + building.upper_cells:
		var point := grid.map_data.get_cell(position).world_position
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.4, point - Vector3.UP * 0.4, 2)
		var hit := level.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and grid.world_to_grid(hit.position) == position, "Click surface matches generated elevation")
	var unit := level.turn_manager.player_units[0]
	var start := building.stair_ground_cell
	grid.update_unit_position(unit, unit.grid_position, start)
	unit.global_position = grid.map_data.get_cell(start).world_position + Vector3.UP * unit.standing_height
	var ap_before_stairs := unit.stats.current_ap
	check(await battle.try_move(unit, building.stair_cells[-1]), "Shared Move action climbs generated stairs")
	check(unit.grid_position == building.stair_cells[-1] and unit.stats.current_ap == ap_before_stairs - 1, "Stair movement spends one AP and registers elevated occupancy")
	if not building.upper_cells.is_empty():
		var upper := building.upper_ladder_roof_cell
		grid.update_unit_position(unit, unit.grid_position, building.upper_ladder_ground_cell)
		unit.global_position = grid.map_data.get_cell(building.upper_ladder_ground_cell).world_position + Vector3.UP * unit.standing_height
		check(await battle.try_move(unit, upper), "Shared Move action climbs upper ladder")
		check(is_equal_approx(unit.global_position.y, grid.map_data.get_cell(upper).world_position.y + unit.standing_height), "Unit finishes on upper lookout surface")
	level.queue_free()
	await process_frame

	print("Generated buildings: 300 seeds across three sizes; %d failures" % failures)
	quit(1 if failures else 0)

func _check_building(data: MapData, graph: Pathfinder, building: GeneratedBuildingData) -> void:
	var roof_count := 0
	for x in range(building.footprint.position.x, building.footprint.end.x):
		for z in range(building.footprint.position.y, building.footprint.end.y):
			var ground := data.get_cell(Vector3i(x, 0, z))
			var roof := data.get_cell(Vector3i(x, building.roof_level, z))
			check(ground != null and not ground.walkable and ground.blocks_line_of_sight, "Building footprint is solid terrain")
			check(roof != null, "Every building footprint cell has a roof cell")
			roof_count += 1 if roof else 0
	check(roof_count == building.footprint.size.x * building.footprint.size.y, "Roof covers the full building footprint")
	var bottom := data.get_cell(building.ladder_ground_cell)
	var top := data.get_cell(building.ladder_roof_cell)
	check(bottom != null and bottom.walkable and bottom.can_stop, "Ladder begins on valid ground")
	check(top != null and top.walkable and top.can_stop, "Ladder ends on a valid roof")
	check(not graph.calculate_3d_path(building.ladder_ground_cell, building.ladder_roof_cell).is_empty(), "Ladder joins ground and roof pathfinding")
	check(not building.stair_cells.is_empty(), "Supported building has an alternate stair route")
	for upper in building.upper_cells:
		check(not graph.calculate_3d_path(building.ladder_ground_cell, upper).is_empty(), "Upper lookout is reachable from ground")
	if not building.upper_cells.is_empty():
		check(building.upper_footprint.size == Vector2i(2, 2) and building.upper_cells.size() == 4, "Upper floor is a coherent 2 by 2 structure")
		check(not building.upper_footprint.has_point(Vector2i(building.upper_ladder_ground_cell.x, building.upper_ladder_ground_cell.z)), "Upper ladder keeps a clear roof landing")
	for link in data.traversal_links:
		graph.astar.disconnect_points(graph.grid_to_id_map[link.from_cell], graph.grid_to_id_map[link.to_cell])
	if not building.stair_cells.is_empty():
		check(not graph.calculate_3d_path(building.stair_ground_cell, building.ladder_roof_cell).is_empty(), "Stairs reach roof independently of ladders")
	for link in data.traversal_links:
		graph.connect_cells(link.from_cell, link.to_cell, link.bidirectional)

func _building_signature(data: MapData) -> Array[String]:
	var signature: Array[String] = []
	for building in data.buildings:
		signature.append("%s:%d:%s:%s" % [building.footprint, building.roof_level, building.ladder_ground_cell, building.ladder_roof_cell])
		signature.append("%s:%s:%s:%s:%s" % [building.stair_ground_cell, building.stair_cells, building.upper_footprint, building.upper_cells, building.upper_ladder_ground_cell])
	signature.sort()
	return signature
