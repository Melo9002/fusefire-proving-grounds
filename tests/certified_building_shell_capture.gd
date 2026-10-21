extends SceneTree
## Explicit rendered inspection for the Phase 3.1 building-i certification.
## Every capture uses the imported shell through the production presenter and
## deliberately contains no engineering overlays or substitute geometry.

const CAPTURE_SIZE := Vector2i(1600, 900)
const COMPONENT_ID := &"industrial_shell_i"
const FRONTAGES := [Vector3.BACK, Vector3.LEFT, Vector3.FORWARD, Vector3.RIGHT]

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
	for rotation in 4:
		var stage := _build_stage(rotation)
		root.add_child(stage)
		await process_frame
		await process_frame
		var camera := stage.get_node("World/Camera") as Camera3D
		var center: Vector3 = stage.get_meta("building_center")
		var frontage: Vector3 = FRONTAGES[rotation]
		var tangent := Vector3(-frontage.z, 0.0, frontage.x)
		camera.look_at_from_position(center + frontage * 19.0 + tangent * 8.0 + Vector3.UP * 9.0, center + Vector3.UP * 1.8)
		camera.make_current()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join("building-i-r%d-frontage.png" % rotation))
		if error != OK:
			push_error("Building shell capture failed: %s" % error)
			quit(1)
			return
		if rotation == 0:
			camera.look_at_from_position(center + Vector3(0.01, 28.0, 0.01), center)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			error = root.get_texture().get_image().save_png(output.path_join("building-i-r0-overhead.png"))
			if error != OK:
				push_error("Building overhead capture failed: %s" % error)
				quit(1)
				return
		root.remove_child(stage)
		stage.free()
	print("Certified building shell captures saved to " + output)
	quit()

func _build_stage(rotation: int) -> Node:
	var stage := Node.new()
	var world := Node3D.new()
	world.name = "World"
	stage.add_child(world)
	var data := FlatMapGenerator.generate(32, 32, 1.0, 3101)
	data.environment_modules.append(EnvironmentModulePlacement.new(COMPONENT_ID, Vector2i(10, 9), rotation))
	ModularEnvironmentPresenter.build(data, world, 1.0)
	var origin := data.get_cell(Vector3i.ZERO).world_position
	var center := origin + Vector3(15.0, 0.0, 15.0)
	stage.set_meta("building_center", center)
	_add_ground(world, center)
	_add_lighting(world)
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = 45.0
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
