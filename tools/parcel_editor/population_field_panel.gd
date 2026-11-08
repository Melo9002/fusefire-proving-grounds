extends VBoxContainer
## Small editor-only UI; field data and persistence live in PopulationFieldDraft.
const Session = preload("res://tools/parcel_editor/population_field_draft.gd")
const Vehicles = preload("res://tools/parcel_editor/parking_vehicle_templates.gd")
const SceneExport = preload("res://tools/parcel_editor/parking_scene_export.gd")
var session = Session.new()
var surface_picker: OptionButton
var preset_picker: OptionButton
enum Tool { INSPECT, DRAW, ERASE, PARKING_ROW }
const PERMITTED_COLOR := Color("949bff")
const PROTECTED_COLOR := Color("ff806b")
var active_tool := Tool.INSPECT
var tool_buttons: Array[Button] = []
var guidance: Label
var measurement: Label
var preview_button: Button
var export_button: Button
var undo_button: Button
var redo_button: Button
var heading_picker: OptionButton
var seed_input: SpinBox
var density: SpinBox
var status: Label
var host: Node3D
var overlay: Node3D
var start_cell: Variant = null
var drag_cell: Variant = null
var _source_sockets: Array[Dictionary] = []
var _fixed_obstacles: Array[AABB] = []
var _vehicles = Vehicles.new()
var _row_preview: Node3D
var _previewing := false
var _preview_ids := {}
var _aisle_arrow: MeshInstance3D
var _field_destination: Label

func setup(editor: Node3D) -> void:
	host = editor
	var tools := HBoxContainer.new()
	var group := ButtonGroup.new()
	for title in ["Inspect", "Paint", "Erase", "Parking row"]:
		var index := tool_buttons.size()
		var button := _add_button(tools, title, func(): select_tool(index))
		button.toggle_mode = true
		button.button_group = group
		button.add_theme_color_override("font_pressed_color", Color("a5dcff"))
		tool_buttons.append(button)
	add_child(tools)
	tool_buttons[Tool.INSPECT].set_pressed_no_signal(true)
	guidance = _add_label(self, "")
	measurement = _add_label(self, "")
	var legend := HBoxContainer.new()
	_add_label(legend, "■ Allowed").modulate = PERMITTED_COLOR
	_add_label(legend, "■ Protected").modulate = PROTECTED_COLOR
	_add_label(legend, "□ Bay").modulate = Color("ffd077")
	_add_label(legend, "□ Aisle").modulate = Color("88e49e")
	add_child(legend)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var options := VBoxContainer.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(options)
	surface_picker = OptionButton.new()
	surface_picker.item_selected.connect(func(_index):
		start_cell = null
		refresh())
	options.add_child(surface_picker)
	preset_picker = OptionButton.new()
	for preset in Session.PRESETS:
		preset_picker.add_item(preset.capitalize())
		preset_picker.set_item_metadata(preset_picker.item_count - 1, preset)
	preset_picker.item_selected.connect(func(_index): _update_tools())
	options.add_child(preset_picker)
	heading_picker = OptionButton.new()
	for label in ["Aisle toward +Z", "Aisle toward −X", "Aisle toward −Z", "Aisle toward +X"]:
		heading_picker.add_item(label)
	heading_picker.item_selected.connect(func(_index):
		start_cell = null
		refresh())
	options.add_child(heading_picker)
	status = _add_label(options, "")
	seed_input = SpinBox.new()
	seed_input.max_value = 2147483647
	seed_input.value = 17
	seed_input.prefix = "Seed "
	seed_input.value_changed.connect(_on_preview_settings_changed)
	options.add_child(seed_input)
	density = SpinBox.new()
	density.max_value = 100
	density.value = 65
	density.suffix = "% of eligible bays"
	density.value_changed.connect(_on_preview_settings_changed)
	options.add_child(density)
	var preview_controls := HBoxContainer.new()
	preview_button = _add_button(preview_controls, "Preview", preview)
	_add_button(preview_controls, "Show source", reset_preview)
	options.add_child(preview_controls)
	_add_label(options, "Preview includes compatible sockets inside painted permission, outside protected areas. Show source restores the authored objects.")
	var history := HBoxContainer.new()
	undo_button = _add_button(history, "Undo field", undo)
	redo_button = _add_button(history, "Redo field", redo)
	options.add_child(history)
	var files := HBoxContainer.new()
	_add_button(files, "Save fields", save_fields)
	_add_button(files, "Load fields", load_fields)
	options.add_child(files)
	var named_files := HBoxContainer.new()
	_add_button(named_files, "Save fields as…", _save_fields_as)
	_add_button(named_files, "Open field draft…", _open_fields)
	options.add_child(named_files)
	_field_destination = _add_label(options, "")
	export_button = _add_button(options, "Export parking scene", export_scene)
	_add_label(options, "Exports go to user://parcel_exports/ with a generated name. Existing exports are kept. Catalog registration is separate.").modulate = Color("93a8ba")
	host.population_toggle.toggled.connect(_apply_preview_visibility)

