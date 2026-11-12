extends VBoxContainer
## Small editor-only UI; field data and persistence live in PopulationFieldDraft.
const Session = preload("res://tools/parcel_editor/population_field_draft.gd")
const Vehicles = preload("res://systems/generation/parking_vehicle_templates.gd")
const SceneExport = preload("res://tools/parcel_editor/population_scene_export.gd")
const Resolver = preload("res://systems/generation/refinery_plot_resolver.gd")
const Containers = preload("res://tools/parcel_editor/container_field_placements.gd")
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
var next_seed_button: Button
var registered_preview_button: Button
var preview_context: Label
var density_context: Label
var fit_feedback: Label
var export_button: Button
var export_folder_button: Button
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
var _registered_preview := false
var compiled_preview: MapData
var _aisle_arrow: MeshInstance3D
var _field_destination: Label
var _authored_guides: Node3D
var _runtime_preview: Node3D
var _definition
var _registered_area_count := 0
var _aisle_obstacles: Array[AABB] = []
var _registered_protection: Array[AABB] = []

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

	var preview_controls := HBoxContainer.new()
	preview_button = _add_button(preview_controls, "Preview", preview)
	next_seed_button = _add_button(preview_controls, "Next seed", _next_seed)
	_add_button(preview_controls, "Show guides", reset_preview)
	add_child(preview_controls)
	registered_preview_button = _add_button(self, "Preview registered parcel", preview_registered)
	preview_context = _add_label(self, "")
	fit_feedback = _add_label(self, "")
	fit_feedback.max_lines_visible = 4

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
	density.suffix = "% of eligible positions"
	density.value_changed.connect(_on_preview_settings_changed)
	options.add_child(density)
	density_context = _add_label(options, "")
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
	export_button = _add_button(options, "Export population scene", export_scene)
	_add_label(options, "Finish · Save drafts → Export scene → Review in Godot → Register in AuthoredParcelCatalog. Export includes fixed edits and new positions, retains existing population rules, and uses their battle occupancy. Draft density affects Preview.").modulate = Color("93a8ba")
	export_folder_button = _add_button(options, "Open exported scene folder", func(): OS.shell_open(export_folder_button.get_meta("folder")))
	export_folder_button.disabled = true
	_add_label(options, "Exports go to user://parcel_exports/ with a generated name. Existing exports are kept. Catalog registration is separate.").modulate = Color("93a8ba")
	host.population_toggle.toggled.connect(func(enabled: bool):
		if is_instance_valid(_authored_guides): _authored_guides.visible = enabled)

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
	if not session.fields.is_empty():
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
	density.editable = not session.fields.is_empty()
	density.visible = density.editable
	density_context.text = "Density affects this field draft preview only." if density.editable else "Registered population rules set occupancy. Paint a draft to try a different density."
	export_button.disabled = host.draft.placements == host.draft.base_placements and not has_row and not session.fields.any(func(field): return field.preset in ["parking", "containers"])
	undo_button.disabled = session.history.is_empty()
	redo_button.disabled = session.future.is_empty()
	match active_tool:
		Tool.DRAW:
			match String(preset_picker.get_selected_metadata()):
				"parking":
					guidance.text = "Drag to paint. Parking bays need %d × %d cells each, with %d clear cells on the aisle side." % [Session.BAY_WIDTH, Session.BAY_DEPTH, Session.AISLE_DEPTH]
				"containers":
					guidance.text = "Paint ground cells. New container positions need a clear 3 × 5 area."
				"equipment":
					guidance.text = "Paint permission to preview existing equipment sockets. New equipment paint is preview-only."
				_:
					guidance.text = "Drag to protect cells on the selected floor."
		Tool.ERASE:
			guidance.text = "Click a field or bay outline to erase it."
		Tool.PARKING_ROW:
			guidance.text = "2. Drag the edge facing the green arrow. Bays are %d × %d cells with a %d-cell aisle. 3. Preview." % [Session.BAY_WIDTH, Session.BAY_DEPTH, Session.AISLE_DEPTH]
		_:
			guidance.text = "Paint an allowed area, then Preview a seed together with your fixed objects."
	if latest.is_empty():
		measurement.text = "%d registered areas · %d draft areas" % [_registered_area_count, session.fields.size()]
	else:
		var rect := Session.rectangle(latest)
		measurement.text = "%s · %d × %d cells" % [String(latest.preset).replace("_", " ").capitalize(), rect.size.x, rect.size.y]
	host.update_draft_badge()
	update_preview_controls()

