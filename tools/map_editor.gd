extends Node3D

const OrbitCamera = preload("res://tools/inspection_orbit_camera.gd")
const AssetPlacement = preload("res://presentation/environment_asset_placement.gd")
const LayoutStore = preload("res://tools/map_editor_layout_store.gd")
const CUSTOM_LAYOUT := &"custom_layout"
const PROCEDURAL_LAYOUTS: Array[StringName] = CoherentEnvironmentAssembler.ENVIRONMENTS
const EDITOR_LAYOUTS: Array[StringName] = [
	CUSTOM_LAYOUT,
	&"industrial_frontage", &"loading_yard", &"road_and_shops", &"vertical_works",
	&"industrial_district", &"commercial_street", &"mixed_service",
]

@export var generation_seed := 2202
@export var layout_preset: StringName = &"industrial_frontage"
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
var preset_picker: OptionButton
var preview_map_size := Vector2i(40, 30)
var show_plan_overlay := true
var custom_layout := EnvironmentModuleLayout.new(CUSTOM_LAYOUT, 0)
var custom_dirty := false
var component_picker: OptionButton
var rotation_picker: OptionButton
var variation_input: SpinBox
var composer_message: Label
var composer_panel: Control
var inspection_shortcuts: Array[Control] = []
var editor_catalog: Dictionary = IndustrialModuleCatalog.create()
var displayed_data: MapData

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].is_valid_int():
		generation_seed = int(args[0])
	if args.size() > 1 and StringName(args[1]) in EDITOR_LAYOUTS:
		layout_preset = StringName(args[1])
	_build_ui()
	_load_custom_layout(false)
	_rebuild()

