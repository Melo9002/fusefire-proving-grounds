extends SceneTree
## Explicit-only clean views of the bounded signal-courtyard composition.

const PlotCatalog = preload("res://systems/generation/urban_plot_catalog.gd")
const ParcelCatalog = preload("res://systems/generation/authored_parcel_catalog.gd")

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
	environment.background_color = Color("1b2730")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b8c8cf")
	environment.ambient_light_energy = 0.58
	environment.fog_enabled = true
	environment.fog_light_color = Color("687a83")
	environment.fog_density = 0.006
	world.environment = environment
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -28, 0)
	sun.light_color = Color("ffd9b0")
	sun.shadow_enabled = true
	stage.add_child(sun)
	var plot := PlotCatalog.definition(PlotCatalog.COURTYARD_B)
	stage.add_child(plot.scene.instantiate())
	for slot: Dictionary in plot.slots:
		var parcel = ParcelCatalog.candidates(slot.role, slot.size)[0]
		var parcel_root: Node3D = parcel.instantiate()
		parcel_root.transform = ParcelTransform.scene_transform(parcel.size, slot.origin, slot.rotation, plot.map_size)
		stage.add_child(parcel_root)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 46
	stage.add_child(camera)
	for view in [
		["overhead", Vector3(0.01, 78, 5), Vector3(0, 0, 2)],
		["approach", Vector3(0, 9, 42), Vector3(0, 3, -8)],
		["oblique", Vector3(52, 36, 52), Vector3(0, 3, -2)],
		["gallery", Vector3(-27, 8, 14), Vector3(0, 4, -4)],
	]:
		camera.position = view[1]
		camera.look_at(view[2])
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join("urban-signal-courtyard-%s.png" % view[0]))
		if error != OK:
			push_error("Urban courtyard capture failed: %s" % error_string(error))
			quit(1)
			return
	print("Urban courtyard captures saved to " + output)
	quit()
