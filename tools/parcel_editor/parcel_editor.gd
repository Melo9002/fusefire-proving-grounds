class_name ParcelEditor
extends Node3D
## Small registered-parcel inspection shell. This deliberately does not restore
## the retired chunk generator, publication system, or runtime dependencies.

const Catalog = preload("res://systems/generation/authored_parcel_catalog.gd")
const DraftSession = preload("res://tools/parcel_editor/parcel_draft_session.gd")
const FieldPanel = preload("res://tools/parcel_editor/population_field_panel.gd")
var field_panel

var parcel_picker: OptionButton
var metadata_label: Label
var validation_label: Label
var population_toggle: CheckButton
var tactical_toggle: CheckButton
var placement_picker: OptionButton
var draft_status: Label
var undo_button: Button
var redo_button: Button
var camera: Camera3D
var displayed_parcel_id: StringName = &""
var displayed_parcel: Node3D
var tactical_overlay: Node3D
var draft = DraftSession.new()

var _definitions: Array = []
var _grid: MeshInstance3D
var _camera_target := Vector3(0, 1.5, 0)
var _yaw := deg_to_rad(45.0)
var _pitch := deg_to_rad(34.0)
var _distance := 32.0
var _orbiting := false
var _panning := false

func _ready() -> void:
	_build_stage()
	_build_ui()
	_definitions = Catalog.all()
	for definition in _definitions:
		parcel_picker.add_item("%s — %s" % [definition.display_name, _size_label(definition.size)])
		parcel_picker.set_item_metadata(parcel_picker.item_count - 1, definition.parcel_id)
	if not _definitions.is_empty():
		_show_index(0)
	_update_camera()