func _add_button(parent: Container, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _add_label(parent: Container, contents: String) -> Label:
	var label := Label.new()
	label.text = contents
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if parent is VBoxContainer else TextServer.AUTOWRAP_OFF
	parent.add_child(label)
	return label

func select_tool(index: int) -> void:
	if index < 0 or index >= tool_buttons.size() or tool_buttons[index].disabled:
		return
	active_tool = index as Tool
	start_cell = null
	refresh()

func cancel_drag() -> void:
	if start_cell != null:
		start_cell = null
		refresh("Stroke canceled.")

func has_unsaved_changes() -> bool:
	return session.is_dirty()

func _on_preview_settings_changed(_value: float) -> void:
	session.preview_seed = int(seed_input.value)
	session.occupancy = int(density.value)
	clear_preview()
	status.text = "Preview settings changed. Press Preview to update."
	_update_tools()

func _update_tools(provisional: Dictionary = {}) -> void:
	var parking_allowed := false
	var has_row := false
	var latest := provisional
	for field in session.fields:
		has_row = has_row or field.preset == Session.PARKING_ROW
		if field.surface == surface_id():
			parking_allowed = parking_allowed or field.preset == "parking"
			if provisional.is_empty(): latest = field
	tool_buttons[Tool.PARKING_ROW].disabled = not parking_allowed
	if active_tool == Tool.PARKING_ROW and not parking_allowed:
		active_tool = Tool.DRAW
	for index in tool_buttons.size():
		tool_buttons[index].set_pressed_no_signal(index == active_tool)
	preset_picker.visible = active_tool == Tool.DRAW
	heading_picker.visible = active_tool == Tool.PARKING_ROW
	preview_button.disabled = session.fields.is_empty()
	export_button.disabled = not has_row
	undo_button.disabled = session.history.is_empty()
	redo_button.disabled = session.future.is_empty()
	match active_tool:
		Tool.DRAW:
			guidance.text = "Drag to paint. Parking bays need %d × %d cells each, with %d clear cells on the aisle side." % [Session.BAY_WIDTH, Session.BAY_DEPTH, Session.AISLE_DEPTH] if preset_picker.selected == 0 else "Drag on the selected floor to paint."
		Tool.ERASE:
			guidance.text = "Click a field or bay outline to erase it."
		Tool.PARKING_ROW:
			guidance.text = "2. Drag the edge facing the green arrow. Bays are %d × %d cells with a %d-cell aisle. 3. Preview." % [Session.BAY_WIDTH, Session.BAY_DEPTH, Session.AISLE_DEPTH]
		_:
			guidance.text = "1. Paint Parking permission → 2. Draw a row → 3. Preview." if not parking_allowed else "Parking permission is ready on this floor. Draw a row along its aisle, or preview existing bays."
	if latest.is_empty():
		measurement.text = "%d draft areas" % session.fields.size()
	else:
		var rect := Session.rectangle(latest)
		measurement.text = "%s · %d × %d cells" % [String(latest.preset).replace("_", " ").capitalize(), rect.size.x, rect.size.y]
	host.update_draft_badge()

func begin(definition, scene_root: Node3D) -> void:
	session.begin(definition, scene_root)
	_field_destination.text = "Quick save / load · " + session.path()
	_field_destination.tooltip_text = ProjectSettings.globalize_path(session.path())
	_source_sockets = definition.population_sockets(scene_root)
	_fixed_obstacles = session.parking_obstacles(definition, scene_root)
	start_cell = null
	surface_picker.clear()
	seed_input.set_value_no_signal(session.preview_seed)
	density.set_value_no_signal(session.occupancy)
	var ids: Array = session.surfaces.keys()
	ids.sort()
	for id in ids:
		surface_picker.add_item("%s · level %d" % [id, session.surfaces[id].level])
		surface_picker.set_item_metadata(surface_picker.item_count - 1, id)
	active_tool = Tool.INSPECT
	refresh()

func surface_id() -> String:
	return String(surface_picker.get_selected_metadata())

func cell_at(screen: Vector2) -> Variant:
	if session.surfaces.is_empty(): return null
	var level := float(session.surfaces[surface_id()].level)
	var origin: Vector3 = host.displayed_parcel.global_position
	var point: Variant = Plane(Vector3.UP, origin.y + level).intersects_ray(host.camera.project_ray_origin(screen), host.camera.project_ray_normal(screen))
	if point == null: return null
	var local: Vector3 = host.displayed_parcel.to_local(point)
	return Vector2i(roundi(local.x), roundi(local.z))

func handle_input(event: InputEvent) -> bool:
	if active_tool == Tool.INSPECT: return false
	if active_tool == Tool.PARKING_ROW and event is InputEventMouseMotion and start_cell == null:
		var hover: Variant = cell_at(event.position)
		if hover != null:
			_position_aisle_arrow(hover)
	if event is InputEventMouseMotion and start_cell != null:
		var next_cell: Variant = cell_at(event.position)
		if next_cell != drag_cell:
			drag_cell = next_cell
			refresh("Release to commit the previewed rectangle.")
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var cell: Variant = cell_at(event.position)
		if event.pressed:
			if active_tool == Tool.ERASE:
				if cell != null and session.erase_at(surface_id(), cell):
					refresh("Erased field.")
			else:
				start_cell = cell
				drag_cell = cell
				refresh("Drag to size the field.")
		elif start_cell != null:
			var record := _drag_record(cell) if cell != null else {}
			var ok: bool = not record.is_empty() and session.add(record.surface, record.preset, Session.rectangle(record), int(record.get("heading", 0)))
			start_cell = null
			refresh("Draft updated." if ok else session.last_error)
		return true
	return false

func _drag_record(cell: Vector2i) -> Dictionary:
	var heading := heading_picker.selected
	var preset := String(preset_picker.get_selected_metadata())
	var rect: Rect2i
	if active_tool == Tool.PARKING_ROW:
		preset = Session.PARKING_ROW
		rect = Session.parking_row_rect(start_cell, cell, heading)
	else:
		var lower := Vector2i(mini(start_cell.x, cell.x), mini(start_cell.y, cell.y))
		var extent := Vector2i(absi(cell.x - start_cell.x) + 1, absi(cell.y - start_cell.y) + 1)
		rect = Rect2i(lower, extent)
	return {"surface": surface_id(), "preset": preset, "heading": heading, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]}

