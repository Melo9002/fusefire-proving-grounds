extends SceneTree
## Rendered look at the Exploration Playground's foundation work (explicit-only, needs a display; stills, not motion):
##   godot_console --path . --script res://tests/playground_foundation_capture.gd -- <directory> [width=640] [height=400]
## One image per view, through the playground's own camera and real input: the casualty station on entering, each carrier at each casualty with its prompt, both casualties side by side after a put-down, the body put down
## at the ladder's foot (clear of the tower), the ramp with the foot placement off and on (standing and mid-stride), the run onto the stairs, and the clean inspection view.
const PLAYGROUND := "res://research/exploration_playground/exploration_playground.tscn"
var world: Node
var _directory := ""
var _size := Vector2i(640, 400)


func _initialize() -> void:
	_run.call_deferred()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _press(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _place(position: Vector3, camera_yaw: float, pitch := -0.15, zoom := 3.2) -> void:
	world.body.global_position = position
	world.body.velocity = Vector3.ZERO
	world.yaw = camera_yaw
	world.pitch = pitch
	world.zoom = zoom
	world.spring.spring_length = zoom
	world._apply_camera_rotation()
	world.pivot_position = world._focus_point()


func _snap(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.resize(_size.x, _size.y, Image.INTERPOLATE_LANCZOS)
	image.save_png("%s/%s.png" % [_directory, name])
	print("saved ", name)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_directory = args[0]
	for argument in args.slice(1):
		var parts := String(argument).split("=", true, 1)
		if parts.size() == 2 and parts[0] == "width":
			_size.x = int(parts[1])
		elif parts.size() == 2 and parts[0] == "height":
			_size.y = int(parts[1])
	DirAccess.make_dir_recursive_absolute(_directory)
	world = load(PLAYGROUND).instantiate()
	root.add_child(world)
	current_scene = world
	await _wait(1.0)
	# The station, from above and behind the spawn point's side.
	_place(Vector3(8.0, 0.0, -2.5), PI, -0.5, 8.0)
	await _wait(0.8)
	await _snap("01_station_overview")
	for pair in [[0, 6.5, "02_regular_at_regular"], [0, 9.5, "03_regular_at_small"], [1, 6.5, "04_small_at_regular"], [1, 9.5, "05_small_at_small"]]:
		world._select_character(pair[0])
		await _wait(0.4)
		_place(Vector3(pair[1], 0.0, -5.2), PI, -0.2, 3.6)
		await _wait(0.6)
		await _snap(pair[2])
	# Small carries Regular; then both casualties lie side by side again after the put-down.
	world._select_character(1)
	await _wait(0.4)
	_place(Vector3(6.5, 0.0, -5.2), PI, -0.2, 4.5)
	await _wait(0.4)
	world.interact()
	await _wait(5.0)
	await _snap("06_small_carries_regular")
	_place(Vector3(8.0, 0.0, -2.0), PI, -0.25, 5.0)
	await _wait(0.5)
	world.interact()
	await _wait(4.5)
	await _snap("07_put_down_beside_station")
	# At the ladder's foot, carrying, facing the tower: the body is put down clear of it.
	world._select_character(0)
	await _wait(0.4)
	_place(Vector3(9.5, 0.0, -5.2), PI, -0.2, 4.0)
	await _wait(0.4)
	world.interact()
	await _wait(5.0)
	world.traversal.place_at_approach(false)
	_place(world.traversal.ladder_foot(), PI, -0.3, 5.0)
	await _wait(0.5)
	await _snap("08_loaded_at_ladder_foot")
	world.interact()
	await _wait(4.5)
	await _snap("09_put_down_at_ladder_foot")
	# The ramp: standing and mid-stride, foot placement off, then on.
	world.carry.reset_all()
	for follow in [false, true]:
		world.visual.rig.set_ground_sampler(world.visual._sample_ground if follow else Callable())
		for case in ["stand", "stride"]:
			world.body.global_position = Vector3(11.0, 0.7, 8.0) if case == "stand" else Vector3(8.6, 0.1, 8.0)
			world.body.velocity = Vector3.ZERO
			world.yaw = -PI * 0.5 + 0.9
			world.pitch = -0.1
			world.zoom = 2.6
			world.spring.spring_length = 2.6
			world._apply_camera_rotation()
			world.visual.reset_motion(0.0)
			await _wait(0.8)
			if case == "stride":
				world.yaw = -PI * 0.5 + 1.0
				_press(&"playground_forward", true)
				await _wait(1.25)
				_press(&"playground_forward", false)
			await _snap("10_ramp_%s_%s" % [case, "on" if follow else "off"])
	# A run at the stairs.
	var stairs: StairModel = world.traversal.stairs
	_place(stairs.low + Vector3(0.0, 0.0, -3.0), PI + 0.5, -0.2, 3.4)
	world.visual.reset_motion(0.0)
	await _wait(0.6)
	_press(&"playground_forward", true)
	_press(&"playground_run", true)
	await _wait(0.9)
	await _snap("11_run_at_stairs")
	await _wait(1.0)
	await _snap("12_on_the_stairs")
	_press(&"playground_forward", false)
	_press(&"playground_run", false)
	await _wait(0.4)
	# The clean inspection view.
	_place(Vector3(8.0, 0.0, -2.5), PI, -0.4, 6.0)
	world.set_clean_view(true)
	await _wait(0.5)
	await _snap("13_clean_view")
	quit()
