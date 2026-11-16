extends SceneTree
## Content contract: continuous-looking Depot scenery must not extend tactical play.
const Placement = preload("res://presentation/environment_asset_placement.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func tactical_snapshot(data: MapData) -> String:
	var cells := []
	for cell: MapCellData in data.cells.values():
		cells.append([cell.grid_position, cell.world_position, cell.walkable, cell.can_stop, cell.cover_type, cell.cover_height,
			cell.blocks_line_of_sight, cell.authored_shot_bounds, cell.authored_shot_parts, cell.movement_cost])
	return var_to_str(cells).sha256_text()

func _run() -> void:
	for map_seed in [16, 17]:
		var data := BattlefieldCatalog.generate(BattlefieldCatalog.SERVICE_DEPOT, Vector2i.ZERO, map_seed, 1.0)
		var manifest := data.content_manifest.duplicate(true)
		var before := tactical_snapshot(data)
		var host := Node3D.new()
		root.add_child(host)
		var presented := BattlefieldCatalog.present(data, host, 1.0)
		check(presented, "Depot layout presents its accepted choices")
		if not presented:
			host.free()
			continue
		var plot := host.get_child(0)
		_check_scenery_budget(plot)
		var peripheral := plot.get_node("Peripheral") as Node3D
		var yards := peripheral.get_node("NeighboringYards") as Node3D
		var boundary := plot.get_node("Tactical/PlayableBoundary") as Node3D
		check(boundary.get_meta("tactical_size") == data.map_size, "The visible boundary matches the authoritative map footprint")
		check(boundary.get_child_count() == 4, "Every edge has a visible boundary cue")
		for edge: MeshInstance3D in boundary.get_children():
			check(edge.mesh is PlaneMesh and edge.mesh.size == Vector2(40, 0.22), "Boundary is one narrow mesh spanning the full edge")
			check(is_equal_approx(absf(edge.position.x), 20) or is_equal_approx(absf(edge.position.z), 20), "Boundary cues follow the actual playable edge")
			check(edge.mesh.material is ShaderMaterial and edge.mesh.material.shader.resource_path.ends_with("playable_boundary.gdshader"), "The saved cue retains its dashed material")
		check(boundary.find_children("*", "PhysicsBody3D", true, false).is_empty(), "Boundary cues do not block entrances or road traversal")
		var background := plot.get_node("Distant/BackgroundBlocks") as Node3D
		check(background.get_child_count() == 6, "The distant placeholder uses a bounded set of buildings")
		for block in background.get_children():
			check(String(block.get_meta("asset_path", "")).contains("/low-detail-building-"), "Distant blocks use the existing low-detail asset family")
			check(block.position.length() > 70, "Simplified background buildings stay distant")
		var playable := AABB(Vector3(-20, -100, -20), Vector3(40, 200, 40))
		for mesh: MeshInstance3D in yards.find_children("*", "MeshInstance3D", true, false):
			var mesh_bounds := mesh.global_transform * mesh.get_aabb()
			check(not playable.intersects(mesh_bounds.grow(-0.002)), "New scenery does not intrude into playable cells: " + String(mesh.get_path()))
		check(yards.find_children("*", "PhysicsBody3D", true, false).is_empty(), "Neighboring yards add no physics bodies")
		check(yards.find_children("*", "NavigationRegion3D", true, false).is_empty(), "Neighboring yards add no navigation region")
		var roads := peripheral.get_children().filter(func(node): return String(node.name).begins_with("ServiceRoad"))
		check(roads.size() == 3, "The existing road has one continuous extension at each end")
		var axis := 0 if map_seed == 16 else 2
		var bounds: Array[AABB] = []
		for road: Node3D in roads: bounds.append(Placement.mesh_bounds(road))
		bounds.sort_custom(func(a, b): return a.position[axis] < b.position[axis])
		for index in range(1, bounds.size()):
			check(absf(bounds[index - 1].end[axis] - bounds[index].position[axis]) < 0.01, "Road sections meet without a gap or overlap")
			check(is_equal_approx(bounds[index - 1].position.y, bounds[index].position.y), "Road extensions keep the same ground height")
		var ground := peripheral.get_node("Surroundings") as MeshInstance3D
		var ground_bounds := ground.global_transform * ground.get_aabb()
		for road_bounds in bounds:
			check(ground_bounds.position.x <= road_bounds.position.x and ground_bounds.end.x >= road_bounds.end.x and ground_bounds.position.z <= road_bounds.position.z and ground_bounds.end.z >= road_bounds.end.z, "Extended ground supports every road section")
		check(before == tactical_snapshot(data) and data.content_manifest == manifest, "Scenery presentation changes neither tactical data nor accepted choices")
		var replayed := BattlefieldCatalog.generate(BattlefieldCatalog.SERVICE_DEPOT, Vector2i.ZERO, 999, 1.0, manifest)
		check(replayed.generation_errors.is_empty() and tactical_snapshot(replayed) == before, "Recorded Depot choices reconstruct identical tactical geometry")
		check(data.cells.size() == 1600 and data.get_cell(Vector3i(-1, 0, 0)) == null and data.get_cell(Vector3i(40, 0, 0)) == null, "The playable map remains 40 by 40")
		host.free()
	print("Depot surroundings: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_scenery_budget(plot: Node) -> void:
	# Prototype content budget measured on 2026-11-15. Timing stays an explicit
	# graphics measurement, never a hardware-dependent CI assertion.
	var meshes := 0
	var triangles := 0
	for name in ["Peripheral", "Distant"]:
		var area := plot.get_node(name)
		check(area.find_children("*", "Light3D", true, false).is_empty(), "Surroundings stay within the no-extra-lights budget")
		for instance: MeshInstance3D in area.find_children("*", "MeshInstance3D", true, false):
			if instance.mesh == null: continue
			meshes += 1
			for surface in instance.mesh.get_surface_count():
				var arrays := instance.mesh.surface_get_arrays(surface)
				var indices: int = arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else 0
				triangles += int((indices if indices > 0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3.0)
	check(meshes > 0 and meshes <= 160 and triangles <= 25000, "Measured surroundings stay within 160 meshes / 25,000 triangles: %d / %d" % [meshes, triangles])