func refresh(message := "") -> void:
	clear_preview()
	if is_instance_valid(overlay): overlay.free()
	overlay = Node3D.new()
	host.add_child(overlay)
	overlay.visible = is_visible_in_tree()
	var fields: Array = session.fields.duplicate()
	var provisional := {}
	if start_cell != null and drag_cell != null:
		provisional = _drag_record(drag_cell)
		if provisional.preset != Session.PARKING_ROW:
			fields.append(provisional)
	var cells := {}
	for field: Dictionary in fields:
		if field.preset == Session.PARKING_ROW: continue
		var rect := Session.rectangle(field)
		var level := int(session.surfaces[field.surface].level)
		var bounds: Array = session.surfaces[field.surface].rect
		rect = rect.intersection(Rect2i(int(bounds[0]), int(bounds[1]), int(bounds[2]), int(bounds[3])))
		for x in range(rect.position.x, rect.end.x):
			for z in range(rect.position.y, rect.end.y):
				var key := Vector3i(x, level, z)
				cells[key] = bool(cells.get(key, false)) or field.preset == "protected"
	for protected in [false, true]:
		var mesh := ImmediateMesh.new()
		var field_material := StandardMaterial3D.new()
		field_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var tint := PROTECTED_COLOR if protected else PERMITTED_COLOR
		field_material.albedo_color = Color(tint, 0.44 if protected else 0.38)
		field_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		field_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		if not cells.values().has(protected): continue
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, field_material)
		for cell: Vector3i in cells:
			if cells[cell] != protected: continue
			for offset in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]:
				mesh.surface_add_vertex(Vector3(cell) + offset + Vector3.UP * 0.07)
		mesh.surface_end()
		var outline := StandardMaterial3D.new()
		outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		outline.albedo_color = tint
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, outline)
		for cell: Vector3i in cells:
			if cells[cell] != protected: continue
			for side in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
				if cells.get(cell + side) == protected: continue
				var midpoint := Vector3(cell) + Vector3(side) * 0.5 + Vector3.UP * 0.085
				var edge := Vector3(side).cross(Vector3.UP) * 0.5
				mesh.surface_add_vertex(midpoint - edge)
				mesh.surface_add_vertex(midpoint + edge)
		mesh.surface_end()
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.position = host.displayed_parcel.position
		overlay.add_child(visual)
	var bays: Array[Dictionary] = session.parking_bays(_source_sockets, _fixed_obstacles, provisional if provisional.get("preset") == Session.PARKING_ROW else {})
	var fitting := _draw_bays(bays)
	_update_tools(provisional)
	_draw_aisle_arrow()
	status.text = message
	if not bays.is_empty():
		if not status.text.is_empty(): status.text += "\n"
		status.text += "%d bays fit · %d rejected." % [fitting, bays.size() - fitting]
		var rejected: Array = bays.filter(func(bay): return not bay.reason.is_empty())
		if not rejected.is_empty(): status.text += " First rejection: %s." % rejected[0].reason

