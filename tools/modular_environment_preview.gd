extends Node3D

const OrbitCamera = preload("res://tools/inspection_orbit_camera.gd")
const AssetPlacement = preload("res://presentation/environment_asset_placement.gd")

@export var generation_seed := 2202
var content: Node3D
var status: Label
var seed_input: SpinBox
var camera: Camera3D
var orbit: RefCounted
var inspection_target := "whole map"
var inspection_module: Node3D
var adjustment_step: SpinBox
var transform_label: Label
var selection_outline_material: StandardMaterial3D

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
		elif event.keycode == KEY_C:
			_focus_component(&"factory_wall_corner", "factory corner — outer, scale 2.0")
		elif event.keycode == KEY_G:
			_focus_component(&"road_straight", "road / paving seam")
		elif event.keycode == KEY_1:
			_set_camera_view(0.0, 0.18)
		elif event.keycode == KEY_3:
			_set_camera_view(PI * 0.5, 0.18)
		elif event.keycode == KEY_7:
			_set_camera_view(0.0, 1.50)
		elif event.keycode == KEY_TAB:
			_select_next_module()
		elif event.keycode == KEY_LEFT:
			_nudge_inspection(Vector3.LEFT * _adjustment_amount())
		elif event.keycode == KEY_RIGHT:
			_nudge_inspection(Vector3.RIGHT * _adjustment_amount())
		elif event.keycode == KEY_UP:
			_nudge_inspection(Vector3.FORWARD * _adjustment_amount())
		elif event.keycode == KEY_DOWN:
			_nudge_inspection(Vector3.BACK * _adjustment_amount())
		elif event.keycode == KEY_PAGEUP:
			_nudge_inspection(Vector3.UP * _adjustment_amount())
		elif event.keycode == KEY_PAGEDOWN:
			_nudge_inspection(Vector3.DOWN * _adjustment_amount())
		elif event.keycode == KEY_Q:
			_rotate_inspection(-90.0)
		elif event.keycode == KEY_E:
			_rotate_inspection(90.0)
		elif event.keycode == KEY_BRACKETRIGHT:
			_set_seed(generation_seed + 1)
		elif event.keycode == KEY_BRACKETLEFT:
			_set_seed(generation_seed - 1)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _select_module_at_screen(event.position):
			get_viewport().set_input_as_handled()
			return
	if is_instance_valid(orbit) and orbit.handle_mouse(event):
		get_viewport().set_input_as_handled()

func _rebuild() -> void:
	if content:
		content.free()
	inspection_module = null
	inspection_target = "whole map"
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
	_update_status(data.environment_modules.size(), "VALID" if validation.is_valid() else validation.describe())
	if is_instance_valid(seed_input):
		seed_input.set_value_no_signal(generation_seed)

func _build_ui() -> void:
	selection_outline_material = StandardMaterial3D.new()
	selection_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selection_outline_material.albedo_color = Color(1.0, 0.72, 0.18, 0.95)
	selection_outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
	selection_outline_material.grow = true
	selection_outline_material.grow_amount = 0.025
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
	var corner_button := Button.new()
	corner_button.text = "Inspect corner"
	corner_button.tooltip_text = "Frame the assembled Factory outer-corner joint (C)"
	corner_button.pressed.connect(func(): _focus_component(&"factory_wall_corner", "factory corner — outer, scale 2.0"))
	controls.add_child(corner_button)
	var road_button := Button.new()
	road_button.text = "Inspect road seam"
	road_button.tooltip_text = "Frame the road and paving connection (G)"
	road_button.pressed.connect(func(): _focus_component(&"road_straight", "road / paving seam"))
	controls.add_child(road_button)
	var views := HBoxContainer.new()
	views.position = Vector2(18, 112)
	layer.add_child(views)
	_add_view_button(views, "Front (1)", 0.0, 0.18)
	_add_view_button(views, "Side (3)", PI * 0.5, 0.18)
	_add_view_button(views, "Top (7)", 0.0, 1.50)
	_add_action_button(views, "Next piece (Tab)", _select_next_module)
	var nudges := HBoxContainer.new()
	nudges.position = Vector2(18, 152)
	layer.add_child(nudges)
	var nudge_heading := Label.new()
	nudge_heading.text = "Selected piece  ·  step"
	nudges.add_child(nudge_heading)
	adjustment_step = SpinBox.new()
	adjustment_step.min_value = 0.01
	adjustment_step.max_value = 5.0
	adjustment_step.step = 0.01
	adjustment_step.value = 0.05
	adjustment_step.custom_minimum_size.x = 90
	nudges.add_child(adjustment_step)
	_add_action_button(nudges, "X−", func(): _nudge_inspection(Vector3.LEFT * _adjustment_amount()))
	_add_action_button(nudges, "X+", func(): _nudge_inspection(Vector3.RIGHT * _adjustment_amount()))
	_add_action_button(nudges, "Y−", func(): _nudge_inspection(Vector3.DOWN * _adjustment_amount()))
	_add_action_button(nudges, "Y+", func(): _nudge_inspection(Vector3.UP * _adjustment_amount()))
	_add_action_button(nudges, "Z−", func(): _nudge_inspection(Vector3.FORWARD * _adjustment_amount()))
	_add_action_button(nudges, "Z+", func(): _nudge_inspection(Vector3.BACK * _adjustment_amount()))
	_add_action_button(nudges, "Yaw −90", func(): _rotate_inspection(-90.0))
	_add_action_button(nudges, "Yaw +90", func(): _rotate_inspection(90.0))
	_add_action_button(nudges, "Reset", _reset_inspection)
	_add_action_button(nudges, "Copy transform", _copy_inspection_transform)
	transform_label = Label.new()
	transform_label.position = Vector2(18, 192)
	transform_label.text = "Left-click any piece to select it, then adjust its transform."
	layer.add_child(transform_label)

