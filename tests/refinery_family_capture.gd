extends SceneTree
## Explicit-only rendered inspection for both authored refinery plot layouts.

const Layout = preload("res://systems/generation/refinery_family_layout.gd")

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
	for seed in [0, 3]:
		await _capture_seed(seed, output)
	print("Refinery family captures saved to " + output)
	quit()

func _capture_seed(seed: int, output: String) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("16232c")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b9c8d4")
	settings.ambient_light_energy = 0.7
	world.environment = settings
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var data := Layout.generate(seed)
	# Match the normal battle scene's authoritative floor so captures expose
	# road/floor layering defects instead of reviewing the plot in isolation.
	var tactical_floor := CSGBox3D.new()
	tactical_floor.name = "TacticalMapFloor"
	tactical_floor.size = Vector3(64, 1, 64)
	tactical_floor.position.y = -0.5
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("4d514f")
	floor_material.roughness = 0.95
	tactical_floor.material = floor_material
	stage.add_child(tactical_floor)
	if not Layout.present(data, stage, 1.0):
		push_error("Could not present seed %d: %s" % [seed, data.generation_errors])
		quit(1)
		return
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 45
	stage.add_child(camera)
	for view in [
		["overhead", Vector3(0.01, 82, 0.01), Vector3.ZERO],
		["oblique", Vector3(67, 50, 67), Vector3(0, 1.5, 0)],
		["ground", Vector3(-25, 5, 29), Vector3(8, 2, -3)],
	]:
		camera.position = view[1]
		camera.look_at(view[2])
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join("refinery-family-seed-%d-%s.png" % [seed, view[0]]))
		if error != OK:
			push_error("Capture failed for seed %d/%s: %s" % [seed, view[0], error])
			quit(1)
			return
	stage.free()
	await process_frame