func preview() -> void:
	if host.draft.placements != host.draft.base_placements:
		status.text = "Preview requires source transforms. Reload the parcel after saving your visual draft."
		return
	clear_preview()
	var map_seed := int(seed_input.value)
	var candidates := _source_sockets.duplicate()
	var row_candidates := {}
	for bay: Dictionary in session.parking_bays(_source_sockets, _fixed_obstacles):
		if not bay.reason.is_empty(): continue
		var candidate := _vehicles.candidate(bay, map_seed, session.parcel_id)
		if not candidate.is_empty():
			row_candidates[candidate.socket_id] = candidate
			candidates.append(candidate)
	var choices: Array[Dictionary] = session.preview(candidates, map_seed, int(density.value), _fixed_obstacles)
	_previewing = true
	for choice in choices: _preview_ids[choice.socket_id] = choice
	for node in host.displayed_parcel.find_children("*", "Node3D", true, false):
		if not node.has_meta("population_socket_id"): continue
		var id: StringName = node.get_meta("population_socket_id")
		node.set_meta("field_preview_base_yaw", node.rotation.y)
		node.rotation.y -= int(_preview_ids.get(id, {}).get("yaw_turns", 0)) * PI * 0.5
	var row_count := 0
	for choice in choices:
		if not row_candidates.has(choice.socket_id): continue
		var candidate: Dictionary = row_candidates[choice.socket_id]
		if not is_instance_valid(_row_preview):
			_row_preview = Node3D.new()
			_row_preview.position = host.displayed_parcel.position
			host.add_child(_row_preview)
		var car: Node3D = candidate.template.duplicate()
		car.position = candidate.local_position
		car.rotation.y = -(candidate.heading + int(choice.yaw_turns)) * PI * 0.5
		_row_preview.add_child(car)
		row_count += 1
	if is_instance_valid(_row_preview): host.population_toggle.disabled = false
	_apply_preview_visibility(host.population_toggle.button_pressed)
	_update_tools()
	var excluded := _source_sockets.filter(func(socket): return session.field_excluded_sockets.has(socket.socket_id)).size()
	status.text = "%d authored sockets + %d row bay%s occupied. %d of %d authored sockets excluded by permission or protection. %d overlap conflicts rejected." % [choices.size() - row_count, row_count, "" if row_count == 1 else "s", excluded, _source_sockets.size(), session.conflict_count]

func _draw_aisle_arrow() -> void:
	if active_tool != Tool.PARKING_ROW:
		return
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color("a0ffb4")
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for point in [Vector2(-0.14, 0), Vector2(0.14, 0), Vector2(0.14, 1.4), Vector2(-0.14, 0), Vector2(0.14, 1.4), Vector2(-0.14, 1.4), Vector2(-0.52, 1.4), Vector2(0.52, 1.4), Vector2(0, 2.2)]:
		mesh.surface_add_vertex(Vector3(point.x, 0, point.y))
	mesh.surface_end()
	_aisle_arrow = MeshInstance3D.new()
	_aisle_arrow.mesh = mesh
	_aisle_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aisle_arrow.rotation.y = -heading_picker.selected * PI * 0.5
	overlay.add_child(_aisle_arrow)
	for field in session.fields:
		if field.surface == surface_id() and field.preset == "parking":
			var rect := Session.rectangle(field)
			_position_aisle_arrow(rect.get_center() if start_cell == null else start_cell)
			break

func _position_aisle_arrow(cell: Vector2i) -> void:
	if not is_instance_valid(_aisle_arrow):
		return
	var surface: Dictionary = session.surfaces[surface_id()]
	var bounds: Array = surface.rect
	if not Rect2i(bounds[0], bounds[1], bounds[2], bounds[3]).has_point(cell):
		return
	_aisle_arrow.position = host.displayed_parcel.position + Vector3(cell.x, surface.level + 0.16, cell.y)

