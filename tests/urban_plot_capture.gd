extends SceneTree
## Explicit-only clean views of the first fixed urban street composition.

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
	environment.background_color = Color("25323a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c3cdd1")
	environment.ambient_light_energy = 0.62
	environment.fog_enabled = true
	environment.fog_light_color = Color("849095")
	environment.fog_density = 0.005
	world.environment = environment
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -34, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var plot := PlotCatalog.definition()
	stage.add_child(plot.scene.instantiate())
	for slot: Dictionary in plot.slots:
		var parcel = ParcelCatalog.candidates(slot.role, slot.size)[0]
		var parcel_root: Node3D = parcel.instantiate()
		parcel_root.transform = ParcelTransform.scene_transform(parcel.size, slot.origin, slot.rotation, plot.map_size)
		stage.add_child(parcel_root)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 44
	stage.add_child(camera)
	for view in [
		["overhead", Vector3(0.01, 76, 0), Vector3.ZERO],
		["oblique", Vector3(52, 38, 56), Vector3(0, 2, 0)],
		["street-west", Vector3(-36, 7, -10), Vector3(0, 4, 3)],
		["street-east", Vector3(36, 7, -9), Vector3(0, 4, 3)],
	]:
		camera.position = view[1]
		camera.look_at(view[2])
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join("urban-service-street-%s.png" % view[0]))
		if error != OK:
			push_error("Urban plot capture failed: %s" % error_string(error))
			quit(1)
			return
	print("Urban plot captures saved to " + output)
	quit()