func update_preview_controls() -> void:
	var has_visual_changes: bool = host.draft.placements != host.draft.base_placements
	preview_button.disabled = session.fields.is_empty() and _source_sockets.is_empty() and not has_visual_changes
	next_seed_button.disabled = preview_button.disabled and not is_instance_valid(_runtime_preview)
	registered_preview_button.visible = has_visual_changes
	registered_preview_button.disabled = _source_sockets.is_empty()
	if is_instance_valid(_runtime_preview):
		return
	if has_visual_changes:
		preview_context.text = "Preview includes your fixed objects and their tactical volumes. Registered preview compares the original layout."
	elif preview_button.disabled:
		preview_context.text = "Paint a population area to preview this parcel."
	elif session.fields.is_empty():
		preview_context.text = "Preview uses the registered rules for this seed."
	else:
		preview_context.text = "Preview uses draft paint. Only registered rules appear in battle."

func begin(definition, scene_root: Node3D) -> void:
	_definition = definition
	session.begin(definition, scene_root)
	_field_destination.text = "Quick save / load · " + session.path()
	_field_destination.tooltip_text = ProjectSettings.globalize_path(session.path())
	_source_sockets = definition.population_sockets(scene_root)
	_fixed_obstacles = session.parking_obstacles(definition, scene_root)
	_aisle_obstacles = session.registered_aisles(scene_root)
	_registered_protection = session.registered_protection(scene_root)
	_draw_authored_guides(scene_root)
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

func sync_draft_context() -> void:
	var copy: Node3D = host.draft.preview_root(host.displayed_parcel)
	_source_sockets = _definition.population_sockets(copy)
	_fixed_obstacles = session.parking_obstacles(_definition, copy)
	copy.free()

func _draw_authored_guides(scene_root: Node3D) -> void:
	if is_instance_valid(_authored_guides): _authored_guides.free()
	_authored_guides = Node3D.new()
	_authored_guides.position = scene_root.position
	host.add_child(_authored_guides)
	_authored_guides.visible = host.population_toggle.button_pressed
	var mesh := ImmediateMesh.new()
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	var painted: Array = scene_root.get_meta("parking_population_paint", [])
	var container_paint: Array = scene_root.get_meta("container_population_paint", [])
	var guides: Array[Dictionary] = []
	for rule in painted:
		guides.append({"rect": rule.rect, "surface": rule.surface, "color": PROTECTED_COLOR if rule.get("preset") == "protected" else PERMITTED_COLOR})
	for rule in container_paint:
		guides.append({"rect": rule.rect, "surface": rule.surface, "color": PROTECTED_COLOR if rule.get("preset") == "protected" else Color("67dbc5")})
	for region in _definition.population_regions(scene_root):
		if not painted.is_empty() and String(region.region_id).begins_with("row_bay_"):
			continue
		if not container_paint.is_empty() and String(region.region_id).begins_with("painted_container_"):
			continue
		var tint := Color("67dbc5") if region.role == &"shipping_container" else PERMITTED_COLOR
		guides.append({"rect": region.local_rect, "surface": region.surface_id, "color": tint})
	_registered_area_count = guides.size()
	for guide in guides:
		if not session.surfaces.has(String(guide.surface)): continue
		var rect: Rect2i = guide.rect
		var fill := BoxMesh.new()
		fill.size = Vector3(rect.size.x, 0.01, rect.size.y)
		var tint := StandardMaterial3D.new()
		tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tint.albedo_color = Color(guide.color, 0.22)
		fill.material = tint
		var visual := MeshInstance3D.new()
		visual.mesh = fill
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var center := Vector2(rect.position) + Vector2(rect.size - Vector2i.ONE) * 0.5
		visual.position = Vector3(center.x, session.surfaces[String(guide.surface)].level + 0.045, center.y)
		_authored_guides.add_child(visual)
	if _source_sockets.is_empty(): return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, line_material)
	for socket in _source_sockets:
		var bounds: AABB = socket.local_bounds
		var lower := Vector2i(floori(bounds.position.x + 0.5), floori(bounds.position.z + 0.5))
		var upper := Vector2i(ceili(bounds.end.x + 0.5), ceili(bounds.end.z + 0.5))
		_draw_outline(mesh, Rect2i(lower, upper - lower), roundi(socket.local_position.y), Color("ffd077"))
	var drawn_aisles := {}
	for bay in scene_root.get_meta("painted_parking_bays", []):
		if not bay.has("aisle"): continue
		var key := [bay.level, bay.aisle]
		if drawn_aisles.has(key): continue
		drawn_aisles[key] = true
		_draw_outline(mesh, bay.aisle, bay.level, Color("88e49e"))
	mesh.surface_end()
	var outlines := MeshInstance3D.new()
	outlines.mesh = mesh
	_authored_guides.add_child(outlines)

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
			var conflict := _paint_conflicts(record)
			var ok: bool = not record.is_empty() and conflict.is_empty() and session.add(record.surface, record.preset, Session.rectangle(record), int(record.get("heading", 0)))
			start_cell = null
			refresh("Draft updated." if ok else String(conflict.get("reason", session.last_error)))
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

