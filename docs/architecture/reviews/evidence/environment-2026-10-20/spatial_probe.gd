extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var road_asset: Node3D = load("res://art/environments/kenney/city_kit_roads/models/road-straight.glb").instantiate()
	print("ROAD_NATIVE root_transform=%s" % road_asset.transform)
	for mesh in road_asset.find_children("*", "MeshInstance3D", true, false):
		print("ROAD_NATIVE mesh_transform=%s parent=%s" % [mesh.transform, mesh.get_parent().name])
		print("ROAD_NATIVE mesh=%s bounds=%s surfaces=%d" % [mesh.name, mesh.get_aabb(), mesh.mesh.get_surface_count()])
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bounds := AABB(vertices[0], Vector3.ZERO)
			for vertex in vertices:
				bounds = bounds.expand(vertex)
			var material = mesh.mesh.surface_get_material(surface)
			print("ROAD_NATIVE surface=%d material=%s bounds=%s" % [surface, material.resource_name, bounds])
			var levels := {}
			for vertex in vertices:
				var key := snappedf(vertex.y, 0.001)
				if not levels.has(key):
					levels[key] = {}
				levels[key][Vector2(snappedf(vertex.x, 0.001), snappedf(vertex.z, 0.001))] = true
			for level in levels:
				print("ROAD_NATIVE y=%s xz=%s" % [level, levels[level].keys()])
	road_asset.free()
	var catalog := IndustrialModuleCatalog.create()
	var definition: EnvironmentModuleDefinition = catalog.industrial_shell_i
	for rotation in 4:
		var logical := definition.rotate_direction(Vector2i.DOWN, rotation)
		var rendered := Basis(Vector3.UP, float(rotation) * PI * 0.5) * Vector3.BACK
		print("ROTATION r%d logical_front=%s rendered_normalized_front=%s dot=%.1f" % [rotation, logical, rendered, Vector3(logical.x, 0, logical.y).dot(rendered)])
	var layout := EnvironmentModuleLayout.new()
	var asymmetric := EnvironmentModuleDefinition.new(&"probe", &"probe", Vector2i(2, 5))
	asymmetric.set_visual_envelope(AABB(Vector3.ZERO, Vector3(2, 1, 5)))
	for rotation in 4:
		var placement := EnvironmentModulePlacement.new(&"probe", Vector2i.ZERO, rotation)
		print("ENVELOPE r%d actual=%s" % [rotation, layout.world_visual_envelope(asymmetric, placement)])
	var data := FlatMapGenerator.generate_coherent_environment(60, 50, 1.0, 17, &"industrial_district")
	var presentation := Node3D.new()
	root.add_child(presentation)
	ModularEnvironmentPresenter.build(data, presentation, 1.0)
	for module in presentation.get_node("ModularEnvironment").get_children():
		var id: StringName = module.get_meta("component_id")
		if id == &"road_straight":
			var road_placement: EnvironmentModulePlacement = data.environment_modules[int(module.get_meta("placement_index"))]
			for child in module.get_children():
				if child is TacticalVisualOccluder:
					var bounds: AABB = child.global_transform * child.occlusion_bounds
					var expected_center := data.get_cell(Vector3i(road_placement.origin.x, 0, road_placement.origin.y)).world_position + Vector3(4.5, 0, 4.5)
					print("ROAD r%d bounds=%s expected_center=%s delta=%s" % [road_placement.rotation, bounds, expected_center, bounds.get_center() - expected_center])
		if not String(id).begins_with("industrial_shell_"):
			continue
		var placement: EnvironmentModulePlacement = data.environment_modules[int(module.get_meta("placement_index"))]
		var asset: Node3D = module.get_child(0)
		var face: String = IndustrialBuildingPlacementProfiles.profile_for_asset(IndustrialBuildingPlacementProfiles.asset_id_for_module(id)).face
		var actual := (asset.basis * (Vector3.FORWARD if face == "-z" else Vector3.BACK)).normalized()
		var expected: Vector2i = catalog[id].rotate_direction(Vector2i.DOWN, placement.rotation)
		print("GENERATED seed17 %s r%d logical=%s actual=%s dot=%.1f" % [id, placement.rotation, expected, actual, Vector3(expected.x, 0, expected.y).dot(actual)])
	presentation.free()
	for rotation in 4:
		var isolated := FlatMapGenerator.generate(40, 30, 1.0, 1)
		isolated.environment_modules.append(EnvironmentModulePlacement.new(&"industrial_shell_i", Vector2i(4, 4), rotation))
		var holder := Node3D.new()
		root.add_child(holder)
		ModularEnvironmentPresenter.build(isolated, holder, 1.0)
		var shell: Node3D = holder.get_node("ModularEnvironment").get_child(0).get_child(0)
		print("REAL_SHELL r%d face=%s logical=%s" % [rotation, (shell.basis * Vector3.FORWARD).normalized(), definition.rotate_direction(Vector2i.DOWN, rotation)])
		holder.free()
	quit()
