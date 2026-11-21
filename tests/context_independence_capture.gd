extends SceneTree
## Rendered evidence that the tactical and the non-tactical contexts share one presentation core (Task 08; explicit-only, needs a display):
##   godot_console --path . --script res://tests/context_independence_capture.gd -- <directory>
## Row 1: a real TacticalUnit with its TacticalCharacterAdapter (idle, walking, turning a corner, aiming). Row 2: the SAME character rig under an ExplorationCharacterHost with no unit (idle, walking, turning,
## crouching, inspecting, mid-inspection). Row 3: unarmed MIRA in the exploration host (idle, walking, crouching, inspecting). The fixed cameras are the same in every row. It also prints and writes the identities
## of the two hosts' rigs and presenters (<directory>/context-independence.txt) so the sharing is stated, not only seen. Outputs: <directory>/context-independence-sheet.png
const UNIT_SCENE := preload("res://units/tactical_unit.tscn")
const HOST_SCENE := preload("res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn")
const TILE := Vector2i(300, 420)
const COLUMNS := 6
var _tiles: Array = []   # row -> Array[Image]
var _notes: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _stage() -> Node3D:
	var stage := Node3D.new()
	root.add_child(stage)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	stage.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 150, 0)
	fill.light_energy = 0.5
	stage.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14, 14)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.47, 0.5)
	floor_mesh.material_override = material
	stage.add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.fov = 50.0
	stage.add_child(camera)
	camera.make_current()
	camera.name = "Camera"
	return stage

func _snap(stage: Node3D, row: int, subject: Vector3, yaw_view := 0.0) -> void:
	var camera := stage.get_node("Camera") as Camera3D
	# Fixed relative camera: three-quarter from the front-right of world +Z, the same for every row.
	camera.position = subject + Vector3(2.4, 1.0, 2.6)
	camera.look_at(subject + Vector3(0, 0.85, 0))
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var size := image.get_size()
	var width := int(size.y * float(TILE.x) / TILE.y)
	image = image.get_region(Rect2i((size.x - width) / 2, 0, width, size.y))
	image.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGBA8)
	while _tiles.size() <= row:
		_tiles.append([])
	_tiles[row].append(image)

func _identity(label: String, rig: CharacterRig, host: Node) -> void:
	_notes.append("%s: host script %s; rig scene %s; rig script %s; presenter %s; animation controller %s; weapon %s" % [label, host.get_script().resource_path, rig.get_parent().get_node("Rig").scene_file_path if rig.get_parent() != null else "?", rig.get_script().resource_path, rig.presenter.get_script().resource_path, rig.animation_controller.get_script().resource_path, "AUG" if rig.has_weapon() else "none"])

func _run() -> void:
	var directory: String = OS.get_cmdline_user_args()[0]

	# ---- Row 1: tactical.
	var stage := _stage()
	var unit := UNIT_SCENE.instantiate() as TacticalUnit
	unit.show_world_hud = false
	stage.add_child(unit)
	unit.position = Vector3(0.0, unit.standing_height, 0.0)
	for i in 30:
		await process_frame
	var adapter: TacticalCharacterAdapter = unit.visual_adapter
	_identity("tactical (TacticalUnit + TacticalCharacterAdapter)", adapter.rig, adapter)
	var foot := func() -> Vector3: return unit.global_position - Vector3.UP * unit.standing_height
	await _snap(stage, 0, foot.call())
	unit.move_along_path(PackedVector3Array([unit.global_position, unit.global_position + Vector3(0, 0, 3.0), unit.global_position + Vector3(2.5, 0, 3.0)]))
	for i in 60:
		await process_frame
	await _snap(stage, 0, foot.call())    # walking
	for i in 70:
		await process_frame
	await _snap(stage, 0, foot.call())    # at the corner, turning
	for i in 90:
		await process_frame
	adapter.present_aim()
	for i in 50:
		await process_frame
	await _snap(stage, 0, foot.call())    # aiming (tactical presentation)
	stage.queue_free()
	await process_frame

	# ---- Rows 2 and 3: the exploration host, equipped then unarmed.
	for row in [1, 2]:
		var armed: bool = row == 1
		stage = _stage()
		var host: ExplorationCharacterHost = HOST_SCENE.instantiate()
		if not armed:
			host.rig.weapon_scene = null
		stage.add_child(host)
		for i in 30:
			await process_frame
		_identity("exploration (ExplorationCharacterHost, %s)" % ("equipped" if armed else "unarmed"), host.rig, host)
		_notes.append("  no TacticalUnit in the scene: %s" % [stage.find_children("*", "Node", true, false).filter(func(n): return n is TacticalUnit).is_empty()])
		await _snap(stage, row, host.global_position)   # idle
		var travelled := 0.0
		for i in 70:
			host.report_velocity(Vector3(0, 0, 1.4), 1.0 / 60.0)
			await process_frame
		await _snap(stage, row, host.global_position)   # walking
		if armed:
			for i in 45:
				host.report_velocity(Vector3(1.4, 0, 0), 1.0 / 60.0)   # a corner: the body turns toward the new heading
				if i == 14:
					await _snap(stage, row, host.global_position)   # turning
				await process_frame
			for i in 40:
				await process_frame
		host.set_crouched(true)
		for i in 80:
			await process_frame
		await _snap(stage, row, host.global_position)   # crouched
		host.set_crouched(false)
		for i in 80:
			await process_frame
		var handle := host.inspect(host.global_position + Vector3(-1.5, 0, 1.0), 2.4)
		for i in 28:
			await process_frame
		await _snap(stage, row, host.global_position)   # turned to the object, bending toward it
		for i in 50:
			await process_frame
		if armed:
			await _snap(stage, row, host.global_position)   # inspecting
		var outcome: int = await handle.wait()   # the interaction runs to its end
		_notes.append("  the inspection settled with outcome %s (0 = COMPLETED): %s" % [outcome, outcome == PresentationTypes.Outcome.COMPLETED])
		stage.queue_free()
		await process_frame

	var rows := _tiles.size()
	var sheet := Image.create(TILE.x * COLUMNS, TILE.y * rows, false, Image.FORMAT_RGBA8)
	for row in rows:
		for index in _tiles[row].size():
			sheet.blit_rect(_tiles[row][index], Rect2i(Vector2i.ZERO, TILE), Vector2i(index * TILE.x, row * TILE.y))
	DirAccess.make_dir_recursive_absolute(directory)
	sheet.save_png(directory + "/context-independence-sheet.png")
	var file := FileAccess.open(directory + "/context-independence.txt", FileAccess.WRITE)
	file.store_string("\n".join(_notes) + "\n")
	file.close()
	print("\n".join(_notes))
	print("context_independence_capture: %d rows written to %s/context-independence-sheet.png (row 1 tactical: idle, walk, turn, aim; row 2 exploration equipped: idle, walk, turn, crouch, inspect x2; row 3 unarmed: idle, walk, crouch, inspect)" % [rows, directory])
	quit(0)
