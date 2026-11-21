extends SceneTree
## Rendered close views of each hand on its grip in the aim pose (explicit-only; needs a display).
##   godot_console --path . --script res://tests/hand_views_capture.gd -- <output.png> [state]
## Cameras are placed in the weapon's own frame, so the views stay meaningful whatever the pose.
const TILE := Vector2i(540, 400)
## [camera position in weapon frame, look-at point in weapon frame, label]
const VIEWS := [
	[Vector3(0.30, -0.05, 0.30), Vector3(0.0, -0.04, 0.19), "support hand: front-left"],
	[Vector3(0.34, -0.02, 0.16), Vector3(0.0, -0.04, 0.19), "support hand: from the left"],
	[Vector3(-0.32, 0.0, -0.20), Vector3(-0.01, -0.05, -0.015), "firing hand: rear-right"],
	[Vector3(-0.34, -0.03, 0.02), Vector3(-0.01, -0.05, -0.015), "firing hand: from the right"],
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var state := StringName(args[1]) if args.size() > 1 else &"aim"
	var stage := Node3D.new()
	root.add_child(stage)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	stage.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.6
	stage.add_child(fill)
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as TacticalCharacterAdapter
	stage.add_child(rig)
	rig.position = Vector3.ZERO
	var camera := Camera3D.new()
	camera.fov = 40.0
	stage.add_child(camera)
	camera.make_current()
	for i in 20: await process_frame
	rig.rig.animation_controller.play(state)
	rig.presenter.aim.held = state == &"aim"
	rig.presenter.aim.release_left = 1000000.0
	for i in 60: await process_frame
	await create_timer(1.0).timeout
	var tiles: Array[Image] = []
	for view in VIEWS:
		camera.global_position = rig.rig.weapon.to_global(view[0])
		camera.look_at(rig.rig.weapon.to_global(view[1]), rig.rig.weapon.global_basis.y)
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var size := image.get_size()
		var crop_width := int(size.y * float(TILE.x) / TILE.y)
		image = image.get_region(Rect2i((size.x - crop_width) / 2, 0, crop_width, size.y))
		image.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
		tiles.append(image)
	var sheet := Image.create(TILE.x * 2, TILE.y * 2, false, Image.FORMAT_RGB8)
	for index in tiles.size():
		sheet.blit_rect(tiles[index], Rect2i(Vector2i.ZERO, TILE), Vector2i((index % 2) * TILE.x, (index / 2) * TILE.y))
	sheet.save_png(args[0])
	print("HANDVIEWS saved")
	quit(0)
