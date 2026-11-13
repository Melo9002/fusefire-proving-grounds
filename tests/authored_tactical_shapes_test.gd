extends SceneTree
## Authored shape contract: visible body, low details, and open ground have distinct roles.
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var floor_mesh := CSGBox3D.new()
	floor_mesh.size = Vector3(40, 0.2, 40)
	floor_mesh.position.y = -0.1
	root.add_child(floor_mesh)
	for filename in ["loading_yard", "loading_yard_alt"]:
		var source := load("res://art/environments/authored/parcels/%s.tscn" % filename).instantiate() as Node3D
		for object_name in ["Warehouse", "Truck"]:
			var object := source.get_node(object_name) as Node3D
			if object_name == "Truck":
				check(_mesh_hit(object, Vector3(-3, 1.2, -1), Vector3(3, 1.2, -1)), "Imported cargo body crosses the authored body probe")
				check(not _mesh_hit(object, Vector3(-3, 1.2, 1.75), Vector3(3, 1.2, 1.75)), "Imported hood leaves the above-hood probe clear")
			else:
				check(_mesh_hit(object, Vector3(-8, 1.5, 0), Vector3(8, 1.5, 0)), "Imported warehouse has a wall at the shell probe")
				check(not _mesh_hit(object, Vector3(-4.8, 1, 4.8), Vector3(-4.8, 1, 5.8)), "Imported warehouse leaves the former oversized side reservation clear")
			for rotation in 4:
				var scene := Node3D.new()
				scene.add_child(object.duplicate())
				var transform := ParcelTransform.scene_transform(Vector2i(16, 32), Vector3i(2, 0, 2), rotation, Vector2i(40, 40), 1)
				var data := FlatMapGenerator.generate(40, 40, 1, 1)
				var old := FlatMapGenerator.generate(40, 40, 1, 1)
				AuthoredSceneMapCompiler.compile(scene, data, 1, transform, true, 3)
				AuthoredSceneMapCompiler.compile(scene, old, 1, transform, true, 2)
				var grid := GridManager.new()
				grid.map_floor = floor_mesh
				grid.map_data = data
				var resolved := transform * object.transform
				var context := "%s/%s rotation %d" % [filename, object_name, rotation]
				if object_name == "Truck":
					var through_body := CombatRules.get_blocking_cell(resolved * Vector3(-3, 1.2, -1), resolved * Vector3(3, 1.2, -1), grid)
					check(through_body != null, context + " actual cargo body blocks shots")
					var above_hood := CombatRules.get_blocking_cell(resolved * Vector3(-3, 1.2, 1.75), resolved * Vector3(3, 1.2, 1.75), grid)
					check(above_hood == null, context + " permits shots above the low hood")
					grid.map_data = old
					check(CombatRules.get_blocking_cell(resolved * Vector3(-3, 1.2, 1.75), resolved * Vector3(3, 1.2, 1.75), grid) != null, context + " preserves revision 2's tall hood for exact replays")
				else:
					var open_cell := grid.world_to_grid(resolved * Vector3(-4.8, 0, 5.5))
					check(data.get_cell(open_cell).walkable and data.get_cell(open_cell).can_stop, context + " open side ground is usable")
					check(not old.get_cell(open_cell).can_stop, context + " preserves old side reservations for exact replays")
					var planter_cell := grid.world_to_grid(resolved * Vector3(-4.5, 0, -2.5))
					check(data.get_cell(planter_cell).cover_type == MapCellData.CoverType.LOW and not data.get_cell(planter_cell).can_stop, context + " planter remains a low-cover obstacle")
				grid.free()
				scene.free()
		source.free()
	if OS.get_cmdline_user_args().has("capture"):
		await _capture_shapes()
	floor_mesh.free()
	print("Authored tactical shapes: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _mesh_hit(object: Node3D, start: Vector3, finish: Vector3) -> bool:
	for mesh_node: MeshInstance3D in object.find_children("*", "MeshInstance3D", true, false):
		var transform := Transform3D.IDENTITY
		var current: Node = mesh_node
		while current != object:
			if current is Node3D: transform = current.transform * transform
			current = current.get_parent()
		var inverse := transform.affine_inverse()
		if not mesh_node.mesh.generate_triangle_mesh().intersect_segment(inverse * start, inverse * finish).is_empty(): return true
	return false

func _capture_shapes() -> void:
	var lighting := DirectionalLight3D.new()
	lighting.rotation_degrees = Vector3(-50, -30, 0)
	root.add_child(lighting)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(camera)
	camera.make_current()
	var source := load("res://art/environments/authored/parcels/loading_yard.tscn").instantiate() as Node3D
	for object_name in ["Warehouse", "Truck"]:
		var object := source.get_node(object_name).duplicate() as Node3D
		object.transform = Transform3D.IDENTITY
		object.show()
		root.add_child(object)
		camera.size = 22 if object_name == "Warehouse" else 7
		camera.position = Vector3(-16, 12, -18) if object_name == "Warehouse" else Vector3(-4, 3, 5)
		camera.look_at(Vector3(0, 2, 0) if object_name == "Warehouse" else Vector3(0, 0.7, 0))
		for diagnostic in [false, true]:
			var overlay := Node3D.new()
			root.add_child(overlay)
			if diagnostic:
				for node: Node3D in object.find_children("*", "Node3D", true, false):
					if not AuthoredSceneMapCompiler.is_active_solid(node): continue
					var box := MeshInstance3D.new()
					var mesh := BoxMesh.new()
					mesh.size = node.get_meta("solid_size")
					var tint := StandardMaterial3D.new()
					tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					tint.no_depth_test = true
					tint.albedo_color = Color(0.1, 0.8, 1, 0.28) if mesh.size.y < 1.2 else Color(1, 0.4, 0.1, 0.23)
					mesh.material = tint
					box.mesh = mesh
					overlay.add_child(box)
					box.global_transform = node.global_transform
			await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("res://artifacts/refined-%s-%s.png" % [object_name.to_lower(), "shapes" if diagnostic else "normal"]) == OK, "Shape capture saved")
			overlay.free()
		object.free()
	source.free()
	camera.free()
	lighting.free()
