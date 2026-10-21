extends SceneTree
## Explicit visual review for the bounded Phase 3.3 service parcel.

const CAPTURE_SIZE := Vector2i(1600, 900)

func _initialize() -> void: _run.call_deferred()

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
	await process_frame
	await process_frame
	var camera := stage.get_node("World/Camera") as Camera3D
	var center: Vector3 = stage.get_meta("parcel_center")
	var views := {
		"overhead": center + Vector3(0.01, 25, 0.01),
		"oblique": center + Vector3(13, 10, 13),
		"service-access": center + Vector3(-14, 5.5, 0),
	}
	for label in views:
		camera.look_at_from_position(views[label], center + Vector3.UP * 1.0)
		camera.make_current()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join("pipe-service-pad-%s.png" % label))
		if error != OK:
			push_error("Equipment parcel capture failed: %s" % error)
			quit(1)
			return
	print("Certified equipment parcel captures saved to " + output)
	quit()

func _build_stage() -> Node:
	var stage := Node.new()
	var world := Node3D.new()
	world.name = "World"
	stage.add_child(world)
	var data := FlatMapGenerator.generate(32, 32, 1.0, 3303)
	var layout := ModularIndustrialLayoutBuilder.apply(data, 1.0, 3303, &"certified_equipment_parcel")
	if not layout.errors.is_empty(): push_error("Capture fixture invalid: " + ";".join(layout.errors))
	ModularEnvironmentPresenter.build(data, world, 1.0)
	var origin := data.get_cell(Vector3i.ZERO).world_position
	var center := origin + Vector3(15, 0, 15)
	stage.set_meta("parcel_center", center)
	_add_ground(world, center)
	_add_lighting(world)
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = 44.0
	world.add_child(camera)
	return stage

func _add_ground(parent: Node3D, center: Vector3) -> void:
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(34, 34)
	floor.mesh = plane
	floor.position = Vector3(center.x, -0.04, center.z)
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
	environment.ambient_light_energy = 0.82
	environment_node.environment = environment
	parent.add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -28, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	parent.add_child(sun)