func _shortcut_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_rebuild()
		elif event.keycode == KEY_F:
			_frame_camera()
		elif event.keycode == KEY_P:
			_set_plan_overlay_visible(not show_plan_overlay)
		elif event.keycode == KEY_C:
			_focus_component(&"factory_wall_corner", "factory corner — inner, scale 2.0")
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
		elif event.keycode == KEY_DELETE and _is_composing():
			_delete_selected_placement()
		elif event.keycode == KEY_S and event.ctrl_pressed and _is_composing():
			_save_custom_layout()
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
		if _is_composing() and _place_selected_component_at_screen(event.position):
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
	var data: MapData
	if layout_preset == CUSTOM_LAYOUT:
		data = _build_custom_map()
	elif layout_preset in PROCEDURAL_LAYOUTS:
		data = FlatMapGenerator.generate_coherent_environment(50, 40, 1.0, generation_seed, layout_preset)
	else:
		data = FlatMapGenerator.generate_modular_environment_sample(40, 30, 1.0, generation_seed, layout_preset)
	displayed_data = data
	preview_map_size = data.map_size
	var ground_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(data.map_size)
	ground_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("303a3f")
	floor_material.roughness = 1.0
	ground_mesh.material_override = floor_material
	content.add_child(ground_mesh)
	_add_grid_overlay(content, data.map_size, 1.0)
	_add_spatial_plan_overlay(content, data)
	GeneratedTerrainPresenter.build(data, content, 1.0)
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	var validation := MapValidator.validate(data, graph, {
		TacticalUnit.Faction.PLAYER: 5,
		TacticalUnit.Faction.ENEMY: 5,
	})
	_update_status(data.environment_modules.size(), "VALID" if validation.is_valid() else validation.describe(), data.environment_layout_plan)
	_update_composer_visibility()
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
	var ui_root := Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var compact_theme := Theme.new()
	compact_theme.default_font_size = 13
	ui_root.theme = compact_theme
	layer.add_child(ui_root)
	status = Label.new()
	status.position = Vector2(12, 12)
	status.add_theme_font_size_override("font_size", 15)
	ui_root.add_child(status)
	var controls := HBoxContainer.new()
	controls.position = Vector2(12, 74)
	ui_root.add_child(controls)
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
	preset_picker = OptionButton.new()
	for preset in EDITOR_LAYOUTS:
		var kind := "Procedural" if preset in PROCEDURAL_LAYOUTS else "Authored"
		preset_picker.add_item("%s — %s" % [kind, String(preset).capitalize()])
		preset_picker.set_item_metadata(preset_picker.item_count - 1, preset)
		if preset == layout_preset:
			preset_picker.select(preset_picker.item_count - 1)
	preset_picker.item_selected.connect(_select_preset)
	controls.add_child(preset_picker)
	var frame_button := Button.new()
	frame_button.text = "Frame map"
	frame_button.pressed.connect(_frame_camera)
	controls.add_child(frame_button)
	var plan_toggle := CheckButton.new()
	plan_toggle.text = "Plan overlay (P)"
	plan_toggle.button_pressed = show_plan_overlay
	plan_toggle.toggled.connect(_set_plan_overlay_visible)
	controls.add_child(plan_toggle)
	var edit_copy := Button.new()
	edit_copy.text = "Edit copy"
	edit_copy.tooltip_text = "Copy the displayed authored or generated modules into the custom composer"
	edit_copy.pressed.connect(_compose_current_layout)
	controls.add_child(edit_copy)
	var corner_button := Button.new()
	corner_button.text = "Inspect corner"
	corner_button.tooltip_text = "Frame the assembled Factory inner-corner joint (C)"
	corner_button.pressed.connect(func(): _focus_component(&"factory_wall_corner", "factory corner — inner, scale 2.0"))
	controls.add_child(corner_button)
	inspection_shortcuts.append(corner_button)
	var road_button := Button.new()
	road_button.text = "Inspect road seam"
	road_button.tooltip_text = "Frame the road and paving connection (G)"
	road_button.pressed.connect(func(): _focus_component(&"road_straight", "road / paving seam"))
	controls.add_child(road_button)
	inspection_shortcuts.append(road_button)
	var views := HBoxContainer.new()
	views.position = Vector2(12, 106)
	ui_root.add_child(views)
	_add_view_button(views, "Front (1)", 0.0, 0.18)
	_add_view_button(views, "Side (3)", PI * 0.5, 0.18)
	_add_view_button(views, "Top (7)", 0.0, 1.50)
	_add_action_button(views, "Next piece (Tab)", _select_next_module)
	var nudges := HBoxContainer.new()
	nudges.position = Vector2(12, 138)
	ui_root.add_child(nudges)
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
	transform_label.position = Vector2(12, 170)
	transform_label.text = "Left-click any piece to select it, then adjust its transform."
	ui_root.add_child(transform_label)
	_build_composer_ui(ui_root)

