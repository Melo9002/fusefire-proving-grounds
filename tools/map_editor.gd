extends Node3D

const OrbitCamera = preload("res://tools/inspection_orbit_camera.gd")
const AssetPlacement = preload("res://presentation/environment_asset_placement.gd")
const LayoutStore = preload("res://tools/map_editor_layout_store.gd")
const BATTLE_SCENE := preload("res://levels/prototype_map/prototype_map.tscn")
const DebugDraw = preload("res://tools/diagnostics/fusefire_debug_draw_3d.gd")
const ReservationLedger = preload("res://systems/generation/environment_spatial_reservation_ledger.gd")
const PLOT_LAYOUT := &"plot_authoring"
const CHUNK_LAYOUT := &"chunk_authoring"
const POPULATION_LAYOUT := &"fixed_population"
const CUSTOM_LAYOUT := &"custom_layout"
const ASSEMBLY_VIEW_COMPLETE := &"complete"
const ASSEMBLY_VIEW_SHELL := &"shell"
const ASSEMBLY_VIEW_DECORATION := &"decoration"
const INSPECTION_CONTROLS_TOP := 92.0
const INSPECTION_ROW_SPACING := 32.0
const PROCEDURAL_LAYOUTS: Array[StringName] = CoherentEnvironmentAssembler.ENVIRONMENTS
const NORMAL_LAYOUTS: Array[StringName] = [
	CHUNK_LAYOUT, PLOT_LAYOUT, CUSTOM_LAYOUT, POPULATION_LAYOUT,
	&"industrial_district", &"commercial_street", &"mixed_service",
]
const ENGINEERING_LAYOUTS: Array[StringName] = [
	&"asset_first_frontage", &"industrial_frontage", &"loading_yard", &"road_and_shops", &"vertical_works", &"building_gallery",
]
const EDITOR_LAYOUTS: Array[StringName] = NORMAL_LAYOUTS + ENGINEERING_LAYOUTS
const ENGINEERING_ONLY_COMPONENTS: Array[StringName] = [
	&"factory_wall_straight", &"factory_wall_corner", &"factory_doorway_wide", &"factory_window_wall",
	&"factory_shop_front", &"factory_interior_floor", &"industrial_building_shell", &"complete_service_building",
]

@export var generation_seed := 17
@export var layout_preset: StringName = &"industrial_district"
@export var custom_layout_path := LayoutStore.DEFAULT_PATH
@export var starter_layout_path := LayoutStore.STARTER_PATH
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
var engineering_fixtures_toggle: CheckButton
var spatial_contract_toggle: CheckButton
var preview_map_size := Vector2i(40, 30)
var show_plan_overlay := true
var show_spatial_contracts := false
var custom_layout := EnvironmentModuleLayout.new(CUSTOM_LAYOUT, 0)
var custom_document: BattlefieldLayoutDocument
var custom_build_errors: Array[Dictionary] = []
var custom_dirty := false
var component_picker: OptionButton
var rotation_picker: OptionButton
var variation_input: SpinBox
var composer_message: Label
var composer_panel: Control
var inspection_shortcuts: Array[Control] = []
var engineering_shortcuts: Array[Control] = []
var editor_catalog: Dictionary = IndustrialModuleCatalog.create()
var preview_placement: EnvironmentModulePlacement
var preview_source_id := ""
var preview_is_duplicate := false
var preview_obstacles: EnvironmentModuleLayout
var preview_visual: Node3D
var preview_actions: Control
var preview_definition: EnvironmentModuleDefinition
var preview_visuals: Array[Dictionary] = []
var pending_resolution: EnvironmentResolutionContext
var pending_compilation: Dictionary = {}
var displayed_data: MapData
var assembly_view: StringName = ASSEMBLY_VIEW_COMPLETE
var show_engineering_fixtures := false
var population_save_directory := "res://tools/map_editor/layouts"
var pending_population: Dictionary = {}
var population_panel: VBoxContainer
var population_message: Label
var plot_authoring: PlotAuthoringController
var chunk_authoring: ChunkAuthoringController
var legacy_edit_controls: Array[Control] = []

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].is_valid_int():
		generation_seed = int(args[0])
	if args.size() > 1 and StringName(args[1]) in EDITOR_LAYOUTS:
		layout_preset = StringName(args[1])
		show_engineering_fixtures = layout_preset in ENGINEERING_LAYOUTS
	_build_ui()
	_load_custom_layout(false)
	_rebuild()

func _process(_delta: float) -> void:
	if layout_preset == PLOT_LAYOUT: return
	if layout_preset == CHUNK_LAYOUT and chunk_authoring != null:
		chunk_authoring.draw()
		return
	if show_spatial_contracts:
		_draw_selected_spatial_contracts()

