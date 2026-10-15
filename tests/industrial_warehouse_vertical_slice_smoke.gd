extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var ordinary := FlatMapGenerator.generate_with_cover(40, 30, 1.0, 940059876)
	check(ordinary.get_inspectable_elevation_levels() == [0], "Unlabelled terrain elevations do not become building floor controls")
	for map_seed in [1, 940059876]:
		var data := FlatMapGenerator.generate_with_cover(40, 30, 1.0, map_seed, 5, false, true)
		var repeated := FlatMapGenerator.generate_with_cover(40, 30, 1.0, map_seed, 5, false, true)
		var graph := Pathfinder.new()
		MapGraphBuilder.build(data, graph)
		MissionZonePlanner.populate_defaults(data, graph)
		var validation := MapValidator.validate(data, graph, {
			TacticalUnit.Faction.PLAYER: 5,
			TacticalUnit.Faction.ALLY: 5,
			TacticalUnit.Faction.ENEMY: 5,
		})
		check(data.source_kind == IndustrialWarehouseLayoutBuilder.SOURCE_KIND, "Industrial source kind is explicit")
		check(data.get_walkable_elevation_levels() == [0, 2, 5], "Authoritative walkable levels drive generic floor controls")
		check(data.get_inspectable_elevation_levels() == [0, 2, 5], "Only explicitly described tactical levels appear in floor controls")
		check(data.get_elevation_label(2) == "Walkway" and data.get_elevation_label(5) == "Roof", "Layout supplies presentation labels without owning floor UI")
		check(_layout_signature(data) == _layout_signature(repeated), "Seed %d reproduces the same authoritative industrial layout" % map_seed)
		check(validation.is_valid(), "Seed %d validates: %s" % [map_seed, validation.describe()])
		check(data.platforms.size() == 1 and data.generated_traversals.size() == 2, "Warehouse has maintenance and rooftop ladder access")
		check(not graph.calculate_3d_path(IndustrialWarehouseLayoutBuilder.ROOF_LADDER_BOTTOM, IndustrialWarehouseLayoutBuilder.ROOF_LADDER_TOP).is_empty(), "Roof ladder connects ground and roof")
		check(not graph.calculate_3d_path(IndustrialWarehouseLayoutBuilder.ROOF_LADDER_TOP, IndustrialWarehouseLayoutBuilder.ROOF_LADDER_BOTTOM).is_empty(), "Roof ladder supports descent")
		var slab := data.get_cell(Vector3i(18, 4, 10))
		check(not slab.walkable and slab.blocks_line_of_sight, "Roof slab blocks fire without occupying the interior")
		check(CombatRules._segment_enters_obstacle(slab.world_position - Vector3.UP, slab.world_position + Vector3.UP, slab, 1.0), "Shots cannot cross the roof slab")
		for footprint in IndustrialWarehouseLayoutBuilder.CONTAINER_SPECS + IndustrialWarehouseLayoutBuilder.CONVEYOR_SPECS + [IndustrialWarehouseLayoutBuilder.CRANE_FOOTPRINT]:
			for x in range(footprint.position.x, footprint.end.x):
				for z in range(footprint.position.y, footprint.end.y):
					check(not data.get_cell(Vector3i(x, 0, z)).walkable, "Solid industrial props have matching authoritative footprints")
		check(not graph.calculate_3d_path(data.get_spawn_cells(TacticalUnit.Faction.PLAYER)[0], data.get_spawn_cells(TacticalUnit.Faction.ENEMY)[0]).is_empty(), "Opposing deployments remain connected")
		for zone_id in [&"reach", &"terminal", &"extract", &"enemy_extract", &"rescue_spawn"]:
			check(not data.get_objective_zone(zone_id).is_empty(), "Seed %d places %s" % [map_seed, zone_id])

	var presented := FlatMapGenerator.generate_with_cover(40, 30, 1.0, 777, 5, false, true)
	var root_3d := Node3D.new()
	root.add_child(root_3d)
	GeneratedTerrainPresenter.build(presented, root_3d, 1.0)
	var assets := root_3d.get_node_or_null("IndustrialWarehouseAssets")
	check(assets != null and assets.get_child_count() >= 40, "Presenter instantiates the representative industrial asset set")
	for child in assets.get_children():
		if not child.has_meta("asset_path"):
			continue
		var bounds := EnvironmentAssetPlacement.mesh_bounds(child)
		var limits: Vector3 = child.get_meta("placement_limits")
		var floor_center: Vector3 = child.get_meta("floor_center")
		check(bounds.size.x <= limits.x + 0.001 and bounds.size.y <= limits.y + 0.001 and bounds.size.z <= limits.z + 0.001, "Imported hierarchy fits reserved envelope: " + str(child.name))
		check(absf(bounds.position.y - floor_center.y) < 0.001, "Imported model rests on its intended floor")
		check(absf(bounds.get_center().x - floor_center.x) < 0.001 and absf(bounds.get_center().z - floor_center.z) < 0.001, "Rotated imported model stays centered")
		check(is_equal_approx(child.scale.x, child.scale.y) and is_equal_approx(child.scale.y, child.scale.z), "Vendor proportions are preserved")
	var roof := assets.get_node("WarehouseRoof") as WarehouseRoofCutaway
	var outside := Vector3(0, 9, 25)
	roof.update_view(outside, [Vector3(0, 1, 15)])
	check(roof.visible, "Roof is visible for an unobstructed exterior subject")
	roof.update_view(outside, [roof.global_position + Vector3.UP])
	check(not roof.visible, "Interior focus hides roof")
	roof.update_view(outside, [roof.global_position + Vector3.UP * 3.5])
	check(not roof.visible, "Elevated walkway focus hides roof")
	roof.update_view(outside, [roof.global_position + Vector3.UP * 6.0])
	check(roof.visible, "Rooftop subject keeps its floor visible")
	roof.update_view(outside, [Vector3(0, 1, 15)])
	check(roof.visible, "Leaving interior restores roof")
	var wall := assets.get_node("Wall_12_17") as TacticalVisualOccluder
	var wall_center := wall.occlusion_bounds.get_center()
	wall.update_view(wall_center + Vector3.BACK * 5, [wall_center + Vector3.FORWARD * 5])
	check(wall.get_child(0).transparency > 0.8, "Visual-only warehouse walls fade without physics colliders")
	wall.restore_view()
	check(wall.get_child(0).transparency == 0.0, "Visual-only walls restore their original opacity")
	check(root_3d.get_children().any(func(child: Node) -> bool: return child.name.begins_with("Traversal_")), "Presenter draws the maintenance-walkway access")
	root_3d.queue_free()
	await process_frame
	print("Industrial warehouse vertical slice: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _layout_signature(data: MapData) -> String:
	var entries: Array[String] = []
	for cell: MapCellData in data.cells.values():
		if cell.cover_type != MapCellData.CoverType.NONE or cell.grid_position.y > 0:
			entries.append("%s:%d:%s:%s" % [cell.grid_position, cell.cover_type, cell.walkable, cell.can_stop])
	entries.sort()
	return "|".join(entries)

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
