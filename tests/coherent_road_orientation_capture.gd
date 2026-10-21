extends SceneTree
## Explicit rendered QA for Task 1.4. It presents only reviewed City Roads
## assets through the production presenter. Derived streetscape diagnostics and
## editor overlays stay disabled so they cannot hide imported pavement seams.

const CAPTURE_SIZE := Vector2i(1600, 900)

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
	root.content_scale_size = CAPTURE_SIZE
	var stage := _build_stage()
	root.add_child(stage)
	var camera := stage.get_node("World/Camera") as Camera3D
	camera.make_current()
	var center: Vector3 = stage.get_meta("fixture_center")
	var curve_seam: Vector3 = stage.get_meta("curve_seam")
	var cross_seam: Vector3 = stage.get_meta("cross_seam")
	var views := [
		{"name": "overhead", "position": center + Vector3(0.01, 58, 0.01), "target": center, "fov": 48.0},
		{"name": "oblique", "position": center + Vector3(-28, 27, 34), "target": center, "fov": 52.0},
		{"name": "curve-seam", "position": curve_seam + Vector3(11, 8, 11), "target": curve_seam, "fov": 42.0},
		{"name": "cross-seam", "position": cross_seam + Vector3(12, 8, -12), "target": cross_seam, "fov": 42.0},
	]
	for view in views:
		camera.fov = view.fov
		camera.look_at_from_position(view.position, view.target)
		await process_frame
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join("road-orientation-%s.png" % view.name))
		if error != OK:
			push_error("Road orientation capture failed: %s" % error)
			quit(1)
			return
	print("Road orientation captures saved to " + output)
	quit()

func _build_stage() -> Node:
	var stage := Node.new()
	var world := Node3D.new()
	world.name = "World"
	stage.add_child(world)
	var data := FlatMapGenerator.generate(60, 55, 1.0, 1404)
	data.environment_modules = [
		EnvironmentModulePlacement.new(&"road_crossroad", Vector2i(25, 20)),
		EnvironmentModulePlacement.new(&"road_straight", Vector2i(25, 10)),
		EnvironmentModulePlacement.new(&"road_straight", Vector2i(25, 0)),
		EnvironmentModulePlacement.new(&"road_straight", Vector2i(15, 20), 1),
		EnvironmentModulePlacement.new(&"road_straight", Vector2i(35, 20), 1),
		EnvironmentModulePlacement.new(&"road_corner", Vector2i(20, 30)),
		EnvironmentModulePlacement.new(&"road_straight", Vector2i(40, 35), 1),
	]
	# False is intentional: imported assets only, without derived roads or overlays.
	ModularEnvironmentPresenter.build(data, world, 1.0, false)
	var center := data.get_cell(Vector3i(30, 0, 26)).world_position
	var curve_seam := data.get_cell(Vector3i(40, 0, 39)).world_position
	var cross_seam := data.get_cell(Vector3i(30, 0, 20)).world_position
	stage.set_meta("fixture_center", center)
	stage.set_meta("curve_seam", curve_seam)
	stage.set_meta("cross_seam", cross_seam)
	_add_ground(world, center)
	_add_lighting(world)
	var camera := Camera3D.new()
	camera.name = "Camera"
	world.add_child(camera)
	return stage

func _add_ground(parent: Node3D, center: Vector3) -> void:
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(64, 59)
	floor.mesh = plane
	floor.position = Vector3(center.x, -0.08, center.z)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("29343a")
	material.roughness = 0.96
	floor.material_override = material
	parent.add_child(floor)

func _add_lighting(parent: Node3D) -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101b24")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c7d3e4")
	environment.ambient_light_energy = 0.8
	environment_node.environment = environment
	parent.add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -28, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	parent.add_child(sun)