func _build_composer_ui(layer: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "ComposerPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-338, 210)
	panel.size = Vector2(326, 350)
	layer.add_child(panel)
	composer_panel = panel
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "MAP COMPOSER"
	heading.add_theme_font_size_override("font_size", 16)
	column.add_child(heading)
	var instructions := Label.new()
	instructions.text = "Choose a module, then click an empty grid cell to place it.\nClick a piece to select it; arrows move, Q/E rotate, Delete removes."
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(instructions)
	component_picker = OptionButton.new()
	component_picker.fit_to_longest_item = false
	component_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var component_ids: Array = editor_catalog.keys()
	component_ids.sort_custom(func(a, b):
		var first: EnvironmentModuleDefinition = editor_catalog[a]
		var second: EnvironmentModuleDefinition = editor_catalog[b]
		return "%s/%s" % [first.family, first.component_id] < "%s/%s" % [second.family, second.component_id]
	)
	for component_id in component_ids:
		var definition: EnvironmentModuleDefinition = editor_catalog[component_id]
		component_picker.add_item("%s  [%d×%d]" % [String(component_id).replace("_", " "), definition.size.x, definition.size.y])
		component_picker.set_item_metadata(component_picker.item_count - 1, component_id)
		component_picker.set_item_tooltip(component_picker.item_count - 1, "%s / %s" % [definition.family, component_id])
	column.add_child(component_picker)
	var options := HBoxContainer.new()
	column.add_child(options)
	var rotation_label := Label.new()
	rotation_label.text = "Rotation"
	options.add_child(rotation_label)
	rotation_picker = OptionButton.new()
	for quarter in 4:
		rotation_picker.add_item("%d°" % (quarter * 90))
		rotation_picker.set_item_metadata(quarter, quarter)
	options.add_child(rotation_picker)
	var variation_label := Label.new()
	variation_label.text = "Variation"
	options.add_child(variation_label)
	variation_input = SpinBox.new()
	variation_input.min_value = 0
	variation_input.max_value = 32
	variation_input.step = 1
	variation_input.custom_minimum_size.x = 72
	options.add_child(variation_input)
	var edit_actions := HBoxContainer.new()
	column.add_child(edit_actions)
	_add_action_button(edit_actions, "Rotate selected", func(): _rotate_selected_placement(1))
	_add_action_button(edit_actions, "Delete selected", _delete_selected_placement)
	var file_actions := HBoxContainer.new()
	column.add_child(file_actions)
	_add_action_button(file_actions, "Save (Ctrl+S)", _save_custom_layout)
	_add_action_button(file_actions, "Reload", func(): _load_custom_layout(true))
	_add_action_button(file_actions, "Clear", _clear_custom_layout)
	composer_message = Label.new()
	composer_message.text = "Saved layouts are project-local JSON."
	composer_message.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	composer_message.custom_minimum_size.y = 45
	column.add_child(composer_message)

func _is_composing() -> bool:
	return layout_preset == CUSTOM_LAYOUT

func _update_composer_visibility() -> void:
	if is_instance_valid(composer_panel):
		composer_panel.visible = _is_composing()
	for control in inspection_shortcuts:
		control.visible = not _is_composing()
	if _is_composing():
		_update_composer_message()
	_update_transform_label()

func _build_custom_map() -> MapData:
	var data := FlatMapGenerator.generate(preview_map_size.x, preview_map_size.y, 1.0, generation_seed)
	data.source_kind = "authored_map_editor"
	EnvironmentModuleMapWriter.apply(data, custom_layout, editor_catalog, 1.0)
	data.environment_modules.assign(custom_layout.placements)
	data.environment_module_seed = generation_seed
	data.rebuild_los_index()
	return data

func _compose_current_layout() -> void:
	if not is_instance_valid(displayed_data):
		return
	if _is_composing():
		_set_composer_message("This is already the editable composition.")
		return
	var copied := EnvironmentModuleLayout.new(CUSTOM_LAYOUT, 0)
	for source in displayed_data.environment_modules:
		var placement := EnvironmentModulePlacement.new(source.component_id, source.origin, source.rotation, source.variation, source.elevation)
		if not copied.try_add(editor_catalog.get(placement.component_id), placement, displayed_data.map_size):
			push_error("Could not copy displayed layout into composer: %s" % copied.errors.back())
			return
	custom_layout = copied
	preview_map_size = displayed_data.map_size
	custom_dirty = true
	layout_preset = CUSTOM_LAYOUT
	for item_index in preset_picker.item_count:
		if preset_picker.get_item_metadata(item_index) == CUSTOM_LAYOUT:
			preset_picker.select(item_index)
			break
	_rebuild()
	_set_composer_message("Copied %d displayed modules. The source layout is unchanged." % custom_layout.placements.size())

func _set_seed(value: int) -> void:
	generation_seed = value
	_rebuild()

func _select_preset(index: int) -> void:
	layout_preset = preset_picker.get_item_metadata(index)
	_rebuild()
	if _is_composing():
		_set_composer_message("Composition mode. Click an empty grid cell to place the selected module.")

func _frame_camera() -> void:
	if is_instance_valid(orbit):
		# Generated MapData is centered around the world origin. Framing a
		# positive-only box put the actual assembly in the corner of the view.
		orbit.frame(AABB(Vector3(-preview_map_size.x * 0.5, 0, -preview_map_size.y * 0.5), Vector3(preview_map_size.x, 8, preview_map_size.y)))
		inspection_target = "whole map"
		_refresh_status_target()

func _set_plan_overlay_visible(visible: bool) -> void:
	show_plan_overlay = visible
	if is_instance_valid(content):
		var overlay := content.get_node_or_null("SpatialPlan")
		if overlay != null:
			overlay.visible = visible

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
	if _is_composing():
		_sync_composer_to_selection(selected)
	_refresh_status_target()
	return true

func _place_selected_component_at_screen(screen_position: Vector2) -> bool:
	if not _is_composing() or not is_instance_valid(component_picker):
		return false
	var plane := Plane(Vector3.UP, 0.0)
	var hit = plane.intersects_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))
	if hit == null:
		return false
	var point := hit as Vector3
	var origin := Vector2i(floori(point.x + float(preview_map_size.x) * 0.5), floori(point.z + float(preview_map_size.y) * 0.5))
	var component_id: StringName = component_picker.get_item_metadata(component_picker.selected)
	var rotation := int(rotation_picker.get_item_metadata(rotation_picker.selected))
	var placement := EnvironmentModulePlacement.new(component_id, origin, rotation, int(variation_input.value))
	var candidate := _layout_with_change(-1, placement)
	if candidate == null:
		return true
	custom_layout = candidate
	custom_dirty = true
	_rebuild()
	_set_composer_message("Placed %s at %s." % [component_id, origin])
	return true

