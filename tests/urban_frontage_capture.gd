extends SceneTree
## Explicit-only all-sides review of the first bounded urban parcel proof.

const Catalog = preload("res://systems/generation/authored_parcel_catalog.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		push_error("A rendered window and output directory are required.")
		quit(1)
		return
	var output: String = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("17232d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c4d0dc")
	environment.ambient_light_energy = 0.7
	world.environment = environment
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -32, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var definition = Catalog.get_definition(Catalog.INDUSTRIAL_OFFICE_PARKING_A)
	var parcel: Node3D = definition.instantiate()
	# Explicit inspection case: neighboring bays demonstrate opposing headings.
	definition.apply_population(parcel, [
		{"socket_id": &"parking_west", "yaw_turns": 0},
		{"socket_id": &"parking_mid", "yaw_turns": 2},
		{"socket_id": &"parking_east", "yaw_turns": 0},
	])
	parcel.position = Vector3(-15.5, 0, -15.5)
	stage.add_child(parcel)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 44
	stage.add_child(camera)
	for view in [
		["overhead", Vector3(0.01, 48, -0.01), Vector3.ZERO],
		["front-oblique", Vector3(30, 23, -38), Vector3(0, 4, 1)],
		["street-front", Vector3(0, 7, -38), Vector3(0, 4.5, 2)],
		["rear", Vector3(0, 8, 39), Vector3(0, 5, 5)],
		["side", Vector3(42, 10, 3), Vector3(0, 5, 3)],
	]:
		camera.position = view[1]
		camera.look_at(view[2])
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join("urban-frontage-%s.png" % view[0]))
		if error != OK:
			push_error("Urban frontage capture failed: %s" % error_string(error))
			quit(1)
			return
	print("Urban frontage captures saved to " + output)
	quit()
