extends SceneTree
## Explicit rendered QA for Task 2.3's bounded asset-first streetscape.
## Clean views prove the imported assets stand on their own; contract views add
## access and reservation lines only after the clean result has been captured.

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
	var overlay := stage.get_node("World/EngineeringOverlay") as Node3D
	var center: Vector3 = stage.get_meta("fixture_center")
	var frontage: Vector3 = stage.get_meta("frontage_center")
	var sidewalk: Vector3 = stage.get_meta("sidewalk_center")
	var road_seam: Vector3 = stage.get_meta("road_seam")
	var views := [
		{"name": "clean-overhead", "overlay": false, "position": center + Vector3(0.01, 50, 0.01), "target": center, "fov": 46.0},
		{"name": "clean-oblique", "overlay": false, "position": center + Vector3(-31, 22, 31), "target": center + Vector3(1, 1.5, 0), "fov": 49.0},
		{"name": "clean-frontage", "overlay": false, "position": frontage + Vector3(-16, 7, 12), "target": frontage + Vector3(0, 2.0, 0), "fov": 44.0},
		{"name": "clean-sidewalk", "overlay": false, "position": sidewalk + Vector3(-7, 3.8, -9), "target": sidewalk + Vector3(4, 1.0, 2), "fov": 48.0},
		{"name": "clean-road-seam", "overlay": false, "position": road_seam + Vector3(-4, 10, -5), "target": road_seam + Vector3(0, 0.15, 0), "fov": 38.0},
		{"name": "contracts-road-seam", "overlay": true, "position": road_seam + Vector3(-4, 10, -5), "target": road_seam + Vector3(0, 0.15, 0), "fov": 38.0},
		{"name": "contracts-overhead", "overlay": true, "position": center + Vector3(0.01, 50, 0.01), "target": center, "fov": 46.0},
		{"name": "contracts-frontage", "overlay": true, "position": frontage + Vector3(-16, 8, 12), "target": frontage + Vector3(0, 1.5, 0), "fov": 44.0},
	]
	for view in views:
		overlay.visible = view.overlay
		camera.fov = view.fov
		camera.look_at_from_position(view.position, view.target)
		await process_frame
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join("asset-first-frontage-%s.png" % view.name))
		if error != OK:
			push_error("Asset-first frontage capture failed: %s" % error)
			quit(1)
			return
	root.remove_child(stage)
	stage.free()
	for rotation in 4:
		var rotation_stage := _build_rotation_stage(rotation)
		root.add_child(rotation_stage)
		camera = rotation_stage.get_node("World/Camera") as Camera3D
		camera.make_current()
		var rotation_center: Vector3 = rotation_stage.get_meta("fixture_center")
		var frontage_direction: Vector3 = [Vector3.LEFT, Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK][rotation]
		var tangent := Vector3(-frontage_direction.z, 0.0, frontage_direction.x)
		camera.fov = 49.0
		camera.look_at_from_position(rotation_center + frontage_direction * 22.0 + tangent * 15.0 + Vector3.UP * 17.0, rotation_center + Vector3.UP * 1.5)
		await process_frame
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join("asset-first-frontage-certification-r%d.png" % rotation))
		if error != OK:
			push_error("Asset-first frontage rotation capture failed: %s" % error)
			quit(1)
			return
		root.remove_child(rotation_stage)
		rotation_stage.free()
	print("Asset-first frontage captures saved to " + output)
	quit()