func _paint_conflicts(record: Dictionary) -> Dictionary:
	if record.is_empty() or record.preset in ["protected", Session.PARKING_ROW]:
		return {}
	var surface: Dictionary = session.surfaces[record.surface]
	var surface_rect := Session.rectangle(surface)
	var rect := Session.rectangle(record)
	var inside := rect.intersection(surface_rect)
	var level := int(surface.level)
	var blocked: Array[Vector2i] = []
	var reasons := PackedStringArray()
	if not surface_rect.encloses(rect):
		reasons.append("Paint extends outside the selected floor.")
	if record.preset == "containers" and record.surface != "ground":
		reasons.append("Container paint requires the ground surface.")
	var connection := ParcelConnection.from_scene(host.displayed_parcel)
	var entrance := connection.world_span(_definition.size, Vector3i.ZERO, 0)
	for z in range(inside.position.y, inside.end.y):
		for x in range(inside.position.x, inside.end.x):
			var volume := AABB(Vector3(x - 0.49, level + 0.02, z - 0.49), Vector3(0.98, 0.95, 0.98))
			var reason := ""
			if Vector3i(x, level, z) in entrance:
				reason = "Paint covers the parcel entrance."
			elif session.has_protected_overlap(record.surface, volume) or _registered_protection.any(func(obstacle): return volume.intersects(obstacle)):
				reason = "Paint covers a protected cell."
			elif _aisle_obstacles.any(func(obstacle): return volume.intersects(obstacle)):
				reason = "Paint covers a registered parking aisle."
			elif _fixed_obstacles.any(func(obstacle): return volume.intersects(obstacle)):
				reason = "Paint overlaps a solid on this floor."
			if not reason.is_empty():
				blocked.append(Vector2i(x, z))
				if not reasons.has(reason):
					reasons.append(reason)
	return {} if reasons.is_empty() else {"reason": " ".join(reasons), "cells": blocked, "level": level, "rect": inside}

func refresh(message := "") -> void:
	clear_preview()
	if is_instance_valid(overlay): overlay.free()
	overlay = Node3D.new()
	host.add_child(overlay)
	overlay.visible = is_visible_in_tree()
	var fields: Array = session.fields.duplicate()
	var provisional := {}
	var conflict := {}
	if start_cell != null and drag_cell != null:
		provisional = _drag_record(drag_cell)
		conflict = _paint_conflicts(provisional)
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
	if not conflict.is_empty():
		_draw_paint_conflicts(conflict)
		message = conflict.reason
	var bays: Array[Dictionary] = session.parking_bays(_source_sockets, _fixed_obstacles, provisional if provisional.get("preset") == Session.PARKING_ROW else {}, start_cell == null)
	var fitting := _draw_bays(bays)
	_update_tools(provisional)
	_draw_aisle_arrow()
	status.text = message
	fit_feedback.text = ""
	if not bays.is_empty():
		if not status.text.is_empty(): status.text += "\n"
		status.text += "%d bays fit · %d rejected. %d authored sockets on this parcel." % [fitting, bays.size() - fitting, _source_sockets.size()]
		if bays.any(func(bay): return bay.inferred):
			status.text += " Row inferred from paint."
		var rejected: Array = bays.filter(func(bay): return not bay.reason.is_empty())
		if not rejected.is_empty(): status.text += " First rejection: %s." % rejected[0].reason
	if session.fields.any(func(field): return field.preset == "containers") or provisional.get("preset") == "containers":
		var template := Containers.Library.create(Containers.ASSET)
		var report := Containers.inspect(session, _definition, host.displayed_parcel, _source_sockets, _fixed_obstacles, template, provisional)
		template.free()
		_draw_container_fit(report)
		fit_feedback.text = _container_fit_text(report)
		fit_feedback.tooltip_text = fit_feedback.text

func _container_fit_text(report: Dictionary) -> String:
	var message := "Containers · %d positions fit." % report.accepted.size()
	for reason in report.causes:
		message += " %s (%d)." % [reason, report.causes[reason]]
	if report.limit_reached:
		message += " Four-position authoring limit reached."
	return message

