extends SceneTree
## Rendered review of the class stripe: the Bulwark's yellow chest band from the front, the side and the back,
## standing and in the aim pose. Explicit-only; needs a display.
##   godot_console --path . --script res://tests/class_marker_capture.gd -- <output.png>
const TILE := Vector2i(420, 600)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	stage.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.32, 0.36, 0.42)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	stage.add_child(environment)
	var definition := TacticalArchetypeCatalog.get_definition(&"bulwark")
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as TacticalCharacterAdapter
	stage.add_child(rig)
	var camera := Camera3D.new()
	camera.fov = 40.0
	stage.add_child(camera)
	camera.make_current()
	for i in 20: await process_frame
	rig.set_class_marker(definition.marker_color)
	for i in 6: await process_frame
	var tiles: Array[Image] = []
	var angles := [0.0, 90.0, 180.0, 0.0]
	for index in angles.size():
		if index == 3:
			rig.rig.animation_controller.play(&"aim")
			rig.presenter.aim.held = true
			rig.presenter.aim.release_left = 1000000.0
			for i in 60: await process_frame
		var forward := rig.rig.character_root.global_basis.z
		var direction := forward.rotated(Vector3.UP, deg_to_rad(angles[index] if index < 3 else 35.0))
		var hips: Vector3 = rig.rig.skeleton.to_global(rig.rig.skeleton.get_bone_global_pose(rig.rig.skeleton.find_bone(&"mixamorig_Hips")).origin)
		var focus := hips + Vector3(0, 0.25, 0)
		camera.position = focus + direction * 2.4
		camera.look_at(focus, Vector3.UP)
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var crop := Rect2i((image.get_width() - TILE.x * 2) / 2, 0, TILE.x * 2, image.get_height()) if image.get_width() > TILE.x * 2 else Rect2i(0, 0, image.get_width(), image.get_height())
		var part := image.get_region(crop)
		part.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
		tiles.append(part)
	var sheet := Image.create(TILE.x * tiles.size(), TILE.y, false, Image.FORMAT_RGB8)
	for index in tiles.size():
		sheet.blit_rect(tiles[index], Rect2i(Vector2i.ZERO, TILE), Vector2i(index * TILE.x, 0))
	sheet.save_png(OS.get_cmdline_user_args()[0])
	print("MARKER saved")
	quit(0)
