extends SceneTree

var failures := 0
var used_assets := {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for dimensions in FlatMapGenerator.MAP_SIZES:
		for map_seed in [1, 17, 42]:
			var map := FlatMapGenerator.generate_with_cover(dimensions.x, dimensions.y, 1.0, map_seed)
			var first := _inspect(map)
			if dimensions == Vector2i(32, 24) and map_seed == 17:
				_check(first == _inspect(map), "Seed 17 reproduces its asset choices and resolved bounds")
	for model in ["box-large.glb", "shipping-container-a.glb", "delivery.glb"]:
		_check(used_assets.has(model), "The seed matrix exercises %s" % model)
	print("Generated cover presentation: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _inspect(map: MapData) -> Dictionary:
	var scenery := Node3D.new()
	root.add_child(scenery)
	GeneratedTerrainPresenter.build(map, scenery, 1.0)
	var placements := {}
	for node: Node3D in scenery.get_children():
		var limits: AABB
		if node.has_meta("grid_position"):
			var cell := map.get_cell(node.get_meta("grid_position"))
			limits = AABB(cell.world_position - Vector3(0.5, 0, 0.5), Vector3(1, cell.cover_height, 1))
		elif node.name.begins_with("Container_"):
			for footprint in map.containers:
				if node.name != "Container_%d_%d" % [footprint.position.x, footprint.position.y]:
					continue
				var first := map.get_cell(Vector3i(footprint.position.x, 0, footprint.position.y))
				limits = AABB(first.world_position - Vector3(0.5, 0, 0.5), Vector3(footprint.size.x, first.cover_height, footprint.size.y))
				break
		else:
			continue
		var asset := node.get_child(0) as Node3D if node.get_child_count() > 0 else null
		_check(asset != null and asset.has_meta("asset_path"), "%s at seed %d uses imported cover" % [node.name, map.generation_seed])
		if asset == null or not asset.has_meta("asset_path"):
			continue
		var model := String(asset.get_meta("asset_path")).get_file()
		var actual := EnvironmentAssetPlacement.mesh_bounds(node)
		_check(limits.grow(0.005).encloses(actual) and is_equal_approx(actual.position.y, limits.position.y), "%s at seed %d fits and rests inside its tactical footprint" % [node.name, map.generation_seed])
		if model != "delivery.glb":
			_check(actual.end.y >= limits.end.y - 0.12, "%s at seed %d represents its tactical cover height" % [node.name, map.generation_seed])
		used_assets[model] = true
		placements[node.name] = [model, asset.transform, actual]
	scenery.free()
	return placements

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