func _draw_container_fit(report: Dictionary) -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	if report.accepted.is_empty() and report.rejected.is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for candidate in report.accepted:
		_draw_outline(mesh, candidate.rect, 0, Color("ffd077"))
	for candidate in report.rejected:
		_draw_outline(mesh, candidate.rect, 0, Color("ff626b"))
	mesh.surface_end()
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = host.displayed_parcel.position
	overlay.add_child(visual)

func _draw_paint_conflicts(conflict: Dictionary) -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	var color := Color("ff626b")
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for cell: Vector2i in conflict.cells:
		_draw_outline(mesh, Rect2i(cell, Vector2i.ONE), conflict.level, color)
	if conflict.rect.has_area():
		_draw_outline(mesh, conflict.rect, conflict.level, color)
	else:
		_draw_outline(mesh, Rect2i(start_cell, Vector2i.ONE), conflict.level, color)
	mesh.surface_end()
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = host.displayed_parcel.position
	overlay.add_child(visual)

func preview() -> void:
	clear_preview()
	sync_draft_context()
	if session.fields.is_empty():
		preview_layout(false)
		return
	_runtime_preview = host.draft.preview_root(host.displayed_parcel)
	var map_seed := int(seed_input.value)
	var candidates := _source_sockets.duplicate()
	var row_candidates := {}
	for bay: Dictionary in host.displayed_parcel.get_meta("painted_parking_bays", []):
		var candidate := _vehicles.candidate(bay, map_seed, session.parcel_id)
		if not candidate.is_empty():
			row_candidates[candidate.socket_id] = candidate
	var draft_bays := {}
	for bay: Dictionary in session.parking_bays(_source_sockets, _fixed_obstacles, {}, true):
		if not bay.reason.is_empty(): continue
		var candidate := _vehicles.candidate(bay, map_seed, session.parcel_id)
		if not candidate.is_empty():
			row_candidates[candidate.socket_id] = candidate
			draft_bays[candidate.socket_id] = true
			candidates.append(candidate)
	var container_template: Node3D
	var container_ids := {}
	var container_report := {}
	if session.fields.any(func(field): return field.preset == "containers"):
		container_template = Containers.Library.create(Containers.ASSET)
		container_report = Containers.inspect(session, _definition, _runtime_preview, _source_sockets, _fixed_obstacles, container_template)
		for candidate in container_report.accepted:
			candidates.append(candidate)
			container_ids[candidate.socket_id] = candidate
	var choices: Array[Dictionary] = session.preview(candidates, map_seed, int(density.value), _fixed_obstacles)
	_definition.apply_population(_runtime_preview, choices)
	var row_count := 0
	var container_count := 0
	for choice in choices:
		if not draft_bays.has(choice.socket_id) and not container_ids.has(choice.socket_id):
			continue
		var candidate: Dictionary = row_candidates.get(choice.socket_id, container_ids.get(choice.socket_id, {}))
		if candidate.is_empty(): continue
		if not is_instance_valid(_row_preview):
			_row_preview = Node3D.new()
			_row_preview.name = "DraftPopulation"
			_runtime_preview.add_child(_row_preview)
		var template: Node3D = candidate.get("template", container_template)
		var occupant := template.duplicate() as Node3D
		occupant.name = String(choice.socket_id)
		occupant.position = candidate.local_position
		occupant.rotation.y = -(int(candidate.get("heading", 0)) + int(choice.yaw_turns)) * PI * 0.5
		_row_preview.add_child(occupant)
		if draft_bays.has(choice.socket_id):
			row_count += 1
		if container_ids.has(choice.socket_id):
			container_count += 1
	if container_template:
		container_template.free()
	_present_preview()
	_update_tools()
	var excluded := _source_sockets.filter(func(socket): return session.field_excluded_sockets.has(socket.socket_id)).size()
	status.text = "%d authored sockets + %d row bay%s occupied. %d of %d authored sockets excluded by permission or protection. %d left empty by occupancy, %d conflicts. Seed %d." % [choices.size() - row_count - container_count, row_count, "" if row_count == 1 else "s", excluded, _source_sockets.size(), session.occupancy_skips, session.conflict_count, map_seed]
	if not container_ids.is_empty() or session.fields.any(func(field): return field.preset == "containers"):
		status.text += "\nNew containers · %d of %d fitted positions occupied." % [container_count, container_ids.size()]
		fit_feedback.text = _container_fit_text(container_report)
	preview_context.text = "Combined draft preview · seed %d · %d occupied. Tactical bounds follow current objects. Export and registration are separate." % [map_seed, choices.size()]

