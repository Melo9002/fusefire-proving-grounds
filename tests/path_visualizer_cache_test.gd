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
	var floor := CSGBox3D.new()
	floor.size = Vector3(8, 1, 8)
	floor.position.y = -0.5
	root.add_child(floor)
	grid.map_floor = floor
	root.add_child(grid)
	var layers := GroundTileLayers.new()
	layers.grid_manager = grid
	root.add_child(layers)
	var visualizer := PathVisualizer.new()
	visualizer.grid_manager = grid
	visualizer.tile_layers = layers
	root.add_child(visualizer)
	var initial := PackedVector3Array([grid.grid_to_world(Vector3i(3, 0, 3)), grid.grid_to_world(Vector3i(4, 0, 4))])
	var path := initial.duplicate()
	visualizer.draw_path(path)
	var path_layer := layers.mesh_instance(GroundTileLayers.Layer.PATH)
	var original := path_layer.mesh
	var faces := original.get_faces()
	for index in 100:
		visualizer.draw_path(path, Color.RED)
	check(path_layer.mesh == original, "Unchanged paths reuse geometry")
	check(path_layer.material_override.get_shader_parameter(&"tint") == Color.RED, "Tint updates independently")
	path[1] = Vector3(2, 1, 2)
	visualizer.draw_path(path)
	check(path_layer.mesh != original, "Changed elevation and destination rebuild geometry")
	visualizer.draw_path(initial)
	check(path_layer.mesh.get_faces() == faces, "Restored path has identical vertices")
	original = path_layer.mesh
	visualizer.tile_padding += 0.1
	visualizer.draw_path(initial)
	check(path_layer.mesh != original, "Inspector padding invalidates geometry")
	original = path_layer.mesh
	grid.cell_size = 2.0
	visualizer.draw_path(initial)
	check(path_layer.mesh != original, "Cell size invalidates geometry")
	visualizer.clear_path()
	visualizer.clear_path()
	check(path_layer.mesh == null, "Repeated clearing is safe")
	visualizer.draw_path(path)
	check(path_layer.mesh != null, "Cleared geometry is restored")
	visualizer.clear_path()
	grid.cell_size = 1.0
	var lower := Vector3i(3, 0, 3)
	var upper := Vector3i(3, 1, 3)
	visualizer.draw_range_zone([lower, upper])
	var range_layer := layers.mesh_instance(GroundTileLayers.Layer.RANGE)
	var complete_range := range_layer.mesh.get_faces()
	visualizer.draw_path(PackedVector3Array([grid.grid_to_world(lower)]))
	check(range_layer.mesh.get_faces().size() * 2 == complete_range.size() and range_layer.mesh.get_aabb().position.y > 0.5, "Path owns its tile while range on the upper floor remains")
	visualizer.clear_path()
	check(range_layer.mesh.get_faces() == complete_range, "Clearing the path restores the suppressed range tile")
	visualizer.clear_range_zone()
	var guard := OverwatchRangeVisualizer.new()
	guard.tile_layers = layers
	root.add_child(guard)
	var enemy_only := Vector3i(4, 0, 3)
	guard.show_ranges([], [lower, upper], [lower, enemy_only])
	var shared_guard := layers.mesh_instance(GroundTileLayers.Layer.SHARED_GUARD)
	var enemy_guard := layers.mesh_instance(GroundTileLayers.Layer.ENEMY_GUARD)
	var friendly_guard := layers.mesh_instance(GroundTileLayers.Layer.GUARD_ACTIVE)
	check(shared_guard.mesh.get_faces().size() == enemy_guard.mesh.get_faces().size(), "Shared Guard renders only one tile at the common cell")
	check(shared_guard.material_override.get_shader_parameter(&"tint") == guard.committed_guard_color.lerp(guard.enemy_guard_color, 0.5), "Shared Guard uses the blended tint")
	check(friendly_guard.mesh.get_aabb().position.y > 0.5, "Guard on the upper floor keeps the friendly tint")
	visualizer.draw_range_zone([lower, enemy_only])
	check(range_layer.mesh != null and shared_guard.mesh == null and enemy_guard.mesh == null, "Move preview owns cells with enemy or shared Guard")
	visualizer.draw_range_zone([lower, upper], Color.RED)
	check(range_layer.material_override.get_shader_parameter(&"tint") == Color.RED and shared_guard.mesh == null and friendly_guard.mesh == null, "Attack preview owns cells with friendly or shared Guard")
	visualizer.clear_range_zone()
	check(shared_guard.mesh != null and enemy_guard.mesh != null and friendly_guard.mesh != null, "Clearing the action preview restores committed Guard coverage")
	guard.show_ranges([], [lower, upper], [enemy_only, enemy_only])
	check(shared_guard.mesh == null and friendly_guard.mesh.get_faces().size() == complete_range.size(), "Losing enemy coverage restores friendly tint, and duplicate enemy coverage stays enemy-only")
	guard.free()
	visualizer.free()
	layers.free()
	floor.free()
	grid.free()
	print("Path visualizer cache: %d failure(s)" % failures)
	quit(1 if failures else 0)