func _build_stage() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("17232d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b8c8d8")
	environment.ambient_light_energy = 0.68
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 44.0
	add_child(camera)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.size = Vector2(390, 720)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(358, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	var title := Label.new()
	title.text = "FUSEFIRE / PARCEL EDITOR"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)
	var scope := Label.new()
	scope.text = "Registered authored parcels — inspection foundation"
	scope.modulate = Color(0.66, 0.76, 0.86)
	scope.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(scope)
	parcel_picker = OptionButton.new()
	parcel_picker.name = "ParcelPicker"
	parcel_picker.item_selected.connect(_show_index)
	column.add_child(parcel_picker)
	metadata_label = Label.new()
	metadata_label.name = "Metadata"
	metadata_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	metadata_label.custom_minimum_size.y = 112
	column.add_child(metadata_label)
	validation_label = Label.new()
	validation_label.name = "Validation"
	validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(validation_label)
	var edit_label := Label.new()
	edit_label.text = "VISUAL PLACEMENT DRAFT"
	edit_label.modulate = Color(0.72, 0.82, 0.92)
	column.add_child(edit_label)
	placement_picker = OptionButton.new()
	placement_picker.name = "PlacementPicker"
	placement_picker.tooltip_text = "Select an imported visual node. Tactical metadata remains unchanged."
	placement_picker.item_selected.connect(_select_placement_index)
	column.add_child(placement_picker)
	var planar := HBoxContainer.new()
	for spec in [["X−", Vector3(-0.5, 0, 0)], ["X+", Vector3(0.5, 0, 0)], ["Z−", Vector3(0, 0, -0.5)], ["Z+", Vector3(0, 0, 0.5)]]:
		var button := Button.new()
		button.text = spec[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): _translate_selected(spec[1]))
		planar.add_child(button)
	column.add_child(planar)
	var vertical := HBoxContainer.new()
	for spec in [["Y−", Vector3(0, -0.25, 0)], ["Y+", Vector3(0, 0.25, 0)], ["YAW −90", -1], ["YAW +90", 1], ["RESET", 0]]:
		var button := Button.new()
		button.text = spec[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if spec[1] is Vector3:
			button.pressed.connect(func(): _translate_selected(spec[1]))
		elif int(spec[1]) == 0:
			button.pressed.connect(_reset_selected)
		else:
			button.pressed.connect(func(): _rotate_selected(int(spec[1])))
		vertical.add_child(button)
	column.add_child(vertical)
	var history := HBoxContainer.new()
	undo_button = Button.new()
	undo_button.text = "UNDO"
	undo_button.pressed.connect(_undo)
	history.add_child(undo_button)
	redo_button = Button.new()
	redo_button.text = "REDO"
	redo_button.pressed.connect(_redo)
	history.add_child(redo_button)
	var save := Button.new()
	save.text = "SAVE DRAFT"
	save.pressed.connect(_save_draft)
	history.add_child(save)
	var load_draft := Button.new()
	load_draft.text = "LOAD DRAFT"
	load_draft.pressed.connect(_load_draft)
	history.add_child(load_draft)
	for button in history.get_children():
		(button as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(history)
	draft_status = Label.new()
	draft_status.name = "DraftStatus"
	draft_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	draft_status.modulate = Color(0.68, 0.76, 0.84)
	column.add_child(draft_status)
	population_toggle = CheckButton.new()
	population_toggle.name = "PopulationToggle"
	population_toggle.text = "Show authored movable population"
	population_toggle.button_pressed = true
	population_toggle.toggled.connect(set_population_visible)
	column.add_child(population_toggle)
	tactical_toggle = CheckButton.new()
	tactical_toggle.name = "TacticalToggle"
	tactical_toggle.text = "Show tactical contracts"
	tactical_toggle.tooltip_text = "Cyan: elevated route/access. Orange: explicit tactical solid volumes. These overlays, not imported meshes, explain gameplay authority."
	tactical_toggle.button_pressed = false
	tactical_toggle.toggled.connect(func(enabled: bool): if tactical_overlay: tactical_overlay.visible = enabled)
	column.add_child(tactical_toggle)
	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 6)
	for spec in [["FRAME", _frame], ["TOP", _top_view], ["OBLIQUE", _oblique_view]]:
		var button := Button.new()
		button.text = spec[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(spec[1])
		views.add_child(button)
	column.add_child(views)
	var help := Label.new()
	help.text = "RMB orbit · MMB pan · wheel zoom · F frame"
	help.modulate = Color(0.62, 0.7, 0.78)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(help)
	field_panel = FieldPanel.new()
	field_panel.setup(self)
	column.add_child(field_panel)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var back := Button.new()
	back.text = "BACK TO MATCH SETUP"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://ui/match_setup.tscn"))
	column.add_child(back)

func select_parcel(parcel_id: StringName) -> bool:
	for index in _definitions.size():
		if _definitions[index].parcel_id == parcel_id:
			parcel_picker.select(index)
			_show_index(index)
			return true
	return false

func _show_index(index: int) -> void:
	if index < 0 or index >= _definitions.size():
		return
	if is_instance_valid(displayed_parcel):
		displayed_parcel.free()
	if is_instance_valid(_grid):
		_grid.free()
	if is_instance_valid(tactical_overlay):
		tactical_overlay.free()
	var definition = _definitions[index]
	displayed_parcel_id = definition.parcel_id
	displayed_parcel = definition.instantiate()
	displayed_parcel.name = "DisplayedParcel"
	displayed_parcel.position = Vector3(-(definition.size.x - 1) * 0.5, 0, -(definition.size.y - 1) * 0.5)
	add_child(displayed_parcel)
	_grid = _create_grid(definition.size)
	add_child(_grid)
	tactical_overlay = _create_tactical_overlay(definition)
	tactical_overlay.visible = tactical_toggle.button_pressed
	add_child(tactical_overlay)
	var connection = definition.connection()
	var connection_text := "none"
	if connection != null:
		connection_text = "%s · cell %s · outward %s · width %d" % [connection.kind, connection.cell, connection.outward, connection.width]
	metadata_label.text = "ID  %s\nRole  %s\nFootprint  %s\nRevision  %d\nService interface  %s" % [definition.parcel_id, definition.role, _size_label(definition.size), definition.revision, connection_text]
	var surfaces: Dictionary = definition.population_surfaces(displayed_parcel)
	for region in definition.population_regions(displayed_parcel):
		var surface: Dictionary = surfaces.get(region.surface_id, {})
		metadata_label.text += "\nPopulation  %s · %s · level %s · %s" % [region.region_id, region.surface_id, str(surface.get("level", "missing")), region.local_rect]
	var failures: PackedStringArray = definition.validate()
	validation_label.text = "VALID — registered scene and contracts agree" if failures.is_empty() else "INVALID — %s" % "; ".join(failures)
	validation_label.modulate = Color("79d99b") if failures.is_empty() else Color("ff7a7a")
	population_toggle.button_pressed = true
	population_toggle.disabled = definition.population_sockets().is_empty()
	set_population_visible(true)
	draft.begin(definition, displayed_parcel)
	field_panel.begin(definition, displayed_parcel)
	_refresh_placement_picker()
	_update_draft_status("Source parcel loaded; runtime content is unchanged.")
	_frame()

func _refresh_placement_picker() -> void:
	placement_picker.clear()
	for record: Dictionary in draft.placements:
		placement_picker.add_item("%s · %s" % [record.path, record.asset_id.get_file()])
		placement_picker.set_item_metadata(placement_picker.item_count - 1, String(record.path))
		if String(record.path) == draft.selected_path:
			placement_picker.select(placement_picker.item_count - 1)
	_update_history_buttons()

func _select_placement_index(index: int) -> void:
	if index >= 0 and index < placement_picker.item_count:
		draft.select(String(placement_picker.get_item_metadata(index)))
		_update_draft_status()

func _translate_selected(delta: Vector3) -> void:
	if draft.translate_selected(delta):
		_apply_draft("Moved visual placement %s." % delta)
	else:
		_update_draft_status(draft.last_error)

func _rotate_selected(turns: int) -> void:
	if draft.rotate_selected_quarter(turns):
		_apply_draft("Rotated visual placement %s90°." % ("+" if turns > 0 else "−"))
	else:
		_update_draft_status(draft.last_error)

func _reset_selected() -> void:
	if draft.reset_selected(displayed_parcel):
		_apply_draft("Reset visual placement to its authored transform.")
	else:
		_update_draft_status(draft.last_error)

func _undo() -> void:
	if draft.undo():
		_apply_draft("Undid the last draft edit.")

func _redo() -> void:
	if draft.redo():
		_apply_draft("Redid the draft edit.")

func _apply_draft(message := "") -> void:
	var failures := draft.apply(displayed_parcel)
	_update_draft_status(message if failures.is_empty() else "; ".join(failures))
	_update_history_buttons()

func _save_draft() -> void:
	_update_draft_status("Saved visual-only draft to %s." % draft.draft_path() if draft.save() else draft.last_error)
	_update_history_buttons()

func _load_draft() -> void:
	var definition = Catalog.get_definition(displayed_parcel_id)
	if draft.load_for(definition, displayed_parcel):
		_apply_draft("Loaded visual-only draft from %s." % draft.draft_path())
		_refresh_placement_picker()
	else:
		_update_draft_status(draft.last_error)

func _update_draft_status(message := "") -> void:
	var record: Dictionary = draft.placement()
	var selection := "No visual placement selected."
	if not record.is_empty():
		selection = "%s\nposition %s · yaw %.1f°" % [record.path, record.position, float(record.rotation_degrees[1])]
	var state := "unsaved" if draft.dirty else "saved/source"
	draft_status.text = "%s · %s\n%s%s" % [String(draft.parcel_id), state, selection, "\n" + message if not message.is_empty() else ""]
	_update_history_buttons()

func _update_history_buttons() -> void:
	if undo_button:
		undo_button.disabled = draft.undo_stack.is_empty()
	if redo_button:
		redo_button.disabled = draft.redo_stack.is_empty()

func set_population_visible(enabled: bool) -> void:
	if not is_instance_valid(displayed_parcel):
		return
	for node in displayed_parcel.find_children("*", "Node3D", true, false):
		if node.has_meta("population_socket_id"):
			(node as Node3D).visible = enabled

func _create_grid(size: Vector2i) -> MeshInstance3D:
	var immediate := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.12, 0.78, 0.9, 0.45)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for x in range(size.x + 1):
		var px := float(x) - size.x * 0.5
		immediate.surface_add_vertex(Vector3(px, 0.025, -size.y * 0.5))
		immediate.surface_add_vertex(Vector3(px, 0.025, size.y * 0.5))
	for z in range(size.y + 1):
		var pz := float(z) - size.y * 0.5
		immediate.surface_add_vertex(Vector3(-size.x * 0.5, 0.025, pz))
		immediate.surface_add_vertex(Vector3(size.x * 0.5, 0.025, pz))
	immediate.surface_end()
	var result := MeshInstance3D.new()
	result.name = "FootprintGrid"
	result.mesh = immediate
	return result

func _create_tactical_overlay(definition) -> Node3D:
	var overlay := Node3D.new()
	overlay.name = "TacticalContracts"
	var solid_material := _overlay_material(Color(1.0, 0.42, 0.12, 0.34))
	for node in displayed_parcel.find_children("*", "Node3D", true, false):
		if not node.has_meta("solid_size"):
			continue
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = node.get_meta("solid_size", Vector3.ONE)
		mesh.material = solid_material
		box.mesh = mesh
		# The overlay is added at the editor origin, so the already-instantiated
		# parcel node's world transform is also the overlay-local transform.
		box.transform = (node as Node3D).global_transform
		overlay.add_child(box)
	var cyan := _overlay_material(Color(0.08, 0.86, 1.0, 0.36))
	var deck_rect: Rect2i = displayed_parcel.get_meta("deck_local_rect", Rect2i())
	if deck_rect.has_area():
		var deck := MeshInstance3D.new()
		var deck_mesh := BoxMesh.new()
		deck_mesh.size = Vector3(deck_rect.size.x, 0.12, deck_rect.size.y)
		deck_mesh.material = cyan
		deck.mesh = deck_mesh
		deck.position = Vector3(deck_rect.position.x + deck_rect.size.x * 0.5 - definition.size.x * 0.5, float(displayed_parcel.get_meta("deck_level", 0)) + 0.08, deck_rect.position.y + deck_rect.size.y * 0.5 - definition.size.y * 0.5)
		overlay.add_child(deck)
	var access: Vector3i = displayed_parcel.get_meta("access_cell", Vector3i(-1, 0, -1))
	if access.x >= 0:
		var marker := MeshInstance3D.new()
		var marker_mesh := BoxMesh.new()
		marker_mesh.size = Vector3(0.8, 0.12, 0.8)
		marker_mesh.material = cyan
		marker.mesh = marker_mesh
		marker.position = Vector3(access.x - (definition.size.x - 1) * 0.5, access.y + 0.1, access.z - (definition.size.y - 1) * 0.5)
		overlay.add_child(marker)
	return overlay

func _overlay_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	return material

func _size_label(size: Vector2i) -> String:
	return "%d × %d" % [size.x, size.y]

func _frame() -> void:
	if displayed_parcel_id.is_empty():
		return
	var definition = Catalog.get_definition(displayed_parcel_id)
	_camera_target = Vector3(0, 1.8, 0)
	_distance = maxf(definition.size.x, definition.size.y) * 1.15 + 5.0
	_update_camera()

func _top_view() -> void:
	var definition = Catalog.get_definition(displayed_parcel_id)
	_camera_target = Vector3.ZERO
	_distance = maxf(definition.size.x, definition.size.y) * 1.25 + 5.0
	_yaw = 0.0
	_pitch = deg_to_rad(89.0)
	_update_camera()

func _oblique_view() -> void:
	_yaw = deg_to_rad(45.0)
	_pitch = deg_to_rad(34.0)
	_frame()

func _update_camera() -> void:
	if camera == null:
		return
	var horizontal := cos(_pitch) * _distance
	var offset := Vector3(sin(_yaw) * horizontal, sin(_pitch) * _distance, cos(_yaw) * horizontal)
	camera.position = _camera_target + offset
	camera.look_at(_camera_target)

func _unhandled_input(event: InputEvent) -> void:
	if field_panel != null and field_panel.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed and event.keycode == KEY_Z:
			_undo()
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode == KEY_Y:
			_redo()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F:
			_frame()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(3.0, _distance * 0.88)
			_update_camera()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(140.0, _distance / 0.88)
			_update_camera()
	elif event is InputEventMouseMotion:
		if _orbiting:
			_yaw -= event.relative.x * 0.008
			_pitch = clampf(_pitch - event.relative.y * 0.008, deg_to_rad(8.0), deg_to_rad(89.0))
			_update_camera()
		elif _panning:
			var pan_scale := _distance * 0.0018
			var right := camera.global_basis.x
			var forward := Vector3(camera.global_basis.z.x, 0, camera.global_basis.z.z).normalized()
			_camera_target += right * -event.relative.x * pan_scale + forward * -event.relative.y * pan_scale
			_update_camera()
