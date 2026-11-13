extends SceneTree
## Explicit-only rendered inspection through the battlefield presenter.

const Catalog = preload("res://systems/generation/battlefield_catalog.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		push_error("A rendered window and output directory are required.")
		quit(1)
		return
	var output := args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = Environment.new()
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_sky_contribution = 0.0
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var data := Catalog.generate(Catalog.PARKING_GARAGE, Vector2i.ONE, 17, 1.0)
	if not data.generation_errors.is_empty() or not Catalog.present_special(data, stage, 1.0):
		push_error("Garage presentation failed: %s" % [data.generation_errors])
		quit(1)
		return
	var deck := stage.find_child("UpperDeck", true, false) as WarehouseRoofCutaway
	var camera := Camera3D.new()
	camera.fov = 49
	stage.add_child(camera)
	camera.current = true
	for view in [
		["overhead", Vector3(0, 45, 0.1), Vector3(0, 0, 0), false],
		["approach", Vector3(-22, 8, -26), Vector3(0, 2, 0), false],
		["rear-ramp", Vector3(23, 13, 28), Vector3(0, 3, 11), false],
		["ground-cutaway", Vector3(21, 19, -22), Vector3(0, 0, 2), true],
	]:
		camera.position = view[1]
		camera.look_at(view[2])
		if view[3]:
			deck.update_view(camera.position, [view[2]])
		else:
			deck.restore_view()
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join("garage-17-%s.png" % view[0]))
		if error != OK:
			push_error("Garage capture failed: %s" % error_string(error))
			quit(1)
			return
	print("Garage captures saved to " + output)
	quit()