func _draw_bays(bays: Array[Dictionary]) -> int:
	if bays.is_empty(): return 0
	var mesh := ImmediateMesh.new()
	var outline_material := StandardMaterial3D.new()
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_material.vertex_color_use_as_albedo = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, outline_material)
	var aisles := {}
	var fitting := 0
	for bay in bays:
		var fits: bool = bay.reason.is_empty()
		_draw_outline(mesh, bay.rect, bay.level, Color("ffd077") if fits else Color("fb6a62"))
		if not fits: continue
		fitting += 1
		var aisle_key := "%s/%s" % [bay.surface, bay.aisle]
		if not aisles.has(aisle_key):
			_draw_outline(mesh, bay.aisle, bay.level, Color("88e49e"))
			aisles[aisle_key] = true
	mesh.surface_end()
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = host.displayed_parcel.position
	overlay.add_child(visual)
	return fitting

func _draw_outline(mesh: ImmediateMesh, rect: Rect2i, level: int, color: Color) -> void:
	var low := Vector3(rect.position.x - 0.5, level + 0.10, rect.position.y - 0.5)
	var x_edge := low + Vector3.RIGHT * rect.size.x
	var z_edge := low + Vector3.BACK * rect.size.y
	var far_corner := x_edge + Vector3.BACK * rect.size.y
	for point in [low, x_edge, x_edge, far_corner, far_corner, z_edge, z_edge, low]:
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(point)

func _apply_preview_visibility(enabled: bool) -> void:
	if not _previewing: return
	for node in host.displayed_parcel.find_children("*", "Node3D", true, false):
		if node.has_meta("population_socket_id"):
			node.visible = enabled and _preview_ids.has(node.get_meta("population_socket_id"))
	if is_instance_valid(_row_preview): _row_preview.visible = enabled

func clear_preview() -> void:
	if is_instance_valid(_row_preview): _row_preview.free()
	if not _previewing: return
	_previewing = false
	_preview_ids.clear()
	host.population_toggle.disabled = _source_sockets.is_empty()
	host.set_population_visible(host.population_toggle.button_pressed)
	for node in host.displayed_parcel.find_children("*", "Node3D", true, false):
		if node.has_meta("field_preview_base_yaw"):
			node.rotation.y = node.get_meta("field_preview_base_yaw")
			node.remove_meta("field_preview_base_yaw")

func reset_preview() -> void:
	refresh("Source population restored.")

func undo() -> void:
	session.undo()
	reset_preview()

func redo() -> void:
	session.redo()
	reset_preview()

func save_fields() -> void:
	var path: String = session.path()
	host.confirm_replace_draft(path, func(): _save_fields_to(path))

func _save_fields_as() -> void:
	host.choose_draft_file(session.path(), true, _save_fields_to)

func _save_fields_to(path: String) -> void:
	session.preview_seed = int(seed_input.value)
	session.occupancy = int(density.value)
	status.text = "Saved " + path if session.save_to(path) else session.last_error
	_update_tools()

func load_fields() -> void:
	_load_fields_from(session.path())

func _open_fields() -> void:
	host.choose_draft_file(session.path(), false, _load_fields_from)

func _load_fields_from(path: String) -> void:
	host.confirm_open_draft(path, has_unsaved_changes(), func(): _apply_loaded_fields(path))

func _apply_loaded_fields(path: String) -> void:
	if session.load_from(path):
		seed_input.set_value_no_signal(session.preview_seed)
		density.set_value_no_signal(session.occupancy)
		reset_preview()
	else: status.text = session.last_error

func export_scene(destination: String = "") -> bool:
	if host.draft.placements != host.draft.base_placements:
		status.text = "Export requires source transforms. Reload the parcel after saving your visual draft."
		return false
	var source = host.Catalog.get_definition(host.displayed_parcel_id)
	var result := SceneExport.build(source, session, _vehicles, int(seed_input.value))
	if result.has("error"):
		status.text = result.error
		return false
	if destination.is_empty():
		destination = "user://parcel_exports/%s.tscn" % result.definition.parcel_id
		if FileAccess.file_exists(destination):
			status.text = "This scene export already exists at %s" % ProjectSettings.globalize_path(destination)
			return false
	var error := DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	if error == OK:
		error = ResourceSaver.save(result.definition.scene, destination)
	if error != OK:
		status.text = "Could not save parking scene: %s" % error_string(error)
		return false
	status.text = "Exported %d parking bays to %s" % [result.bay_count, ProjectSettings.globalize_path(destination)]
	return true