func _build_stage() -> Node:
	var stage := Node.new()
	var world := Node3D.new()
	world.name = "World"
	stage.add_child(world)
	var data := FlatMapGenerator.generate_modular_environment_sample(40, 30, 1.0, 2303, &"asset_first_frontage")
	ModularEnvironmentPresenter.build(data, world, 1.0, ModularEnvironmentPresenter.RoadPresentationMode.ASSET_FIRST)
	var center := data.get_cell(Vector3i(18, 0, 14)).world_position
	var frontage := data.get_cell(Vector3i(23, 0, 14)).world_position
	var sidewalk := data.get_cell(Vector3i(12, 0, 12)).world_position
	var road_seam := data.get_cell(Vector3i(9, 0, 15)).world_position
	stage.set_meta("fixture_center", center)
	stage.set_meta("frontage_center", frontage)
	stage.set_meta("sidewalk_center", sidewalk)
	stage.set_meta("road_seam", road_seam)
	_add_ground(world, center)
	_add_lighting(world)
	_add_engineering_overlay(world, data)
	var camera := Camera3D.new()
	camera.name = "Camera"
	world.add_child(camera)
	return stage

func _build_rotation_stage(rotation: int) -> Node:
	var stage := Node.new()
	var world := Node3D.new()
	world.name = "World"
	stage.add_child(world)
	var data := _rotated_fixture(rotation)
	ModularEnvironmentPresenter.build(data, world, 1.0, ModularEnvironmentPresenter.RoadPresentationMode.ASSET_FIRST)
	var road_access := _rotate_square_cell(ModularIndustrialLayoutBuilder.REFERENCE_ROAD_ACCESS, rotation)
	var frontage_access := _rotate_square_cell(ModularIndustrialLayoutBuilder.REFERENCE_FRONTAGE_ACCESS, rotation)
	var center := (_world(data, road_access) + _world(data, frontage_access)) * 0.5
	stage.set_meta("fixture_center", center)
	_add_square_ground(world, data)
	_add_lighting(world)
	var camera := Camera3D.new()
	camera.name = "Camera"
	world.add_child(camera)
	return stage

func _rotated_fixture(rotation: int) -> MapData:
	var catalog := IndustrialModuleCatalog.create()
	var source := FlatMapGenerator.generate_modular_environment_sample(40, 40, 1.0, 2303, &"asset_first_frontage")
	var result := FlatMapGenerator.generate(40, 40, 1.0, 2303)
	var layout := EnvironmentModuleLayout.new(&"asset_first_frontage_capture_r%d" % rotation, 2303)
	for placement: EnvironmentModulePlacement in source.environment_modules:
		var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
		var size := definition.rotated_size(placement.rotation)
		var rotated := EnvironmentModulePlacement.new(
			placement.component_id,
			_rotate_square_rect_origin(placement.origin, size, rotation),
			posmod(placement.rotation + rotation, 4),
			placement.variation,
			placement.elevation
		)
		if not layout.try_add(definition, rotated, result.map_size):
			push_error("Rotation capture placement failed: %s" % "; ".join(layout.errors))
	for failure in EnvironmentModuleMapWriter.apply(result, layout, catalog, 1.0):
		push_error("Rotation capture compilation failed: %s" % failure.message)
	result.environment_modules.assign(layout.placements)
	result.environment_module_seed = 2303
	result.rebuild_los_index()
	return result

func _rotate_square_rect_origin(origin: Vector2i, size: Vector2i, rotation: int) -> Vector2i:
	match rotation:
		1: return Vector2i(40 - origin.y - size.y, origin.x)
		2: return Vector2i(40 - origin.x - size.x, 40 - origin.y - size.y)
		3: return Vector2i(origin.y, 40 - origin.x - size.x)
		_: return origin

func _rotate_square_cell(cell: Vector2i, rotation: int) -> Vector2i:
	match rotation:
		1: return Vector2i(39 - cell.y, cell.x)
		2: return Vector2i(39 - cell.x, 39 - cell.y)
		3: return Vector2i(cell.y, 39 - cell.x)
		_: return cell

