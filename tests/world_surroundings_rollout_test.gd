extends SceneTree
## Current-site content contract: bounded scenery, continuous roads and fixed replay identity.
const Placement = preload("res://presentation/environment_asset_placement.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	for site in BattlefieldCatalog.PLAYABLE:
		for map_seed in [16, 17]: _case(site, map_seed)
	print("Current-site surroundings rollout: 6 layouts, %d failure(s)" % failures)
	quit(1 if failures else 0)

func _case(site: StringName, map_seed: int) -> void:
	var data := BattlefieldCatalog.generate(site, Vector2i.ZERO, map_seed, 1.0)
	var host := Node3D.new()
	root.add_child(host)
	check(BattlefieldCatalog.present(data, host, 1.0), "Current plot presents: %s / %d" % [site, map_seed])
	if host.get_child_count() == 0:
		host.free()
		return
	var plot := host.get_child(0)
	var before := data.content_manifest.duplicate(true)
	var count := 0
	var triangles := 0
	for name in ["Peripheral", "Distant"]:
		var area := plot.get_node(name)
		for type in ["PhysicsBody3D", "NavigationRegion3D", "Light3D", "TacticalUnit"]:
			check(area.find_children("*", type, true, false).is_empty(), "Scenery adds no %s: %s" % [type, site])
		for mesh: MeshInstance3D in area.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null: continue
			count += 1
			for surface in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var indices: int = arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else 0
				triangles += int((indices if indices else arrays[Mesh.ARRAY_VERTEX].size()) / 3.0)
	check(count > 0 and count <= 160 and triangles <= 25000, "Scenery budget %s/%d: %d meshes, %d triangles" % [site, map_seed, count, triangles])
	print("[SceneryBudget] %s/%d: %d meshes, %d triangles" % [site, map_seed, count, triangles])
	var ground := plot.get_node("Peripheral/Surroundings") as MeshInstance3D
	var ground_bounds := ground.global_transform * ground.get_aabb()
	check(ground_bounds.size.x >= 640 and ground_bounds.size.z >= 640, "Ground extends beyond supported normal/wide views")
	var roads := plot.get_node("Peripheral").get_children().filter(func(node): return String(node.name).begins_with("ServiceRoad"))
	check(roads.size() == 3, "Every site keeps two continuous road extensions")
	var axis := 2 if site == BattlefieldCatalog.SERVICE_DEPOT and map_seed == 17 else 0
	var bounds: Array[AABB] = []
	for road: Node3D in roads: bounds.append(Placement.mesh_bounds(road))
	bounds.sort_custom(func(a, b): return a.position[axis] < b.position[axis])
	for index in range(1, bounds.size()):
		check(absf(bounds[index - 1].end[axis] - bounds[index].position[axis]) < 0.01, "Roads meet without gaps or overlaps")
		check(is_equal_approx(bounds[index - 1].position.y, bounds[index].position.y), "Roads share ground height")
	for road_bounds in bounds:
		# Ground supports a road's horizontal footprint; it must not contain
		# the road vertically, since the visible road sits above its surface.
		var ground_footprint := Rect2(Vector2(ground_bounds.position.x, ground_bounds.position.z), Vector2(ground_bounds.size.x, ground_bounds.size.z))
		var road_footprint := Rect2(Vector2(road_bounds.position.x, road_bounds.position.z), Vector2(road_bounds.size.x, road_bounds.size.z))
		check(ground_footprint.encloses(road_footprint), "Extended ground supports the continuing road")
	var playable := AABB(Vector3(-20, -100, -20), Vector3(40, 200, 40))
	for mesh: MeshInstance3D in plot.get_node("Peripheral/NeighboringYards").find_children("*", "MeshInstance3D", true, false):
		var box := mesh.global_transform * mesh.get_aabb()
		if box.size.y > 0.08: check(not playable.intersects(box.grow(-0.002)), "Nearby structure stays outside playable cells: " + String(mesh.get_path()))
		elif site != BattlefieldCatalog.SERVICE_DEPOT:
			check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "New flat paving and paint do not add shadow passes")
	var backdrop := plot.get_node("Distant/BackgroundBlocks")
	check(backdrop.get_child_count() == 6, "All directions retain low-detail background districts")
	for mesh: MeshInstance3D in backdrop.find_children("*", "MeshInstance3D", true, false):
		check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Distant blocks add no shadow passes")
	check(data.cells.size() == 1600 and data.content_manifest == before, "Presentation preserves tactical bounds and accepted choices")
	if site != BattlefieldCatalog.SERVICE_DEPOT:
		check(data.content_manifest.plot_revision == 2, "Changed Freight/Fleet surroundings have a new content revision")
		var stale := before.duplicate(true)
		stale.plot_revision = 1
		var rejected := BattlefieldCatalog.generate(site, Vector2i.ZERO, map_seed, 1.0, stale)
		check(rejected.generation_errors.any(func(error): return error.code == "STALE_PLOT_REVISION"), "Old scenery identity rejects explicitly")
	host.free()