func _set_seed(value: int) -> void:
	generation_seed = value
	_rebuild()

func _frame_camera() -> void:
	if is_instance_valid(orbit):
		# Generated MapData is centered around the world origin. Framing a
		# positive-only box put the actual assembly in the corner of the view.
		orbit.frame(AABB(Vector3(-20, 0, -15), Vector3(40, 8, 30)))
		inspection_target = "whole map"
		_refresh_status_target()

func _focus_component(component_id: StringName, label: String) -> bool:
	if not is_instance_valid(content) or not is_instance_valid(orbit):
		return false
	var modular_root := content.get_node_or_null("ModularEnvironment")
	if modular_root == null:
		return false
	var modules := modular_root.get_children()
	for module in modules:
		if module.get_meta("component_id", &"") != component_id:
			continue
		return _focus_module(module as Node3D, label, modules)
	return false

func _focus_module(module: Node3D, label: String, modules: Array[Node]) -> bool:
	var bounds := AssetPlacement.mesh_bounds(module)
	if bounds.size == Vector3.ZERO:
		return false
	# A joint only makes sense beside the pieces it connects. Include touching
	# module visuals so the inspector frames the seam rather than one mesh.
	var neighborhood := bounds
	for neighbor in modules:
		if neighbor == module:
			continue
		var neighbor_bounds := AssetPlacement.mesh_bounds(neighbor as Node3D)
		if bounds.grow(0.25).intersects(neighbor_bounds):
			neighborhood = neighborhood.merge(neighbor_bounds)
	orbit.frame(neighborhood.grow(1.0))
	_prepare_inspection_module(module)
	inspection_target = label
	_refresh_status_target()
	return true

func _select_next_module() -> void:
	if not is_instance_valid(content) or not is_instance_valid(orbit):
		return
	var modular_root := content.get_node_or_null("ModularEnvironment")
	if modular_root == null:
		return
	var modules: Array[Node] = modular_root.get_children()
	if modules.is_empty():
		return
	var index := modules.find(inspection_module)
	for offset in modules.size():
		var candidate := modules[(index + 1 + offset) % modules.size()] as Node3D
		var component_id: StringName = candidate.get_meta("component_id", &"unknown")
		if _focus_module(candidate, str(component_id), modules):
			return

func _select_module_at_screen(screen_position: Vector2) -> bool:
	if not is_instance_valid(content) or not is_instance_valid(camera):
		return false
	var modular_root := content.get_node_or_null("ModularEnvironment")
	if modular_root == null:
		return false
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var selected: Node3D
	var nearest_distance := INF
	var modules: Array[Node] = modular_root.get_children()
	for candidate_node in modules:
		var candidate := candidate_node as Node3D
		var hit = AssetPlacement.mesh_bounds(candidate).intersects_ray(ray_origin, ray_direction)
		if hit == null:
			continue
		var distance := ray_origin.distance_squared_to(hit as Vector3)
		if distance < nearest_distance:
			nearest_distance = distance
			selected = candidate
	if not is_instance_valid(selected):
		return false
	var component_id: StringName = selected.get_meta("component_id", &"unknown")
	_prepare_inspection_module(selected)
	inspection_target = str(component_id)
	_refresh_status_target()
	return true

func _set_camera_view(azimuth: float, altitude: float) -> void:
	if is_instance_valid(orbit):
		orbit.set_view(azimuth, altitude)

