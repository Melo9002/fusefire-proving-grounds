extends Node3D

const OrbitCamera = preload("res://tools/inspection_orbit_camera.gd")

@export var generation_seed := 2202
var content: Node3D
var status: Label
var seed_input: SpinBox
var camera: Camera3D
var orbit: RefCounted

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].is_valid_int():
		generation_seed = int(args[0])
	_build_ui()
	_rebuild()

func _shortcut_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_rebuild()
		elif event.keycode == KEY_F:
			_frame_camera()
		elif event.keycode == KEY_BRACKETRIGHT:
			_set_seed(generation_seed + 1)
		elif event.keycode == KEY_BRACKETLEFT:
			_set_seed(generation_seed - 1)

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(orbit) and orbit.handle_mouse(event):
		get_viewport().set_input_as_handled()

func _rebuild() -> void:
	if content:
		content.free()
	content = Node3D.new()
	content.name = "PreviewContent"
	add_child(content)
	var data := FlatMapGenerator.generate_modular_industrial_sample(40, 30, 1.0, generation_seed)
	var ground_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 30)
	ground_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("303a3f")
	floor_material.roughness = 1.0
	ground_mesh.material_override = floor_material
	content.add_child(ground_mesh)
	_add_grid_overlay(content, data.map_size, 1.0)
	GeneratedTerrainPresenter.build(data, content, 1.0)
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	var validation := MapValidator.validate(data, graph, {
		TacticalUnit.Faction.PLAYER: 5,
		TacticalUnit.Faction.ENEMY: 5,
	})
	status.text = "MODULAR INDUSTRIAL PREVIEW  |  seed %d  |  %d components  |  %s\nR regenerate · [ / ] seed · RMB orbit · MMB pan · wheel zoom · F frame" % [
		generation_seed, data.environment_modules.size(), "VALID" if validation.is_valid() else validation.describe()
	]
	if is_instance_valid(seed_input):
		seed_input.set_value_no_signal(generation_seed)

func _build_ui() -> void:
	camera = Camera3D.new()
	camera.position = Vector3(30, 24, 30)
	camera.fov = 55.0
	camera.look_at_from_position(camera.position, Vector3.ZERO)
	add_child(camera)
	orbit = OrbitCamera.new(camera)
	orbit.focus = Vector3.ZERO
	orbit.distance = 34.0
	orbit.apply()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("18232d")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("9fb5c2")
	settings.ambient_light_energy = 0.75
	environment.environment = settings
	add_child(environment)
	var layer := CanvasLayer.new()
	add_child(layer)
	status = Label.new()
	status.position = Vector2(18, 18)
	status.add_theme_font_size_override("font_size", 18)
	layer.add_child(status)
	var controls := HBoxContainer.new()
	controls.position = Vector2(18, 72)
	layer.add_child(controls)
	var previous := Button.new()
	previous.text = "Previous seed"
	previous.pressed.connect(func(): _set_seed(generation_seed - 1))
	controls.add_child(previous)
	seed_input = SpinBox.new()
	seed_input.min_value = -2147483648
	seed_input.max_value = 2147483647
	seed_input.step = 1
	seed_input.value = generation_seed
	seed_input.custom_minimum_size.x = 150
	seed_input.value_changed.connect(func(value): _set_seed(int(value)))
	controls.add_child(seed_input)
	var next := Button.new()
	next.text = "Next seed"
	next.pressed.connect(func(): _set_seed(generation_seed + 1))
	controls.add_child(next)
	var regenerate := Button.new()
	regenerate.text = "Regenerate"
	regenerate.pressed.connect(_rebuild)
	controls.add_child(regenerate)
	var frame_button := Button.new()
	frame_button.text = "Frame map"
	frame_button.pressed.connect(_frame_camera)
	controls.add_child(frame_button)

func _set_seed(value: int) -> void:
	generation_seed = value
	_rebuild()

func _frame_camera() -> void:
	if is_instance_valid(orbit):
		# Generated MapData is centered around the world origin. Framing a
		# positive-only box put the actual assembly in the corner of the view.
		orbit.frame(AABB(Vector3(-20, 0, -15), Vector3(40, 8, 30)))

func _add_grid_overlay(parent: Node3D, map_size: Vector2i, cell_size: float) -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.34, 0.68, 0.74, 0.32)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var half_width := float(map_size.x) * cell_size * 0.5
	var half_depth := float(map_size.y) * cell_size * 0.5
	for x in map_size.x + 1:
		var world_x := -half_width + float(x) * cell_size
		mesh.surface_add_vertex(Vector3(world_x, 0.035, -half_depth))
		mesh.surface_add_vertex(Vector3(world_x, 0.035, half_depth))
	for z in map_size.y + 1:
		var world_z := -half_depth + float(z) * cell_size
		mesh.surface_add_vertex(Vector3(-half_width, 0.035, world_z))
		mesh.surface_add_vertex(Vector3(half_width, 0.035, world_z))
	mesh.surface_end()
	var overlay := MeshInstance3D.new()
	overlay.name = "TacticalGrid"
	overlay.mesh = mesh
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(overlay)
