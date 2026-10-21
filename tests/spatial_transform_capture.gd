extends SceneTree
## Explicit rendered QA for the canonical module transform. This uses the real
## building-i catalog definition and ModularEnvironmentPresenter; the marker is
## a diagnostic indication of the independently expected frontage.

const CAPTURE_SIZE := Vector2i(1600, 900)
const PLACEMENT_ORIGIN := Vector2i(10, 9)

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
	var expected_frontages := [Vector3.BACK, Vector3.LEFT, Vector3.FORWARD, Vector3.RIGHT]
	var labels := ["+Z / grid DOWN", "-X / grid LEFT", "-Z / grid UP", "+X / grid RIGHT"]
	var caption := _create_caption()
	for rotation in 4:
		caption.text = "BUILDING-I  |  MODULE ROTATION %d  |  EXPECTED FRONTAGE %s\nGreen marker identifies the authored frontage side." % [rotation, labels[rotation]]
		var stage := _build_stage(rotation, expected_frontages[rotation])
		root.add_child(stage)
		(stage.get_node("World/Camera") as Camera3D).make_current()
		await process_frame
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var filename := "building-i-r%d.png" % rotation
		var error := root.get_texture().get_image().save_png(output.path_join(filename))
		stage.queue_free()
		await process_frame
		if error != OK:
			push_error("Spatial transform capture failed: %s" % error)
			quit(1)
			return
	print("Spatial transform captures saved to " + output)
	quit()

func _build_stage(rotation: int, expected_frontage: Vector3) -> Node:
	var stage := Node.new()
	var world := Node3D.new()
	world.name = "World"
	stage.add_child(world)
	var data := FlatMapGenerator.generate(36, 34, 1.0, 1201 + rotation)
	data.environment_modules.append(EnvironmentModulePlacement.new(&"industrial_shell_i", PLACEMENT_ORIGIN, rotation))
	ModularEnvironmentPresenter.build(data, world, 1.0)
	var definition: EnvironmentModuleDefinition = IndustrialModuleCatalog.create().industrial_shell_i
	var dimensions := definition.rotated_size(rotation)
	var origin_world := data.get_cell(Vector3i(PLACEMENT_ORIGIN.x, 0, PLACEMENT_ORIGIN.y)).world_position
	var center := origin_world + Vector3(float(dimensions.x - 1) * 0.5, 0.0, float(dimensions.y - 1) * 0.5)
	_add_ground(world, center)
	_add_frontage_marker(world, center, dimensions, expected_frontage)
	_add_lighting(world)
	var camera := Camera3D.new()
	camera.name = "Camera"
	world.add_child(camera)
	var oblique := Vector3(expected_frontage.z, 0.0, -expected_frontage.x)
	camera.position = center + expected_frontage * 20.0 + oblique * 10.0 + Vector3.UP * 13.0
	camera.look_at_from_position(camera.position, center + Vector3.UP * 3.0)
	camera.fov = 48.0
	return stage

func _add_ground(parent: Node3D, center: Vector3) -> void:
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(34.0, 32.0)
	floor.mesh = plane
	floor.position = Vector3(center.x, -0.02, center.z)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("48565b")
	material.roughness = 0.95
	floor.material_override = material
	parent.add_child(floor)

func _add_frontage_marker(parent: Node3D, center: Vector3, dimensions: Vector2i, direction: Vector3) -> void:
	var half_extent := float(dimensions.x) * 0.5 if absf(direction.x) > 0.5 else float(dimensions.y) * 0.5
	var marker := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.42
	cylinder.bottom_radius = 0.42
	cylinder.height = 0.16
	marker.mesh = cylinder
	marker.position = center + direction * (half_extent + 1.0) + Vector3.UP * 0.09
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("55f28b")
	material.emission_enabled = true
	material.emission = Color("1ed760")
	material.emission_energy_multiplier = 1.8
	marker.material_override = material
	parent.add_child(marker)

func _add_lighting(parent: Node3D) -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("14212a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b8c8df")
	environment.ambient_light_energy = 0.75
	environment_node.environment = environment
	parent.add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	parent.add_child(sun)

func _create_caption() -> Label:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var panel := ColorRect.new()
	panel.position = Vector2(20, 20)
	panel.size = Vector2(660, 78)
	panel.color = Color(0.035, 0.055, 0.07, 0.92)
	layer.add_child(panel)
	var label := Label.new()
	label.position = Vector2(18, 11)
	label.add_theme_font_size_override("font_size", 22)
	panel.add_child(label)
	return label
