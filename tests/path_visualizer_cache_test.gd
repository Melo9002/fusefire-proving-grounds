extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var grid := GridManager.new()
	root.add_child(grid)
	var visualizer := PathVisualizer.new()
	visualizer.grid_manager = grid
	root.add_child(visualizer)
	var path := PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 1)])
	visualizer.draw_path(path)
	var original := visualizer.path_mesh_instance.mesh
	var faces := original.get_faces()
	for index in 100:
		visualizer.draw_path(path, Color.RED)
	check(visualizer.path_mesh_instance.mesh == original, "Unchanged paths reuse geometry")
	check(visualizer.path_mesh_instance.material_override.albedo_color == Color.RED, "Tint updates independently")
	path[1] = Vector3(2, 1, 2)
	visualizer.draw_path(path)
	check(visualizer.path_mesh_instance.mesh != original, "Changed elevation and destination rebuild geometry")
	visualizer.draw_path(PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 1)]))
	check(visualizer.path_mesh_instance.mesh.get_faces() == faces, "Restored path has identical vertices")
	original = visualizer.path_mesh_instance.mesh
	visualizer.tile_padding += 0.1
	visualizer.draw_path(PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 1)]))
	check(visualizer.path_mesh_instance.mesh != original, "Inspector padding invalidates geometry")
	original = visualizer.path_mesh_instance.mesh
	grid.cell_size = 2.0
	visualizer.draw_path(PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 1)]))
	check(visualizer.path_mesh_instance.mesh != original, "Cell size invalidates geometry")
	visualizer.clear_path()
	visualizer.clear_path()
	check(visualizer.path_mesh_instance.mesh == null, "Repeated clearing is safe")
	visualizer.draw_path(path)
	check(visualizer.path_mesh_instance.mesh != null, "Cleared geometry is restored")
	visualizer.free()
	grid.free()
	print("Path visualizer cache: %d failure(s)" % failures)
	quit(1 if failures else 0)