func _layout_with_change(replace_index: int, replacement: EnvironmentModulePlacement) -> EnvironmentModuleLayout:
	var candidate := EnvironmentModuleLayout.new(CUSTOM_LAYOUT, 0)
	for index in custom_layout.placements.size() + (1 if replace_index < 0 else 0):
		var placement: EnvironmentModulePlacement
		if replace_index < 0 and index == custom_layout.placements.size():
			placement = replacement
		elif index == replace_index:
			placement = replacement
		else:
			placement = custom_layout.placements[index]
		var copied := EnvironmentModulePlacement.new(placement.component_id, placement.origin, placement.rotation, placement.variation, placement.elevation)
		if not candidate.try_add(editor_catalog.get(copied.component_id), copied, preview_map_size):
			_set_composer_message("Cannot place: %s" % candidate.errors.back(), true)
			return null
	return candidate

func _layout_without(index_to_remove: int) -> EnvironmentModuleLayout:
	var candidate := EnvironmentModuleLayout.new(CUSTOM_LAYOUT, 0)
	for index in custom_layout.placements.size():
		if index == index_to_remove:
			continue
		var placement := custom_layout.placements[index]
		var copied := EnvironmentModulePlacement.new(placement.component_id, placement.origin, placement.rotation, placement.variation, placement.elevation)
		if not candidate.try_add(editor_catalog.get(copied.component_id), copied, preview_map_size):
			_set_composer_message("Could not rebuild composition: %s" % candidate.errors.back(), true)
			return null
	return candidate

func _selected_placement_index() -> int:
	return int(inspection_module.get_meta("placement_index", -1)) if is_instance_valid(inspection_module) else -1

func _move_selected_placement(delta: Vector2i) -> void:
	var index := _selected_placement_index()
	if index < 0 or index >= custom_layout.placements.size():
		_set_composer_message("Select a placed module first.", true)
		return
	var current := custom_layout.placements[index]
	var replacement := EnvironmentModulePlacement.new(current.component_id, current.origin + delta, current.rotation, current.variation, current.elevation)
	var candidate := _layout_with_change(index, replacement)
	if candidate == null:
		return
	custom_layout = candidate
	custom_dirty = true
	_rebuild()
	_select_placement_index(index)

func _rotate_selected_placement(quarter_turns: int) -> void:
	var index := _selected_placement_index()
	if index < 0 or index >= custom_layout.placements.size():
		_set_composer_message("Select a placed module first.", true)
		return
	var current := custom_layout.placements[index]
	var replacement := EnvironmentModulePlacement.new(current.component_id, current.origin, current.rotation + quarter_turns, current.variation, current.elevation)
	var candidate := _layout_with_change(index, replacement)
	if candidate == null:
		return
	custom_layout = candidate
	custom_dirty = true
	_rebuild()
	_select_placement_index(index)