func _add_engineering_overlay(parent: Node3D, data: MapData) -> void:
	var overlay := Node3D.new()
	overlay.name = "EngineeringOverlay"
	parent.add_child(overlay)
	var immediate := ImmediateMesh.new()
	var lines := MeshInstance3D.new()
	lines.mesh = immediate
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	lines.material_override = material
	overlay.add_child(lines)
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	# Green: the explicit walkable street-to-frontage route.
	var start := _world(data, ModularIndustrialLayoutBuilder.REFERENCE_ROAD_ACCESS) + Vector3.UP * 0.35
	var finish := _world(data, ModularIndustrialLayoutBuilder.REFERENCE_FRONTAGE_ACCESS) + Vector3.UP * 0.35
	_line(immediate, start, finish, Color("56e58a"))
	for x in range(ModularIndustrialLayoutBuilder.REFERENCE_ROAD_ACCESS.x, ModularIndustrialLayoutBuilder.REFERENCE_FRONTAGE_ACCESS.x + 1):
		var point := _world(data, Vector2i(x, ModularIndustrialLayoutBuilder.REFERENCE_ROAD_ACCESS.y)) + Vector3.UP * 0.35
		_cross(immediate, point, 0.22, Color("56e58a"))
	# Cyan: imported road-to-paving transition seams.
	for z in [5, 15]:
		_line(immediate, _world_corner(data, Vector2(13.5, z - 0.5), 0.30), _world_corner(data, Vector2(13.5, z + 9.5), 0.30), Color("43d8ed"))
	# Red: the physical end-to-end seam between the two road tiles. The clean
	# capture deliberately omits this locator so any transverse band stays real.
	_line(immediate, _world_corner(data, Vector2(4.0, 15.0), 0.31), _world_corner(data, Vector2(14.0, 15.0), 0.31), Color("ff5d5d"))
	# Gold: the sealed building's protected three-cell frontage apron.
	_draw_rect(immediate, data, Rect2(Vector2(20.5, 11.5), Vector2(3.0, 6.0)), 0.32, Color("f6bd4a"))
	# Magenta: streetlight authored visual reservations, calculated through the
	# same corrected rectangular-envelope transform inspected by Phase 1.
	var catalog := IndustrialModuleCatalog.create()
	var layout := EnvironmentModuleLayout.new(&"capture_contracts", data.environment_module_seed)
	for placement: EnvironmentModulePlacement in data.environment_modules:
		layout.try_add(catalog[placement.component_id], placement, data.map_size)
		if placement.component_id != &"street_light":
			continue
		var bounds := layout.world_visual_envelope(catalog[placement.component_id], placement)
		_draw_rect(immediate, data, Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)), 0.34, Color("ec6fd2"))
	immediate.surface_end()
	overlay.visible = false

func _line(mesh: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(to)

func _cross(mesh: ImmediateMesh, center: Vector3, radius: float, color: Color) -> void:
	_line(mesh, center - Vector3(radius, 0, 0), center + Vector3(radius, 0, 0), color)
	_line(mesh, center - Vector3(0, 0, radius), center + Vector3(0, 0, radius), color)

func _draw_rect(mesh: ImmediateMesh, data: MapData, rect: Rect2, height: float, color: Color) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index in 4:
		_line(mesh, _world_corner(data, corners[index], height), _world_corner(data, corners[(index + 1) % 4], height), color)

func _world(data: MapData, cell: Vector2i) -> Vector3:
	return data.get_cell(Vector3i(cell.x, 0, cell.y)).world_position

func _world_corner(data: MapData, point: Vector2, height: float) -> Vector3:
	var origin := data.get_cell(Vector3i(0, 0, 0)).world_position
	return origin + Vector3(point.x, height, point.y)

func _add_ground(parent: Node3D, center: Vector3) -> void:
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(44, 34)
	floor.mesh = plane
	floor.position = Vector3(center.x + 1.5, -0.08, center.z + 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("29343a")
	material.roughness = 0.96
	floor.material_override = material
	parent.add_child(floor)

func _add_square_ground(parent: Node3D, data: MapData) -> void:
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(44, 44)
	floor.mesh = plane
	floor.position = data.get_cell(Vector3i(19, 0, 19)).world_position + Vector3(0.5, -0.08, 0.5)
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
