extends SceneTree
## Rendered look at the sandbox's action packages through the playground's own over-the-shoulder camera (explicit-only, needs a display):
##   godot_console --path . --script res://tests/exploration_actions_capture.gd -- <directory>
## Tiles: aiming at a mannequin, a hit and its health bar, cover behind the low wall (crouched, then popped up to aim), the ladder mid-climb, the staircase mid-way, carrying a body, the defeat and respawn screen.
## Output: <directory>/exploration-actions-sheet.png
const PLAYGROUND := "res://research/exploration_playground/exploration_playground.tscn"
const TILE := Vector2i(480, 300)
const COLUMNS := 3
var world: Node
var _tiles: Array[Image] = []

func _initialize() -> void:
	_run.call_deferred()

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _press(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)

func _place(position: Vector3, camera_yaw: float, pitch := -0.15) -> void:
	world.body.global_position = position
	world.body.velocity = Vector3.ZERO
	world.yaw = camera_yaw
	world.pitch = pitch
	world._apply_camera_rotation()
	world.pivot_position = world._focus_point()

func _snap() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGBA8)
	_tiles.append(image)

func _run() -> void:
	var directory: String = OS.get_cmdline_user_args()[0]
	world = load(PLAYGROUND).instantiate()
	root.add_child(world)
	current_scene = world
	await _wait(1.0)
	var target: PlaygroundTarget = world.get_children().filter(func(n): return n is PlaygroundTarget)[0]
	# Aim and a hit.
	_place(Vector3(target.global_position.x - 0.45, 0.0, target.global_position.z + 5.0), 0.0, 0.0)
	await _wait(1.0)
	world.combat.set_aim(true)
	await _wait(0.9)
	await _snap()
	world.combat.fire()
	await _wait(0.45)
	await _snap()
	world.combat.set_aim(false)
	# Cover: crouched behind the low wall, then popped up to aim.
	_place(Vector3(-8.0, 0.0, 3.0), 0.0)
	await _wait(0.5)
	world._cover_or_jump()
	await _wait(1.3)
	await _snap()
	world.combat.set_aim(true)
	await _wait(1.0)
	await _snap()
	world.combat.set_aim(false)
	world.cover.leave()
	# Ladder, mid-climb.
	_place(Vector3(0.0, 0.0, 14.0), PI)
	await _wait(0.5)
	_press(&"playground_forward", true)
	await _wait(2.5)
	_press(&"playground_forward", false)
	await _snap()
	world.traversal.dismount_bottom()
	await _wait(0.3)
	# Stairs, mid-way.
	_place(Vector3(-12.0, 0.0, 4.6), PI)
	world.visual.set_crouched(true)   # crouch and run held on the stairs: the stair pose takes over (this used to sink her into the treads)
	await _wait(0.5)
	_press(&"playground_forward", true)
	_press(&"playground_run", true)
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 9000 and world.body.global_position.y < 1.0:
		await process_frame
	await _wait(0.35)
	await _snap()   # a moment later: the feet are on different phases of their stance
	_press(&"playground_forward", false)
	_press(&"playground_run", false)
	await _snap()
	world.visual.set_crouched(false)
	# Carry.
	_place(Vector3(6.5, 0.0, -5.2), PI)
	await _wait(0.5)
	world.interact()
	await _wait(4.2)
	_press(&"playground_forward", true)
	await _wait(0.8)
	await _snap()
	_press(&"playground_forward", false)
	# Defeat and the respawn screen.
	world.interact()
	await _wait(3.6)
	_place(Vector3(14.0, 0.0, -12.0), PI)
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 9000 and not world.dead:
		await process_frame
	await _wait(PlaygroundPlayerHealth.SCREEN_DELAY + 0.8)
	await _snap()

	var rows := ceili(float(_tiles.size()) / COLUMNS)
	var sheet := Image.create(TILE.x * COLUMNS, TILE.y * rows, false, Image.FORMAT_RGBA8)
	for index in _tiles.size():
		sheet.blit_rect(_tiles[index], Rect2i(Vector2i.ZERO, TILE), Vector2i((index % COLUMNS) * TILE.x, (index / COLUMNS) * TILE.y))
	DirAccess.make_dir_recursive_absolute(directory)
	sheet.save_png(directory + "/exploration-actions-sheet.png")
	print("exploration_actions_capture: %d tiles written to %s/exploration-actions-sheet.png (aim, hit, cover crouched, cover aiming, ladder, stairs, carrying, defeat with respawn screen)" % [_tiles.size(), directory])
	quit(0)