func _delete_selected_placement() -> void:
	var index := _selected_placement_index()
	if index < 0 or index >= custom_layout.placements.size():
		_set_composer_message("Select a placed module first.", true)
		return
	var removed := custom_layout.placements[index].component_id
	var candidate := _layout_without(index)
	if candidate == null:
		return
	custom_layout = candidate
	custom_dirty = true
	_rebuild()
	_set_composer_message("Removed %s." % removed)

func _select_placement_index(index: int) -> void:
	var root := content.get_node_or_null("ModularEnvironment") if is_instance_valid(content) else null
	if root == null:
		return
	for candidate in root.get_children():
		if int(candidate.get_meta("placement_index", -1)) == index:
			_prepare_inspection_module(candidate as Node3D)
			inspection_target = str(candidate.get_meta("component_id", &"unknown"))
			_sync_composer_to_selection(candidate)
			_refresh_status_target()
			return

func _sync_composer_to_selection(module: Node3D) -> void:
	var component_id: StringName = module.get_meta("component_id", &"")
	for item_index in component_picker.item_count:
		if component_picker.get_item_metadata(item_index) == component_id:
			component_picker.select(item_index)
			break
	rotation_picker.select(int(module.get_meta("rotation", 0)))
	variation_input.value = int(module.get_meta("variation", 0))
	_update_composer_message()

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
	if not _is_composing() and not module.has_meta("inspection_base_position"):
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
	if _is_composing():
		if not is_zero_approx(delta.y):
			_set_composer_message("Use modules with authored vertical links for elevation; free Y movement is presentation-only.", true)
			return
		_move_selected_placement(Vector2i(int(signf(delta.x)), int(signf(delta.z))))
		return
	inspection_module.position += delta
	_update_transform_label()

func _rotate_inspection(degrees: float) -> void:
	if not is_instance_valid(inspection_module):
		_update_transform_label("Select a piece first.")
		return
	if _is_composing():
		_rotate_selected_placement(roundi(degrees / 90.0))
		return
	inspection_module.rotate_y(deg_to_rad(degrees))
	_update_transform_label()

func _reset_inspection() -> void:
	if not is_instance_valid(inspection_module):
		_update_transform_label("Select a piece first.")
		return
	if _is_composing():
		_set_composer_message("Composer placements already use snapped grid transforms.")
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
	if _is_composing():
		return "%s origin=%s yaw=%d° variation=%d" % [
			inspection_module.get_meta("component_id", &"unknown"),
			inspection_module.get_meta("origin", Vector2i.ZERO),
			int(inspection_module.get_meta("rotation", 0)) * 90,
			int(inspection_module.get_meta("variation", 0)),
		]
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
		var help := "  ·  arrows move · Q/E rotate · Delete removes" if _is_composing() else "  ·  arrows X/Z · PgUp/PgDn Y · Q/E yaw"
		transform_label.text = _inspection_transform_text() + help
	else:
		transform_label.text = "Choose a module and click an empty grid cell to place it." if _is_composing() else "Left-click any piece to select it, then adjust its transform."

func _update_status(component_count: int, validation_text: String, plan: EnvironmentLayoutPlan = null) -> void:
	var plan_text := "authored layout"
	if plan != null:
		plan_text = "%s · %d road tiles · %d parcels · %d rejected · fallback %s" % [
			String(plan.topology).replace("_", " "), plan.road_cells.size(), plan.parcels.size(),
			plan.rejected_candidates.size(), "yes" if plan.fallback_used else "no",
		]
	var dirty_text := "  |  UNSAVED" if _is_composing() and custom_dirty else ""
	var lmb_help := "select/place" if _is_composing() else "select"
	status.text = "FUSEFIRE MAP EDITOR  |  %s%s  |  seed %d  |  %d components  |  %s\nTarget: %s  |  LMB %s · RMB orbit · MMB pan · wheel zoom · F map · P plan · 1/3/7 views\nPlan: %s" % [
		String(layout_preset).replace("_", " "), dirty_text, generation_seed, component_count, validation_text, inspection_target, lmb_help, plan_text
	]