func preview_registered() -> void:
	clear_preview()
	preview_layout(true)

func preview_layout(registered: bool) -> void:
	_registered_preview = registered
	var map_seed := int(seed_input.value)
	var scope := String(host.displayed_parcel.get_meta("population_preview_instance", "parcel_editor"))
	var scene_root: Node3D = null if registered else host.draft.preview_root(host.displayed_parcel)
	var resolved := Resolver._resolve_population(_definition, map_seed, {}, true, scope, scene_root)
	if resolved.has("error"):
		if scene_root: scene_root.free()
		preview_context.text = String(resolved.error)
		return
	if not registered:
		var sockets: Array[Dictionary] = _definition.population_sockets(scene_root)
		for choice in resolved.choices:
			var socket: Dictionary = sockets.filter(func(item): return item.socket_id == choice.socket_id)[0]
			var bounds := Session.socket_bounds_at_turn(socket, int(choice.get("yaw_turns", 0)))
			if _fixed_obstacles.any(func(other): return bounds.grow(-0.001).intersects(other)):
				scene_root.free()
				preview_context.text = "Draft population overlaps a fixed object at %s. Move the fixed object or paint a different population area." % choice.socket_id
				return
	_runtime_preview = _definition.instantiate() if registered else scene_root
	_definition.apply_population(_runtime_preview, resolved.choices)
	_present_preview()
	if registered:
		overlay.hide()
	status.text = "Seed %d · %d of %d placements occupied." % [map_seed, resolved.choices.size(), _source_sockets.size()]
	status.hide()
	preview_context.text = ("%s preview · " % ("Registered" if registered else "Combined draft")) + status.text + " Show guides restores your editor view."
	update_preview_controls()

func _present_preview() -> void:
	_runtime_preview.position = host.displayed_parcel.position
	host.add_child(_runtime_preview)
	host.displayed_parcel.hide()
	_authored_guides.hide()
	compiled_preview = FlatMapGenerator.generate(_definition.size.x, _definition.size.y, 1.0, int(seed_input.value))
	AuthoredSceneMapCompiler.compile(_runtime_preview, compiled_preview, 1.0)
	host.refresh_tactical_overlay(_runtime_preview)

func _next_seed() -> void:
	var registered := _registered_preview
	seed_input.value = posmod(int(seed_input.value) + 1, 2147483648)
	if registered:
		preview_registered()
	else:
		preview()

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
		if fits: fitting += 1
		var aisle_key := "%s/%s" % [bay.surface, bay.aisle]
		if not aisles.has(aisle_key):
			_draw_outline(mesh, bay.aisle, bay.level, Color("88e49e") if String(bay.aisle_issue).is_empty() else Color("fb6a62"))
			for cell in bay.aisle_conflicts:
				_draw_outline(mesh, cell, bay.level, Color("ff626b"))
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

func clear_preview() -> void:
	if is_instance_valid(_runtime_preview):
		_runtime_preview.free()
		status.show()
		host.displayed_parcel.show()
		_authored_guides.visible = host.population_toggle.button_pressed
		if is_instance_valid(overlay):
			overlay.visible = is_visible_in_tree()
		host.refresh_tactical_overlay(host.displayed_parcel)
	_registered_preview = false
	compiled_preview = null

func reset_preview() -> void:
	refresh("Painted guides and empty placements.")

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
	clear_preview()
	for record in host.draft.placements:
		var node := host.displayed_parcel.get_node_or_null(NodePath(record.path)) as Node3D
		if node and not record.get("removed", false):
			var issue: String = host._validate_visual_pose(node)
			if not issue.is_empty():
				status.text = "Export rejected at %s · %s" % [record.path, issue]
				return false
	var source = host.Catalog.get_definition(host.displayed_parcel_id)
	var result := SceneExport.build(source, session, _vehicles, host.draft)
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
		status.text = "Could not save population scene: %s" % error_string(error)
		return false
	status.text = "Exported %d parking bays and %d container positions to %s" % [result.bay_count, result.container_count, ProjectSettings.globalize_path(destination)]
	export_folder_button.set_meta("folder", ProjectSettings.globalize_path(destination.get_base_dir()))
	export_folder_button.disabled = false
	preview_context.text = "Scene exported. Review it in Godot, then register its new ID and revision in AuthoredParcelCatalog. Saved drafts remain available."
	return true
