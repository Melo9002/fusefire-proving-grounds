extends SceneTree
## Rendered evidence for a humanoid with no weapon (Task 07 package 9; explicit-only, needs a display):
##   godot_console --path . --script res://tests/unarmed_capture.gd -- <directory>
## One sheet, fixed cameras, eight tiles a row: the equipped MIRA (front, side), then the unarmed one standing, walking, crouched and kneeling from the front, side and three-quarter, half way up a ladder, and carrying a passenger. Output: <directory>/unarmed-sheet.png
const TILE := Vector2i(300, 420)
var _tiles: Array[Image] = []

func _initialize() -> void:
	_run.call_deferred()

func _snap(camera: Camera3D, position_value: Vector3, look_at_value: Vector3, feed: Callable = Callable()) -> void:
	camera.position = position_value
	camera.look_at(look_at_value)
	for i in 2:
		if feed.is_valid():
			feed.call()
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var size := image.get_size()
	var width := int(size.y * float(TILE.x) / TILE.y)
	image = image.get_region(Rect2i((size.x - width) / 2, 0, width, size.y))
	image.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGBA8)
	_tiles.append(image)

func _character(stage: Node3D, armed: bool) -> TacticalCharacterAdapter:
	var v := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as TacticalCharacterAdapter
	if not armed:
		v.rig.weapon_scene = null
	stage.add_child(v)
	v.position = Vector3.ZERO   # standing on the floor
	return v

func _run() -> void:
	var directory: String = OS.get_cmdline_user_args()[0]
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
	plane.size = Vector2(10, 10)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.45, 0.47, 0.5)
	floor_mesh.material_override = floor_material
	stage.add_child(floor_mesh)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.make_current()
	var look := Vector3(0, 0.85, 0)
	var front := Vector3(0, 1.0, 2.3)
	var side := Vector3(2.3, 1.0, 0)
	var three_quarter := Vector3(1.7, 1.05, 1.7)
	var other_side := Vector3(-2.3, 1.0, 0)
	var hip_look := Vector3(0, 0.85, 0)

	var armed := _character(stage, true)
	for i in 30:
		await process_frame
	await _snap(camera, front, look)
	await _snap(camera, side, look)
	armed.queue_free()
	await process_frame

	var bare := _character(stage, false)
	for i in 30:
		await process_frame
	await _snap(camera, front, look)
	await _snap(camera, side, look)
	await _snap(camera, three_quarter, look)
	await _snap(camera, Vector3(0.9, 0.95, 0.9), hip_look)    # hand beside the thigh, close, from the character's left-front
	await _snap(camera, Vector3(-0.9, 0.95, 0.9), hip_look)   # and from the right-front
	bare.rig.animation_controller.play(&"move")
	var walk := func() -> void: bare.update_locomotion(Vector3(0, 0, 3.0), 1.0 / 60.0)
	for i in 70:
		walk.call()
		await process_frame
	await _snap(camera, side, look, walk)
	await _snap(camera, three_quarter, look, walk)
	bare.rig.animation_controller.play(&"idle")
	for i in 60:
		bare.update_locomotion(Vector3.ZERO, 1.0 / 60.0)
		await process_frame
	bare.presenter.postures.set_posture(&"capture", PresentationTypes.Posture.CROUCH, PresentationTypes.PRIORITY_CONTEXT, 0.0, 0.40)
	for i in 60:
		await process_frame
	await _snap(camera, side, look)
	await _snap(camera, three_quarter, look)
	await _snap(camera, front, look)
	bare.presenter.postures.set_posture(&"capture", PresentationTypes.Posture.KNEEL, PresentationTypes.PRIORITY_CONTEXT, 0.0, bare.rig.crouch_modifier.max_depth + CharacterRig.KNEEL_BLEND_RANGE)
	for i in 80:
		await process_frame
	await _snap(camera, side, look)
	await _snap(camera, three_quarter, look)
	await _snap(camera, front, look)
	await _snap(camera, other_side, look)   # the opposite-side kneeling view
	bare.presenter.postures.release(&"capture")
	for i in 60:
		await process_frame
	bare.rig.begin_traversal(&"ladder", 3.0, 1)
	for i in 70:
		bare.rig.set_traversal_progress(1.4)
		await process_frame
	await _snap(camera, side, look + Vector3(0, 0.2, 0))
	bare.rig.end_traversal()
	for i in 30:
		await process_frame
	bare.preview_carrying = true
	bare.rig.begin_carry()
	for i in 40:
		await process_frame
	await _snap(camera, front, look)

	# The equipped carrier lifting a passenger, carrying it, and setting it down (the rescue presentation).
	bare.queue_free()
	await process_frame
	var carrier := _character(stage, true)
	for i in 30:
		await process_frame
	var lift_from: Vector3 = carrier.rig.character_root.global_position + Vector3(0, 0, 1.1)
	carrier.preview_carrying = true   # no tactical unit here: the context says this character is the carrier
	carrier.rig.begin_pickup(lift_from)
	for i in 50:
		await process_frame
	await _snap(camera, side, look)   # mid-lift
	for i in 300:
		await process_frame
	await _snap(camera, three_quarter, look)   # carrying
	await _snap(camera, front, look)
	carrier.rig.begin_release()
	for i in 60:
		await process_frame
	await _snap(camera, side, look)   # mid-release

	var columns := 8
	var rows := ceili(float(_tiles.size()) / columns)
	var sheet := Image.create(TILE.x * columns, TILE.y * rows, false, Image.FORMAT_RGBA8)
	for index in _tiles.size():
		sheet.blit_rect(_tiles[index], Rect2i(Vector2i.ZERO, TILE), Vector2i((index % columns) * TILE.x, (index / columns) * TILE.y))
	DirAccess.make_dir_recursive_absolute(directory)
	sheet.save_png(directory + "/unarmed-sheet.png")
	print("unarmed_capture: %d tiles written to %s/unarmed-sheet.png (equipped front, side; unarmed standing front, side, three-quarter, two hip close-ups; walking side, three-quarter; crouched side, three-quarter, front; kneeling side, three-quarter, front, opposite side; ladder; carrying; then an equipped carrier mid-lift, carrying (three-quarter, front) and mid-release)" % [_tiles.size(), directory])
	quit(0)