func _refresh_status_target() -> void:
	if not is_instance_valid(status):
		return
	var lines := status.text.split("\n")
	if lines.size() < 2:
		return
	var lmb_help := "select/place" if _is_composing() else "select"
	lines[1] = "Target: %s  |  LMB %s · RMB orbit · MMB pan · wheel zoom · F map · P plan · 1/3/7 views" % [inspection_target, lmb_help]
	status.text = "\n".join(lines)

func _save_custom_layout() -> void:
	var error := LayoutStore.save(custom_layout, preview_map_size)
	if not error.is_empty():
		_set_composer_message(error, true)
		return
	custom_dirty = false
	_update_status(custom_layout.placements.size(), "VALID")
	_set_composer_message("Saved %d modules to %s." % [custom_layout.placements.size(), LayoutStore.DEFAULT_PATH])

func _load_custom_layout(rebuild_after: bool) -> void:
	var result := LayoutStore.load(editor_catalog)
	var loaded_starter := false
	if not result.ok:
		result = LayoutStore.load(editor_catalog, LayoutStore.STARTER_PATH)
		loaded_starter = result.ok
		if not result.ok:
			if rebuild_after:
				_set_composer_message(result.error, true)
			return
	custom_layout = result.layout
	custom_layout.layout_id = CUSTOM_LAYOUT
	preview_map_size = result.map_size
	custom_dirty = loaded_starter
	if rebuild_after:
		_rebuild()
		if loaded_starter:
			_set_composer_message("Loaded the starter composition. Save to create your custom layout.")
		else:
			_set_composer_message("Reloaded %d saved modules." % custom_layout.placements.size())

func _clear_custom_layout() -> void:
	custom_layout = EnvironmentModuleLayout.new(CUSTOM_LAYOUT, 0)
	custom_dirty = true
	_rebuild()
	_set_composer_message("Cleared the working composition. Save only when this is intentional.")

func _set_composer_message(message: String, is_error := false) -> void:
	if not is_instance_valid(composer_message):
		return
	composer_message.text = message
	composer_message.modulate = Color("ff9f9f") if is_error else Color.WHITE

func _update_composer_message() -> void:
	if not _is_composing():
		return
	var state := "UNSAVED" if custom_dirty else "saved"
	_set_composer_message("%d modules · %s · custom_layout.json" % [custom_layout.placements.size(), state])

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

func _add_spatial_plan_overlay(parent: Node3D, data: MapData) -> void:
	if data.environment_layout_plan == null:
		return
	var plan := data.environment_layout_plan
	var mesh := ImmediateMesh.new()
	var parcel_material := StandardMaterial3D.new()
	parcel_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	parcel_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	parcel_material.albedo_color = Color(1.0, 0.65, 0.16, 0.75)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, parcel_material)
	for parcel in plan.parcels:
		_add_plan_rect(mesh, parcel.bounds, data.map_size, 0.13)
	mesh.surface_end()
	var road_material := StandardMaterial3D.new()
	road_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	road_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	road_material.albedo_color = Color(0.15, 0.92, 1.0, 0.9)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, road_material)
	for road_cell in plan.road_cells:
		_add_plan_rect(mesh, Rect2i(road_cell * plan.macro_size, Vector2i.ONE * plan.macro_size), data.map_size, 0.15)
	mesh.surface_end()
	var overlay := MeshInstance3D.new()
	overlay.name = "SpatialPlan"
	overlay.mesh = mesh
	overlay.visible = show_plan_overlay
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(overlay)

func _add_plan_rect(mesh: ImmediateMesh, bounds: Rect2i, map_size: Vector2i, height: float) -> void:
	var half := Vector2(map_size) * 0.5
	var minimum := Vector2(bounds.position) - half
	var maximum := Vector2(bounds.end) - half
	var points := [
		Vector3(minimum.x, height, minimum.y), Vector3(maximum.x, height, minimum.y),
		Vector3(maximum.x, height, maximum.y), Vector3(minimum.x, height, maximum.y),
	]
	for index in 4:
		mesh.surface_add_vertex(points[index])
		mesh.surface_add_vertex(points[(index + 1) % 4])