func _add_view_button(parent: Control, label: String, azimuth: float, altitude: float) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(func(): _set_camera_view(azimuth, altitude))
	parent.add_child(button)

func _add_action_button(parent: Control, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	parent.add_child(button)

func _prepare_inspection_module(module: Node3D) -> void:
	if is_instance_valid(inspection_module) and inspection_module != module:
		_set_selection_outline(inspection_module, false)
	inspection_module = module
	if not module.has_meta("inspection_base_position"):
		var pivot := AssetPlacement.mesh_bounds(module).get_center()
		for child in module.get_children():
			if child is Node3D:
				child.position -= pivot
		module.position = pivot
		module.set_meta("inspection_base_position", pivot)
	_set_selection_outline(module, true)
	_update_transform_label()

func _set_selection_outline(module: Node3D, enabled: bool) -> void:
	if not is_instance_valid(module):
		return
	for child in module.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		mesh_instance.material_overlay = selection_outline_material if enabled else null

func _adjustment_amount() -> float:
	return adjustment_step.value if is_instance_valid(adjustment_step) else 0.05

func _nudge_inspection(delta: Vector3) -> void:
	if not is_instance_valid(inspection_module):
		_update_transform_label("Select a piece first.")
		return
	inspection_module.position += delta
	_update_transform_label()

func _rotate_inspection(degrees: float) -> void:
	if not is_instance_valid(inspection_module):
		_update_transform_label("Select a piece first.")
		return
	inspection_module.rotate_y(deg_to_rad(degrees))
	_update_transform_label()

func _reset_inspection() -> void:
	if not is_instance_valid(inspection_module):
		_update_transform_label("Select a piece first.")
		return
	inspection_module.position = inspection_module.get_meta("inspection_base_position", inspection_module.position)
	inspection_module.rotation = Vector3.ZERO
	_update_transform_label()

func _copy_inspection_transform() -> void:
	if not is_instance_valid(inspection_module):
		_update_transform_label("Select a piece first.")
		return
	var text := _inspection_transform_text()
	DisplayServer.clipboard_set(text)
	_update_transform_label("Copied: " + text)

func _inspection_transform_text() -> String:
	if not is_instance_valid(inspection_module):
		return ""
	var base: Vector3 = inspection_module.get_meta("inspection_base_position", inspection_module.position)
	var offset := inspection_module.position - base
	var assets: Array[String] = []
	for child in inspection_module.get_children():
		var path: String = child.get_meta("asset_path", "")
		var asset_name := path.get_file()
		if not asset_name.is_empty() and asset_name not in assets:
			assets.append(asset_name)
	var asset_label := " [%s]" % ", ".join(assets) if not assets.is_empty() else ""
	return "%s%s offset=(%.3f, %.3f, %.3f) yaw=%.1f" % [
		inspection_module.get_meta("component_id", &"unknown"), asset_label, offset.x, offset.y, offset.z,
		rad_to_deg(inspection_module.rotation.y),
	]

func _update_transform_label(prefix := "") -> void:
	if not is_instance_valid(transform_label):
		return
	if not prefix.is_empty():
		transform_label.text = prefix
	elif is_instance_valid(inspection_module):
		transform_label.text = _inspection_transform_text() + "  ·  arrows X/Z · PgUp/PgDn Y · Q/E yaw"
	else:
		transform_label.text = "Left-click any piece to select it, then adjust its transform."

func _update_status(component_count: int, validation_text: String) -> void:
	status.text = "MODULAR INDUSTRIAL PREVIEW  |  seed %d  |  %d components  |  %s\nTarget: %s  |  LMB select · RMB orbit · MMB pan · wheel zoom · F map · C corner · G road · 1/3/7 views" % [
		generation_seed, component_count, validation_text, inspection_target
	]

func _refresh_status_target() -> void:
	if not is_instance_valid(status):
		return
	var lines := status.text.split("\n")
	if lines.size() < 2:
		return
	lines[1] = "Target: %s  |  LMB select · RMB orbit · MMB pan · wheel zoom · F map · C corner · G road · 1/3/7 views" % inspection_target
	status.text = "\n".join(lines)

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
		mesh.surface_add_vertex(Vector3(world_x, 0.08, -half_depth))
		mesh.surface_add_vertex(Vector3(world_x, 0.08, half_depth))
	for z in map_size.y + 1:
		var world_z := -half_depth + float(z) * cell_size
		mesh.surface_add_vertex(Vector3(-half_width, 0.08, world_z))
		mesh.surface_add_vertex(Vector3(half_width, 0.08, world_z))
	mesh.surface_end()
	var overlay := MeshInstance3D.new()
	overlay.name = "TacticalGrid"
	overlay.mesh = mesh
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(overlay)