func _shortcut_input(event: InputEvent) -> void:
	if layout_preset == PLOT_LAYOUT:
		plot_authoring.shortcut(event)
		return
	if chunk_authoring != null and chunk_authoring.publication != null and chunk_authoring.publication.busy: return
	if layout_preset == CHUNK_LAYOUT:
		chunk_authoring.shortcut(event)
		return
	if preview_placement != null and _preview_shortcut(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_rebuild()
		elif event.keycode == KEY_F:
			_frame_camera()
		elif event.keycode == KEY_P:
			_set_plan_overlay_visible(not show_plan_overlay)
		elif event.keycode == KEY_D:
			_set_spatial_contracts_visible(not show_spatial_contracts)
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
	if layout_preset == PLOT_LAYOUT:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			plot_authoring.click(event.position)
		elif is_instance_valid(orbit): orbit.handle_mouse(event)
		return
	if chunk_authoring != null and chunk_authoring.publication != null and chunk_authoring.publication.busy: return
	if layout_preset == CHUNK_LAYOUT:
		if event is InputEventMouseMotion and event.button_mask == 0:
			chunk_authoring.move_pending(event.position)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			chunk_authoring.click(event.position)
		elif is_instance_valid(orbit): orbit.handle_mouse(event)
		return
	if preview_placement != null:
		if event is InputEventMouseMotion and event.button_mask == 0:
			_move_preview_at_screen(event.position)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_move_preview_at_screen(event.position)
			_confirm_placement_preview()
			get_viewport().set_input_as_handled()
			return
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
	if chunk_authoring != null: chunk_authoring.cancel_pending()
	_cancel_placement_preview(false)
	_update_composer_visibility()
	if layout_preset == PLOT_LAYOUT:
		plot_authoring.changed()
		_frame_camera()
		return
	if layout_preset == CHUNK_LAYOUT:
		displayed_data = null
		chunk_authoring.rebuild()
		_frame_camera()
		chunk_authoring.update_status()
		return
	if content:
		content.free()
	inspection_module = null
	inspection_target = "whole map"
	assembly_view = ASSEMBLY_VIEW_COMPLETE
	content = Node3D.new()
	content.name = "PreviewContent"
	add_child(content)
	var data: MapData
	if layout_preset == CUSTOM_LAYOUT:
		data = _build_custom_map()
	elif layout_preset == POPULATION_LAYOUT:
		var populated := pending_population if not pending_population.is_empty() else FixedEnvironmentPopulation.build(generation_seed)
		pending_population = {}
		if not populated.ok:
			displayed_data = null
			population_message.text = "Population rejected: " + str(populated.errors)
			status.text = "Fixed environment population failed; no playable snapshot."
			return
		data = populated.data
		population_message.text = "Fixed industrial base · seed %d\n8 additions in declared yards. Street and mission access stay protected.\nSave keeps the exact accepted choices." % generation_seed
	elif layout_preset in PROCEDURAL_LAYOUTS:
		var context := EnvironmentResolutionContext.new()
		data = FlatMapGenerator.generate_coherent_environment(60, 50, 1.0, generation_seed, layout_preset, 5, context)
		data.battlefield_layout_document = BattlefieldLayoutDocument.from_generated(data, "", context)
	else:
		data = FlatMapGenerator.generate_modular_environment_sample(40, 30, 1.0, generation_seed, layout_preset)
		var legacy_layout := EnvironmentModuleLayout.new(layout_preset, generation_seed)
		legacy_layout.placements.assign(data.environment_modules)
		data.battlefield_layout_document = BattlefieldLayoutDocument.from_authored(legacy_layout, data.map_size, &"mixed_service", "legacy_%s" % layout_preset, data)
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
	var validation_text := "TACTICAL VALID" if validation.is_valid() else "TACTICAL %s" % validation.describe()
	if _is_composing() and not custom_build_errors.is_empty(): validation_text = "DOCUMENT INVALID: %s" % custom_build_errors[0].message
	_update_status(data.environment_modules.size(), validation_text, data.environment_layout_plan)
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
	ui_root.name = "MapEditorUI"
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The root only positions the editor widgets.  If it keeps Control's default
	# STOP filter, its otherwise empty full-screen rectangle swallows mouse
	# events before _unhandled_input() can orbit the camera or ray-pick modules.
	# Interactive children retain their own STOP filters and continue to receive
	# clicks normally.
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var compact_theme := Theme.new()
	compact_theme.default_font_size = 13
	ui_root.theme = compact_theme
	layer.add_child(ui_root)
	status = Label.new()
	status.position = Vector2(12, 12)
	status.add_theme_font_size_override("font_size", 15)
	ui_root.add_child(status)
	var controls := HBoxContainer.new()
	controls.position = Vector2(12, INSPECTION_CONTROLS_TOP)
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
	_populate_preset_picker()
	preset_picker.item_selected.connect(_select_preset)
	controls.add_child(preset_picker)
	engineering_fixtures_toggle = CheckButton.new()
	engineering_fixtures_toggle.text = "Engineering fixtures"
	engineering_fixtures_toggle.tooltip_text = "Show preserved component demonstrations and regression maps"
	engineering_fixtures_toggle.button_pressed = show_engineering_fixtures
	engineering_fixtures_toggle.toggled.connect(_set_engineering_fixtures_visible)
	controls.add_child(engineering_fixtures_toggle)
	var frame_button := Button.new()
	frame_button.text = "Frame map"
	frame_button.pressed.connect(_frame_camera)
	controls.add_child(frame_button)
	var plan_toggle := CheckButton.new()
	plan_toggle.text = "Plan overlay (P)"
	plan_toggle.button_pressed = show_plan_overlay
	plan_toggle.toggled.connect(_set_plan_overlay_visible)
	controls.add_child(plan_toggle)
	spatial_contract_toggle = CheckButton.new()
	spatial_contract_toggle.text = "Spatial contracts (D)"
	spatial_contract_toggle.button_pressed = show_spatial_contracts
	spatial_contract_toggle.tooltip_text = "Selected module: green footprint, amber clearance, magenta visual envelope, cyan connection sockets"
	spatial_contract_toggle.toggled.connect(_set_spatial_contracts_visible)
	controls.add_child(spatial_contract_toggle)
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
	engineering_shortcuts.append(corner_button)
	var road_button := Button.new()
	road_button.text = "Inspect road seam"
	road_button.tooltip_text = "Frame the road and paving connection (G)"
	road_button.pressed.connect(func(): _focus_component(&"road_straight", "road / paving seam"))
	controls.add_child(road_button)
	inspection_shortcuts.append(road_button)
	var views := HBoxContainer.new()
	views.position = Vector2(12, INSPECTION_CONTROLS_TOP + INSPECTION_ROW_SPACING)
	ui_root.add_child(views)
	_add_view_button(views, "Front (1)", 0.0, 0.18)
	_add_view_button(views, "Side (3)", PI * 0.5, 0.18)
	_add_view_button(views, "Top (7)", 0.0, 1.50)
	_add_action_button(views, "Next piece (Tab)", _select_next_module)
	_add_action_button(views, "Complete", func(): _set_assembly_view(ASSEMBLY_VIEW_COMPLETE))
	_add_action_button(views, "Shell", func(): _set_assembly_view(ASSEMBLY_VIEW_SHELL))
	_add_action_button(views, "Decor", func(): _set_assembly_view(ASSEMBLY_VIEW_DECORATION))
	var nudges := HBoxContainer.new()
	nudges.position = Vector2(12, INSPECTION_CONTROLS_TOP + INSPECTION_ROW_SPACING * 2.0)
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
	transform_label.position = Vector2(12, INSPECTION_CONTROLS_TOP + INSPECTION_ROW_SPACING * 3.0)
	transform_label.text = "Left-click any piece to select it, then adjust its transform."
	ui_root.add_child(transform_label)
	_build_composer_ui(ui_root)
	legacy_edit_controls.assign([nudges, transform_label, previous, seed_input, next, regenerate, plan_toggle, spatial_contract_toggle, edit_copy])
	for control in views.get_children().slice(3): legacy_edit_controls.append(control)
	chunk_authoring = ChunkAuthoringController.new(self)
	chunk_authoring.build_ui(ui_root)
	plot_authoring = PlotAuthoringController.new(self)
	plot_authoring.build_ui(ui_root)
	population_panel = VBoxContainer.new()
	ui_root.add_child(population_panel)
	population_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	population_panel.offset_left = -340
	population_panel.offset_right = -12
	population_panel.offset_top = 220
	population_message = Label.new()
	population_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	population_panel.add_child(population_message)
	_add_action_button(population_panel, "Save populated battlefield", _save_population)
	_add_action_button(population_panel, "Reload saved seed", _reload_population)
	_add_action_button(population_panel, "Play — Eliminate", func(): _play_population(MissionObjectiveDefinition.Kind.ELIMINATE))
	_add_action_button(population_panel, "Play — Terminal", func(): _play_population(MissionObjectiveDefinition.Kind.INTERACT_TERMINAL))
	population_panel.hide()

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
	_populate_component_picker()
	column.add_child(component_picker)
	var fixture_note := Label.new()
	fixture_note.text = "Reviewed assets and authored assemblies. Enable Engineering fixtures for legacy fragments."
	fixture_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(fixture_note)
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
	var instance_actions := HBoxContainer.new()
	column.add_child(instance_actions)
	_add_action_button(instance_actions, "Duplicate selected", _duplicate_selected_placement)
	_add_action_button(instance_actions, "Apply variant", _change_selected_variation)
	var file_actions := HBoxContainer.new()
	column.add_child(file_actions)
	_add_action_button(file_actions, "Save (Ctrl+S)", _save_custom_layout)
	_add_action_button(file_actions, "Reload", func(): _load_custom_layout(true))
	_add_action_button(file_actions, "Clear", _clear_custom_layout)
	preview_actions = HBoxContainer.new()
	column.add_child(preview_actions)
	_add_action_button(preview_actions, "Confirm (Enter)", _confirm_placement_preview)
	_add_action_button(preview_actions, "Cancel (Esc)", _cancel_placement_preview)
	preview_actions.visible = false
	var play_actions := HBoxContainer.new()
	column.add_child(play_actions)
	_add_action_button(play_actions, "Play edited battlefield", _play_custom_layout)
	composer_message = Label.new()
	composer_message.text = "Saved layouts are project-local JSON."
	composer_message.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	composer_message.custom_minimum_size.y = 45
	column.add_child(composer_message)

func _populate_preset_picker() -> void:
	if not is_instance_valid(preset_picker):
		return
	preset_picker.clear()
	for preset in NORMAL_LAYOUTS:
		var kind := "Author" if preset in [CHUNK_LAYOUT, PLOT_LAYOUT] else ("Editable" if preset == CUSTOM_LAYOUT else "Environment")
		preset_picker.add_item("%s — %s" % [kind, String(preset).capitalize()])
		preset_picker.set_item_metadata(preset_picker.item_count - 1, preset)
	if show_engineering_fixtures:
		for preset in ENGINEERING_LAYOUTS:
			preset_picker.add_item("Fixture — %s" % String(preset).capitalize())
			preset_picker.set_item_metadata(preset_picker.item_count - 1, preset)
	for item_index in preset_picker.item_count:
		if preset_picker.get_item_metadata(item_index) == layout_preset:
			preset_picker.select(item_index)
			return
	preset_picker.select(0)

func _populate_component_picker() -> void:
	if not is_instance_valid(component_picker):
		return
	var selected_id: StringName = &""
	if component_picker.item_count > 0 and component_picker.selected >= 0:
		selected_id = component_picker.get_item_metadata(component_picker.selected)
	component_picker.clear()
	var component_ids: Array = editor_catalog.keys()
	component_ids.sort_custom(func(a, b):
		var first: EnvironmentModuleDefinition = editor_catalog[a]
		var second: EnvironmentModuleDefinition = editor_catalog[b]
		return "%s/%s" % [first.family, first.component_id] < "%s/%s" % [second.family, second.component_id]
	)
	for component_id in component_ids:
		if not show_engineering_fixtures and component_id in ENGINEERING_ONLY_COMPONENTS:
			continue
		var definition: EnvironmentModuleDefinition = editor_catalog[component_id]
		component_picker.add_item("%s  [%d×%d]" % [String(component_id).replace("_", " "), definition.size.x, definition.size.y])
		component_picker.set_item_metadata(component_picker.item_count - 1, component_id)
		component_picker.set_item_tooltip(component_picker.item_count - 1, "%s / %s" % [definition.family, component_id])
		if component_id == selected_id:
			component_picker.select(component_picker.item_count - 1)

func _is_composing() -> bool:
	return layout_preset == CUSTOM_LAYOUT

func _update_composer_visibility() -> void:
	if is_instance_valid(population_panel): population_panel.visible = layout_preset == POPULATION_LAYOUT
	var plot_mode := layout_preset == PLOT_LAYOUT
	if plot_authoring != null: plot_authoring.panel.visible = plot_mode
	var chunk_mode := layout_preset == CHUNK_LAYOUT
	if chunk_authoring != null: chunk_authoring.panel.visible = chunk_mode
	for control in legacy_edit_controls: control.visible = not chunk_mode and not plot_mode
	if is_instance_valid(composer_panel):
		composer_panel.visible = _is_composing()
	for control in inspection_shortcuts:
		control.visible = not _is_composing() and not chunk_mode and not plot_mode
	for control in engineering_shortcuts:
		control.visible = show_engineering_fixtures and not _is_composing() and not chunk_mode and not plot_mode
	if _is_composing():
		_update_composer_message()
	_update_transform_label()

func _build_custom_map() -> MapData:
	if not pending_compilation.is_empty():
		var accepted := pending_compilation
		pending_compilation = {}
		if accepted.document.signature() == custom_document.signature():
			custom_build_errors.clear()
			return accepted.data
	var context := pending_resolution if pending_resolution != null else EnvironmentResolutionContext.new()
	pending_resolution = null
	if custom_document == null:
		custom_document = BattlefieldLayoutDocument.from_authored(custom_layout, preview_map_size, &"mixed_service", "legacy_custom_layout", null, context)
	var result := BattlefieldLayoutDocumentCompiler.compile(custom_document, 1.0, 5, context)
	custom_build_errors.assign(result.errors)
	if result.document != null: custom_document = result.document
	if result.data != null: return result.data
	# Invalid document shape cannot be compiled. Return a visible empty tactical
	# canvas while the structured error remains in the editor status.
	return FlatMapGenerator.generate(preview_map_size.x, preview_map_size.y, 1.0, 0)

func _compose_current_layout() -> void:
	if not is_instance_valid(displayed_data):
		return
	if _is_composing():
		_set_composer_message("This is already the editable composition.")
		return
	var source_document := displayed_data.battlefield_layout_document
	if source_document == null:
		var source_layout := EnvironmentModuleLayout.new(StringName(displayed_data.source_kind), displayed_data.environment_module_seed)
		source_layout.placements.assign(displayed_data.environment_modules)
		source_document = BattlefieldLayoutDocument.from_authored(source_layout, displayed_data.map_size, &"mixed_service", "legacy_editor_copy", displayed_data)
	custom_document = source_document.editable_copy()
	var copied := custom_document.to_module_layout(editor_catalog)
	if not copied.errors.is_empty():
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

func _set_engineering_fixtures_visible(show_enabled: bool) -> void:
	show_engineering_fixtures = show_enabled
	if not show_enabled and layout_preset in ENGINEERING_LAYOUTS:
		layout_preset = &"industrial_district"
	_populate_preset_picker()
	_populate_component_picker()
	if is_instance_valid(engineering_fixtures_toggle):
		engineering_fixtures_toggle.set_pressed_no_signal(show_enabled)
	_rebuild()

func _frame_camera() -> void:
	if is_instance_valid(orbit):
		# Generated MapData is centered around the world origin. Framing a
		# positive-only box put the actual assembly in the corner of the view.
		orbit.frame(AABB(Vector3(-preview_map_size.x * 0.5, 0, -preview_map_size.y * 0.5), Vector3(preview_map_size.x, 8, preview_map_size.y)))
		inspection_target = "whole map"
		_refresh_status_target()

func _set_plan_overlay_visible(show_enabled: bool) -> void:
	show_plan_overlay = show_enabled
	if is_instance_valid(content):
		var overlay := content.get_node_or_null("SpatialPlan")
		if overlay != null:
			overlay.visible = show_enabled

func _set_spatial_contracts_visible(show_enabled: bool) -> void:
	show_spatial_contracts = show_enabled
	if is_instance_valid(spatial_contract_toggle):
		spatial_contract_toggle.set_pressed_no_signal(show_enabled)
	if not show_enabled:
		DebugDraw.clear_all()
	elif not DebugDraw.is_available():
		_update_transform_label("Debug Draw 3D is unavailable. Run a project import and verify the vendored native library.")
	elif not is_instance_valid(inspection_module):
		_update_transform_label("Spatial contracts enabled. Select a module to inspect it.")

func _draw_selected_spatial_contracts() -> Dictionary:
	var summary := {"available": DebugDraw.is_available(), "footprint": 0, "clearance": 0, "envelope": 0, "sockets": 0}
	if not summary.available or not is_instance_valid(displayed_data) or not is_instance_valid(inspection_module):
		return summary
	var placement_index := int(inspection_module.get_meta("placement_index", -1))
	if placement_index < 0 or placement_index >= displayed_data.environment_modules.size():
		return summary
	var placement: EnvironmentModulePlacement = displayed_data.environment_modules[placement_index]
	var definition: EnvironmentModuleDefinition = editor_catalog.get(placement.component_id)
	if definition == null:
		return summary
	var layout := EnvironmentModuleLayout.new(&"map_editor_diagnostics", generation_seed)
	var _scope := DebugDraw.begin_scope(get_viewport(), true, 0.025)
	for cell in layout.world_cells(definition, placement):
		var center := _diagnostic_cell_center(cell, placement.elevation)
		if DebugDraw.draw_aabb(AABB(center - Vector3(0.46, 0.04, 0.46), Vector3(0.92, 0.08, 0.92)), Color(0.25, 1.0, 0.4, 0.92)):
			summary.footprint += 1
	for cell in layout.world_clearance_cells(definition, placement):
		var center := _diagnostic_cell_center(cell, placement.elevation) + Vector3.UP * 0.07
		if DebugDraw.draw_aabb(AABB(center - Vector3(0.43, 0.025, 0.43), Vector3(0.86, 0.05, 0.86)), Color(1.0, 0.64, 0.12, 0.9)):
			summary.clearance += 1
	var envelope := layout.world_visual_envelope(definition, placement)
	if envelope.size != Vector3.ZERO:
		var origin_cell := displayed_data.get_cell(Vector3i(0, 0, 0))
		if origin_cell != null:
			envelope.position += origin_cell.world_position
			if DebugDraw.draw_aabb(envelope, Color(1.0, 0.18, 0.82, 0.96)):
				summary.envelope = 1
	for connection in layout.world_connections(definition, placement):
		var cell: Vector2i = connection.cell
		var direction: Vector2i = connection.direction
		var start := _diagnostic_cell_center(cell, int(connection.elevation)) + Vector3.UP * 0.28
		var finish := start + Vector3(direction.x, 0.0, direction.y) * 0.8
		if DebugDraw.draw_arrow(start, finish, Color(0.15, 0.92, 1.0, 1.0)):
			summary.sockets += 1
	return summary

func _diagnostic_cell_center(cell: Vector2i, elevation: int) -> Vector3:
	var map_cell := displayed_data.get_cell(Vector3i(cell.x, elevation, cell.y))
	if map_cell != null:
		return map_cell.world_position + Vector3.UP * 0.08
	var origin_cell := displayed_data.get_cell(Vector3i(0, 0, 0))
	var origin := origin_cell.world_position if origin_cell != null else Vector3.ZERO
	return origin + Vector3(cell.x, elevation, cell.y) + Vector3.UP * 0.08

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
	var quarter_turns := int(rotation_picker.get_item_metadata(rotation_picker.selected))
	var placement := EnvironmentModulePlacement.new(component_id, origin, quarter_turns, int(variation_input.value))
	var candidate := _layout_with_change(-1, placement)
	if candidate == null:
		return true
	if not _accept_custom_layout(candidate): return true
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
		var copied := placement.copy()
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
		var copied := placement.copy()
		if not candidate.try_add(editor_catalog.get(copied.component_id), copied, preview_map_size):
			_set_composer_message("Could not rebuild composition: %s" % candidate.errors.back(), true)
			return null
	return candidate

func _selected_placement_index() -> int:
	if not is_instance_valid(inspection_module): return -1
	var id := str(inspection_module.get_meta("placement_id", ""))
	for index in custom_layout.placements.size():
		if custom_layout.placements[index].placement_id == id and not id.is_empty(): return index
	return -1

func _move_selected_placement(delta: Vector2i) -> void:
	if preview_placement == null and not _begin_placement_preview(false): return
	preview_placement.origin += delta
	_refresh_placement_preview()

func _rotate_selected_placement(quarter_turns: int) -> void:
	if preview_placement == null and not _begin_placement_preview(false): return
	preview_placement.rotation = posmod(preview_placement.rotation + quarter_turns, 4)
	_refresh_placement_preview()

func _delete_selected_placement() -> void:
	if preview_placement != null:
		_set_composer_message("Confirm or cancel the preview first.", true)
		return
	var index := _selected_placement_index()
	if index < 0 or index >= custom_layout.placements.size():
		_set_composer_message("Select a placed module first.", true)
		return
	var removed := custom_layout.placements[index].component_id
	var candidate := _layout_without(index)
	if candidate == null:
		return
	if not _accept_custom_layout(candidate): return
	_rebuild()
	_set_composer_message("Removed %s." % removed)

func _change_selected_variation() -> void:
	if preview_placement != null:
		_set_composer_message("Confirm or cancel the preview first.", true)
		return
	var index := _selected_placement_index()
	if index < 0:
		_set_composer_message("Select a placed module first.", true)
		return
	var replacement := custom_layout.placements[index].copy()
	replacement.variation = int(variation_input.value)
	var candidate := _layout_with_change(index, replacement)
	if candidate == null or not _accept_custom_layout(candidate): return
	_rebuild()
	_select_placement_index(index)

func _duplicate_selected_placement() -> void:
	if preview_placement != null:
		_set_composer_message("Confirm or cancel the current preview first.", true)
		return
	_begin_placement_preview(true)

func _begin_placement_preview(is_duplicate: bool) -> bool:
	var index := _selected_placement_index()
	if index < 0:
		_set_composer_message("Select a placed module first.", true)
		return false
	var source := custom_layout.placements[index]
	preview_source_id = source.placement_id
	preview_is_duplicate = is_duplicate
	preview_placement = source.copy()
	if is_duplicate: preview_placement.placement_id = ""
	preview_definition = editor_catalog[source.component_id]
	preview_visuals.clear()
	if displayed_data != null:
		for record in displayed_data.resolved_environment_modules:
			if record.placement.placement_id == source.placement_id:
				preview_definition = record.definition
				preview_visuals.assign(record.visuals)
				break
	preview_obstacles = EnvironmentModuleLayout.new(&"placement_preview")
	for placement in custom_layout.placements:
		if not is_duplicate and placement.placement_id == preview_source_id: continue
		if not preview_obstacles.try_add(editor_catalog[placement.component_id], placement.copy(), preview_map_size):
			_cancel_placement_preview(false)
			_set_composer_message("Existing composition needs repair before placement.", true)
			return false
	if not is_duplicate and is_instance_valid(inspection_module): inspection_module.visible = false
	if is_instance_valid(preview_actions): preview_actions.show()
	_refresh_placement_preview()
	return true

func _placement_preview_error() -> String:
	if preview_placement == null: return "No active preview."
	var error := preview_obstacles.placement_error(preview_definition, preview_placement, preview_map_size)
	if not error.is_empty(): return error
	var candidate := EnvironmentModuleLayout.new(&"preview_support")
	candidate.placements.assign(preview_obstacles.placements)
	candidate.placements.append(preview_placement)
	var support := EnvironmentModuleLayout.Spatial.source_support_errors(candidate, editor_catalog, preview_map_size)
	return str(support[0].message) if not support.is_empty() else ""

func _refresh_placement_preview() -> void:
	var error := _placement_preview_error()
	_set_composer_message(("Blocked: %s. Move preview; Esc cancels." % error) if not error.is_empty() else "Preview: click / Enter to validate and place; Q/E rotates; Esc cancels.", not error.is_empty())
	if is_instance_valid(preview_visual): preview_visual.free()
	if displayed_data == null or not is_inside_tree(): return
	preview_visual = Node3D.new()
	preview_visual.name = "PlacementPreview"
	add_child(preview_visual)
	for visual in preview_visuals:
		ModularEnvironmentPresenter._add_visual(displayed_data, preview_visual, preview_definition, preview_placement, visual, 1.0)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 1.0, 0.45, 0.5) if error.is_empty() else Color(1.0, 0.15, 0.1, 0.5)
	for node in preview_visual.find_children("*", "MeshInstance3D", true, false):
		node.material_override = material
		node.material_overlay = null
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _move_preview_at_screen(screen_position: Vector2) -> void:
	if not is_instance_valid(camera): return
	var plane := Plane(Vector3.UP, float(preview_placement.elevation))
	var hit = plane.intersects_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))
	if hit == null: return
	var at := Vector2i(floori(hit.x + float(preview_map_size.x) * 0.5), floori(hit.z + float(preview_map_size.y) * 0.5))
	if at == preview_placement.origin: return
	preview_placement.origin = at
	_refresh_placement_preview()

