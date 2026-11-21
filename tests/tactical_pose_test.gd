extends SceneTree

const CONTEXT := preload("res://presentation/characters/runtime/tactical_pose_context.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var grid := GridManager.new()
	root.add_child(grid)
	var floor_node := CSGBox3D.new()
	floor_node.size = Vector3(8, 0.2, 8)
	grid.add_child(floor_node)
	grid.map_floor = floor_node
	for cell_pos in [Vector3i(2, 0, 2), Vector3i(3, 0, 2), Vector3i(4, 0, 2), Vector3i(4, 2, 2)]:
		var cell := MapCellData.new(cell_pos, grid.grid_to_world(cell_pos))
		grid.map_data.add_cell(cell)
	grid.get_cell_data(Vector3i(3, 0, 2)).cover_type = MapCellData.CoverType.LOW
	grid.get_cell_data(Vector3i(3, 0, 2)).cover_height = 0.8
	var cover := CONTEXT.cover_at(grid, Vector3i(2, 0, 2), Vector3.RIGHT)
	check(cover.type == MapCellData.CoverType.LOW and cover.direction == Vector3.RIGHT, "Cover normal follows neighboring cover")
	check(cover.has("surface_position") and cover.has("surface_normal"), "Authored cover pose receives world-space procedural contact hints")
	grid.get_cell_data(Vector3i(3, 0, 2)).cover_height = 0
	check(CONTEXT.cover_at(grid, Vector3i(2, 0, 2), Vector3.RIGHT).type == MapCellData.CoverType.NONE, "An empty label alone does not select a physical cover pose")
	grid.get_cell_data(Vector3i(3, 0, 2)).cover_height = 0.8
	var path := PackedVector3Array()
	for cell_pos in [Vector3i(2, 0, 2), Vector3i(3, 0, 2), Vector3i(4, 0, 2), Vector3i(4, 2, 2), Vector3i(4, 0, 2)]:
		path.append(grid.grid_to_world(cell_pos))
	check(CONTEXT.path_poses(grid, path) == [&"move", &"vault", &"vault", &"climb", &"descend"], "Raw path distinguishes cover from elevation")
	var demo = load("res://art/characters/mira_0/demo/mira_0_pose_workbench.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	await process_frame
	var controller = demo.rig.animation_controller
	for pose in [&"cover_low", &"cover_high", &"shoot_left", &"shoot_right", &"vault", &"climb", &"descend", &"land", &"pickup", &"carry_idle", &"carry_move", &"boarding"]:
		controller.play(pose)
		await create_timer(0.2).timeout
		check(controller.current_state == pose, "Pose plays: %s" % pose)
	controller.play(&"cover_low")
	await create_timer(0.25).timeout
	controller.play(&"rifle_idle")
	await create_timer(0.25).timeout
	check(controller.current_state == &"rifle_idle", "Traversal and cover poses return to MIRA Zero idle")
	demo.queue_free()
	grid.queue_free()
	await process_frame
	print("Tactical poses: %d failure(s)" % failures)
	quit(1 if failures else 0)
