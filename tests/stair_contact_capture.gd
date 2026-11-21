extends SceneTree
## Rendered evidence for stair foot contact (explicit-only: needs a GPU, not part of the standard tiers). MIRA stops half way up the playground stairs, at the centre line and at the edge, seen from the side,
## front, back and three-quarter; the top half of each sheet has the corrections switched OFF (feet glued to the centre line, no tread clamp, no settle, no foot-orientation stage), the bottom half has them ON.
## godot --path . --script res://tests/stair_contact_capture.gd -- <output.png>
const PLAYGROUND := "res://research/exploration_playground/exploration_playground.tscn"
var world: Node


func _initialize() -> void:
	_run.call_deferred()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _press(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _views(camera: Camera3D, target: Vector3, side: Vector3) -> Array:
	var views := []
	# side (looking along the stair's width), front (toward the climber), back, three-quarter
	for offset in [side * 2.2, Vector3(0, 0, 2.4), Vector3(0, 0, -2.4), side * 1.6 + Vector3(0, 0, 1.6)]:
		views.append(target + offset + Vector3(0, 0.35, 0))
	return views


func _scenario(lateral: float, corrected: bool, tiles: Array[Image], camera: Camera3D) -> void:
	var rig: CharacterRig = world.visual.rig
	var stairs: StairModel = world.traversal.stairs
	rig.stair_profile.lateral_follow_enabled = corrected
	rig.stair_profile.tread_clamp_enabled = corrected
	rig.stair_profile.settle_enabled = corrected
	if rig.foot_modifier != null:
		rig.foot_modifier.active = corrected
	world.body.global_position = Vector3(stairs.low.x + lateral, 0.0, 4.4)
	world.body.velocity = Vector3.ZERO
	world.yaw = PI
	world.pitch = 0.0
	world._apply_camera_rotation()
	world.pivot_position = world._focus_point()
	await _wait(0.8)
	_press(&"playground_forward", true)
	await _wait(2.4)
	_press(&"playground_forward", false)
	await _wait(1.2)
	var target: Vector3 = world.body.global_position + Vector3(0, 0.55, 0)
	for position in _views(camera, target, Vector3.RIGHT):
		camera.global_position = position
		camera.look_at(target, Vector3.UP)
		for i in 4:
			await process_frame
		tiles.append(root.get_texture().get_image())


func _run() -> void:
	var out_path := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://stair_contact.png"
	world = load(PLAYGROUND).instantiate()
	root.add_child(world)
	current_scene = world
	await _wait(1.0)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.fov = 40.0
	var tiles: Array[Image] = []
	for corrected in [false, true]:
		for lateral in [0.0, 0.55]:
			await _scenario(lateral, corrected, tiles, camera)
	var width := 420
	var height := 300
	var sheet := Image.create(width * 4, height * 4, false, Image.FORMAT_RGB8)
	for index in tiles.size():
		var tile := tiles[index]
		tile.resize(width, height, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(tile, Rect2i(0, 0, width, height), Vector2i((index % 4) * width, (index / 4) * height))
	sheet.save_png(out_path)
	print("stair_contact_capture: wrote %s (%d tiles: rows = off/centre, off/edge, on/centre, on/edge; columns = side, front, back, three-quarter)" % [out_path, tiles.size()])
	quit(0)