func _preview_shortcut(event: InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo: return false
	match event.keycode:
		KEY_ESCAPE: _cancel_placement_preview()
		KEY_ENTER, KEY_KP_ENTER: _confirm_placement_preview()
		KEY_Q: _rotate_selected_placement(-1)
		KEY_E: _rotate_selected_placement(1)
		KEY_LEFT: _move_selected_placement(Vector2i.LEFT)
		KEY_RIGHT: _move_selected_placement(Vector2i.RIGHT)
		KEY_UP: _move_selected_placement(Vector2i.UP)
		KEY_DOWN: _move_selected_placement(Vector2i.DOWN)
		_: return false
	return true

func _cancel_placement_preview(show_message := true) -> void:
	if preview_placement == null: return
	if is_instance_valid(inspection_module): inspection_module.visible = true
	if is_instance_valid(preview_visual): preview_visual.free()
	preview_visual = null
	preview_placement = null
	preview_source_id = ""
	preview_obstacles = null
	preview_visuals.clear()
	if is_instance_valid(preview_actions): preview_actions.hide()
	if show_message: _set_composer_message("Preview cancelled; composition unchanged.")

func _confirm_placement_preview() -> bool:
	if preview_placement == null: return false
	var error := _placement_preview_error()
	if not error.is_empty():
		_set_composer_message("Cannot confirm: " + error, true)
		return false
	var source_index := -1
	for index in custom_layout.placements.size():
		if custom_layout.placements[index].placement_id == preview_source_id: source_index = index
	if source_index < 0:
		_set_composer_message("Source placement no longer exists; cancel this preview.", true)
		return false
	var context := EnvironmentResolutionContext.new()
	var candidate: BattlefieldLayoutDocument
	var selected_id := preview_source_id
	if preview_is_duplicate:
		var source := custom_layout.placements[source_index]
		var ids: Array[String] = [preview_source_id]
		var copied := custom_document.duplicate_placements(ids, preview_placement.origin - source.origin, context.catalog, context, preview_placement.rotation - source.rotation)
		if not copied.ok:
			_set_composer_message("Cannot confirm: " + str(copied.error), true)
			return false
		candidate = copied.document
		selected_id = copied.id_map[preview_source_id]
	else:
		var layout := _layout_with_change(source_index, preview_placement)
		if layout == null: return false
		candidate = BattlefieldLayoutDocument.from_dictionary(custom_document.to_dictionary())
		var failures := candidate.apply_edited_layout(layout, context)
		if not failures.is_empty():
			_set_composer_message("Cannot confirm: " + str(failures[0].message), true)
			return false
	var compiled := BattlefieldLayoutDocumentCompiler.compile(candidate, 1.0, 5, context)
	if not compiled.ok:
		_set_composer_message("Cannot confirm: " + str(compiled.errors[0].message), true)
		return false
	_cancel_placement_preview(false)
	custom_document = compiled.document
	custom_layout = custom_document.to_module_layout(context.catalog)
	custom_dirty = true
	pending_resolution = null
	pending_compilation = compiled
	_rebuild()
	for index in custom_layout.placements.size():
		if custom_layout.placements[index].placement_id == selected_id: _select_placement_index(index)
	_set_composer_message("Placement confirmed. Save to keep this composition.")
	return true

func _select_placement_index(index: int) -> void:
	var root := content.get_node_or_null("ModularEnvironment") if is_instance_valid(content) else null
	if root == null:
		return
	var placements: Array = custom_layout.placements if _is_composing() else (displayed_data.environment_modules if displayed_data != null else [])
	if index < 0 or index >= placements.size(): return
	var selected_id: String = placements[index].placement_id
	for candidate in root.get_children():
		if not selected_id.is_empty() and str(candidate.get_meta("placement_id", "")) == selected_id:
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
	if assembly_view != ASSEMBLY_VIEW_COMPLETE and StringName(module.get_meta("structural_assembly_id", &"")).is_empty():
		assembly_view = ASSEMBLY_VIEW_COMPLETE
	if not _is_composing() and not module.has_meta("inspection_base_position"):
		var pivot := AssetPlacement.mesh_bounds(module).get_center()
		for child in module.get_children():
			if child is Node3D:
				child.position -= pivot
		module.position = pivot
		module.set_meta("inspection_base_position", pivot)
	_set_selection_outline(module, true)
	_apply_assembly_view()
	_update_transform_label()

func _set_assembly_view(view: StringName) -> bool:
	if view not in [ASSEMBLY_VIEW_COMPLETE, ASSEMBLY_VIEW_SHELL, ASSEMBLY_VIEW_DECORATION]:
		return false
	if view != ASSEMBLY_VIEW_COMPLETE:
		if not is_instance_valid(inspection_module) or StringName(inspection_module.get_meta("structural_assembly_id", &"")).is_empty():
			_update_transform_label("Select a building assembly before choosing a shell view.")
			return false
	assembly_view = view
	_apply_assembly_view()
	_update_transform_label()
	return true

func _apply_assembly_view() -> void:
	if not is_instance_valid(content):
		return
	var modular_root := content.get_node_or_null("ModularEnvironment")
	if modular_root == null:
		return
	for module_node in modular_root.get_children():
		var module := module_node as Node3D
		module.visible = assembly_view == ASSEMBLY_VIEW_COMPLETE or module == inspection_module
		for visual_node in module.get_children():
			if not visual_node is Node3D:
				continue
			var role: StringName = visual_node.get_meta("assembly_visual_role", &"component")
			match assembly_view:
				ASSEMBLY_VIEW_SHELL:
					visual_node.visible = role == &"structural"
				ASSEMBLY_VIEW_DECORATION:
					visual_node.visible = role == &"decorative"
				_:
					visual_node.visible = true

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
	var assembly_id: StringName = inspection_module.get_meta("structural_assembly_id", &"")
	var assembly_label := ""
	if not assembly_id.is_empty():
		assembly_label = " · assembly=%s · %s · %s" % [
			assembly_id,
			inspection_module.get_meta("assembly_enclosure", &"unknown"),
			inspection_module.get_meta("architectural_purpose", &"unspecified"),
		]
		if assembly_view != ASSEMBLY_VIEW_COMPLETE:
			assembly_label += " · view=%s" % assembly_view
	if _is_composing():
		return "%s origin=%s yaw=%d° variation=%d%s" % [
			inspection_module.get_meta("component_id", &"unknown"),
			inspection_module.get_meta("origin", Vector2i.ZERO),
			int(inspection_module.get_meta("rotation", 0)) * 90,
			int(inspection_module.get_meta("variation", 0)),
			assembly_label,
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
	return "%s%s offset=(%.3f, %.3f, %.3f) yaw=%.1f%s" % [
		inspection_module.get_meta("component_id", &"unknown"), asset_label, offset.x, offset.y, offset.z,
		rad_to_deg(inspection_module.rotation.y),
		assembly_label,
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
		var summary := plan.generation_summary()
		plan_text = "%s · %d roads · %d functional / %d buffers · %d attempts / %d rejected · %d fallback / %d exhausted" % [
			String(plan.topology).replace("_", " "), plan.road_cells.size(),
			int(summary.functional_parcels), int(summary.buffer_parcels),
			int(summary.candidate_attempts), int(summary.candidate_rejections),
			int(summary.fallback_outcomes), int(summary.search_budget_exhaustions),
		]
	var dirty_text := "  |  UNSAVED" if _is_composing() and custom_dirty else ""
	var lmb_help := "select/place" if _is_composing() else "select"
	status.text = "FUSEFIRE MAP EDITOR  |  %s%s  |  seed %d  |  %d components  |  %s\nTarget: %s  |  LMB %s · RMB orbit · MMB pan · wheel zoom · F map · P plan · 1/3/7 views\nPlan: %s" % [
		String(layout_preset).replace("_", " "), dirty_text, generation_seed, component_count, validation_text, inspection_target, lmb_help, plan_text
	]

func _refresh_status_target() -> void:
	if layout_preset == PLOT_LAYOUT: return
	if layout_preset == CHUNK_LAYOUT and chunk_authoring != null:
		chunk_authoring.update_status()
		return
	if not is_instance_valid(status):
		return
	var lines := status.text.split("\n")
	if lines.size() < 2:
		return
	var lmb_help := "select/place" if _is_composing() else "select"
	lines[1] = "Target: %s  |  LMB %s · RMB orbit · MMB pan · wheel zoom · F map · P plan · 1/3/7 views" % [inspection_target, lmb_help]
	status.text = "\n".join(lines)

func _save_custom_layout() -> void:
	if preview_placement != null:
		_set_composer_message("Confirm or cancel the preview first.", true)
		return
	var context := EnvironmentResolutionContext.new()
	var compiled := BattlefieldLayoutDocumentCompiler.compile(custom_document, 1.0, 5, context)
	if not compiled.ok:
		custom_build_errors.assign(compiled.errors)
		_set_composer_message("Cannot save invalid composition: %s" % compiled.errors[0].message, true)
		return
	custom_document = compiled.document
	var error := LayoutStore.save(custom_document, custom_layout_path, context)
	if not error.is_empty():
		_set_composer_message(error, true)
		return
	custom_dirty = false
	_update_status(custom_layout.placements.size(), "TACTICAL VALID")
	_set_composer_message("Saved %d modules to %s." % [custom_layout.placements.size(), custom_layout_path])

func _play_custom_layout() -> void:
	if preview_placement != null:
		_set_composer_message("Confirm or cancel the preview first.", true)
		return
	if custom_document == null:
		_set_composer_message("No unified layout document is available to play.", true)
		return
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battlefield_preset = BattleConfiguration.BattlefieldPreset.GENERATION_2_INDUSTRIAL
	config.map_size = custom_document.map_size()
	config.battle_seed = int(custom_document.provenance.get("generation_seed", generation_seed))
	config.player_count = 2
	config.enemy_count = 2
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, config.enemy_count, false)
	var prepared := Generation2BattlefieldBuilder.compile_document(custom_document, config)
	if not prepared.ok:
		_set_composer_message("Cannot play edited battlefield: %s" % prepared.errors[0].get("message", "validation failed"), true)
		return
	var battle := BATTLE_SCENE.instantiate() as BattleLevel
	battle.configure_layout_document(config, prepared.document)
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	queue_free()

func _load_custom_layout(rebuild_after: bool) -> void:
	var result := LayoutStore.load(editor_catalog, custom_layout_path, &"legacy_compatibility")
	var loaded_starter := false
	if not result.ok and result.code == "FILE_NOT_FOUND":
		result = LayoutStore.load(editor_catalog, starter_layout_path, &"legacy_compatibility")
		loaded_starter = result.ok
		if not result.ok:
			if rebuild_after:
				_set_composer_message(result.error, true)
			return
	elif not result.ok:
		if rebuild_after:
			_set_composer_message("Load rejected; current composition was preserved: %s" % result.error, true)
		return
	if not _adopt_loaded_custom_layout(result):
		return
	var loaded_legacy: bool = result.legacy
	var load_warnings: Array = result.warnings
	custom_dirty = loaded_starter or loaded_legacy
	if rebuild_after:
		_rebuild()
		if loaded_starter:
			_set_composer_message("Loaded the legacy starter composition. Save to create a versioned custom document.")
		elif loaded_legacy:
			_set_composer_message("Loaded schema-1 composition in legacy compatibility mode. Save to migrate it explicitly.")
		elif not load_warnings.is_empty():
			_set_composer_message("Reloaded with warning: %s" % load_warnings[0])
		else:
			_set_composer_message("Reloaded %d modules with %s identity." % [custom_layout.placements.size(), custom_document.environment_id])

func _adopt_loaded_custom_layout(result: Dictionary) -> bool:
	# The store validates the complete document before this transaction boundary.
	# A failed parse or dependency resolution cannot partly replace editor state.
	if not bool(result.get("ok", false)) or result.get("document") == null or result.get("layout") == null:
		return false
	custom_layout = result.layout
	custom_layout.layout_id = CUSTOM_LAYOUT
	preview_map_size = result.map_size
	custom_document = result.document
	return true

func _clear_custom_layout() -> void:
	custom_layout = EnvironmentModuleLayout.new(CUSTOM_LAYOUT, 0)
	custom_document = BattlefieldLayoutDocument.from_authored(custom_layout, preview_map_size, &"mixed_service", "new_custom_layout")
	custom_dirty = true
	_rebuild()
	_set_composer_message("Cleared the working composition. Save only when this is intentional.")

func _accept_custom_layout(candidate: EnvironmentModuleLayout) -> bool:
	var context := EnvironmentResolutionContext.new()
	var support_failures := EnvironmentModuleLayout.Spatial.source_support_errors(candidate, editor_catalog, preview_map_size)
	if not support_failures.is_empty():
		_set_composer_message("%s: %s" % [support_failures[0].code, support_failures[0].message], true)
		return false
	if custom_document == null:
		custom_document = BattlefieldLayoutDocument.from_authored(candidate, preview_map_size, &"mixed_service", "legacy_custom_layout")
	else:
		var errors := custom_document.apply_edited_layout(candidate, context)
		if not errors.is_empty():
			_set_composer_message("%s: %s" % [errors[0].code, errors[0].message], true)
			return false
	pending_resolution = context
	custom_layout = candidate
	custom_dirty = true
	return true

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
	if data.environment_layout_plan == null: return
	var plan := data.environment_layout_plan
	var groups := [
		{"color":Color(1.0,0.65,0.16,0.75),"height":0.13,"rects":[],"segments":[]},
		{"color":Color(0.15,0.92,1.0,0.9),"height":0.15,"rects":[],"segments":[]},
		{"color":Color(0.30,1.0,0.35,1.0),"height":0.19,"rects":[],"segments":[]},
		{"color":Color(1.0,0.25,0.82,0.85),"height":0.18,"rects":[],"segments":[]},
		{"color":Color(1.0,0.92,0.20,0.8),"height":0.17,"rects":[],"segments":[]},
	]
	for parcel in plan.parcels:
		groups[0].rects.append(parcel.bounds)
		for frontage in parcel.get("frontage_spans",[]):
			if str(frontage.get("frontage_id","")) != str(parcel.get("selected_frontage_id","")): continue
			var start = frontage.get("start",[]); var finish = frontage.get("end",[])
			if start is Array and finish is Array and start.size() == 2 and finish.size() == 2: groups[2].segments.append([start,finish])
	for cell in plan.road_cells: groups[1].rects.append(Rect2i(cell*plan.macro_size,Vector2i.ONE*plan.macro_size))
	for reservation in plan.reservations:
		var group := -1
		if reservation.get("role","") in [ReservationLedger.PEDESTRIAN_ACCESS,ReservationLedger.LOADING_SERVICE_APPROACH,ReservationLedger.CIRCULATION_CLEARANCE]: group = 3
		elif reservation.get("role","") in [ReservationLedger.DEPLOYMENT_REGION,ReservationLedger.OBJECTIVE_REGION]: group = 4
		if group >= 0:
			for cell: Vector2i in reservation.get("cells",[]): groups[group].rects.append(Rect2i(cell,Vector2i.ONE))
	var mesh := ImmediateMesh.new()
	for group in groups:
		# Empty road/frontage/mission layers are legitimate in authored plots.
		if group.rects.is_empty() and group.segments.is_empty(): continue
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = group.color
		mesh.surface_begin(Mesh.PRIMITIVE_LINES,material)
		for bounds: Rect2i in group.rects: _add_plan_rect(mesh,bounds,data.map_size,group.height)
		for segment in group.segments: _add_plan_segment(mesh,segment[0],segment[1],data.map_size,group.height)
		mesh.surface_end()
	var overlay := MeshInstance3D.new()
	overlay.name = "SpatialPlan"; overlay.mesh = mesh; overlay.visible = show_plan_overlay
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

func _add_plan_segment(mesh: ImmediateMesh, start_data, end_data, map_size: Vector2i, height: float) -> void:
	if not start_data is Array or not end_data is Array or start_data.size() != 2 or end_data.size() != 2: return
	var half := Vector2(map_size) * 0.5
	var start := Vector2(float(start_data[0]), float(start_data[1])) - half
	var finish := Vector2(float(end_data[0]), float(end_data[1])) - half
	mesh.surface_add_vertex(Vector3(start.x, height, start.y))
	mesh.surface_add_vertex(Vector3(finish.x, height, finish.y))

func _save_population() -> void:
	if displayed_data == null or displayed_data.battlefield_layout_document == null: return
	var path := population_save_directory.path_join("population_%d.json" % generation_seed)
	var error := LayoutStore.save(displayed_data.battlefield_layout_document, path)
	population_message.text = "Saved exact populated battlefield: " + path if error.is_empty() else error

func _play_population(kind: MissionObjectiveDefinition.Kind) -> void:
	if displayed_data == null or displayed_data.battlefield_layout_document == null: return
	var config := FixedEnvironmentPopulation.configuration(generation_seed, kind)
	var prepared := Generation2BattlefieldBuilder.compile_document(displayed_data.battlefield_layout_document, config)
	if not prepared.ok:
		population_message.text = "Cannot play: " + str(prepared.errors)
		return
	var battle := BATTLE_SCENE.instantiate() as BattleLevel
	battle.configure_layout_document(config, prepared.document)
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	queue_free()

func _reload_population() -> void:
	var path := population_save_directory.path_join("population_%d.json" % generation_seed)
	var loaded := LayoutStore.load(editor_catalog, path)
	if not loaded.ok:
		population_message.text = "Cannot reload saved seed: " + str(loaded.get("error", "invalid file"))
		return
	var compiled := BattlefieldLayoutDocumentCompiler.compile(loaded.document)
	if not compiled.ok or not loaded.document.provenance.has("population"):
		population_message.text = "Saved file is not a valid populated battlefield: " + str(compiled.errors)
		return
	pending_population = compiled
	_rebuild()
	population_message.text = "Loaded exact saved population from " + path + ". No reroll."
