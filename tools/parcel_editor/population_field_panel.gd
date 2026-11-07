extends VBoxContainer
## Small editor-only UI; field data and persistence live in PopulationFieldDraft.
const Session = preload("res://tools/parcel_editor/population_field_draft.gd")
const ParkingReference = preload("res://art/environments/authored/parcels/industrial_office_parking.tscn")
const AssetPlacement = preload("res://presentation/environment_asset_placement.gd")
var session = Session.new()
var surface_picker: OptionButton
var preset_picker: OptionButton
var tool_picker: OptionButton
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
var _parking_reference: Node3D
var _vehicle_templates: Array[Dictionary] = []
var _row_preview: Node3D
var _previewing := false
var _preview_ids := {}

func setup(editor: Node3D) -> void:
	host = editor
	var title := Label.new()
	title.text = "POPULATION FIELDS / DRAFT"
	add_child(title)
	surface_picker = OptionButton.new()
	surface_picker.item_selected.connect(func(_index):
		start_cell = null
		refresh())
	add_child(surface_picker)
	preset_picker = OptionButton.new()
	for preset in Session.PRESETS:
		preset_picker.add_item(preset.capitalize())
		preset_picker.set_item_metadata(preset_picker.item_count - 1, preset)
	add_child(preset_picker)
	tool_picker = OptionButton.new()
	for text in ["Inspect / camera", "Draw field (LMB drag)", "Erase field or row (LMB click)", "Draw parking row (LMB drag)"]:
		tool_picker.add_item(text)
	tool_picker.item_selected.connect(func(_index):
		start_cell = null
		heading_picker.visible = tool_picker.selected == 3
		refresh())
	add_child(tool_picker)
	heading_picker = OptionButton.new()
	for label in ["Aisle toward +Z", "Aisle toward −X", "Aisle toward −Z", "Aisle toward +X"]:
		heading_picker.add_item(label)
	heading_picker.item_selected.connect(func(_index):
		start_cell = null
		refresh())
	heading_picker.hide()
	add_child(heading_picker)
	var options := VBoxContainer.new()
	seed_input = SpinBox.new()
	seed_input.max_value = 2147483647
	seed_input.value = 17
	seed_input.prefix = "Seed "
	seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_child(seed_input)
	density = SpinBox.new()
	density.max_value = 100
	density.value = 65
	density.suffix = "% of eligible bays"
	density.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_child(density)
	add_child(options)
	var actions := HBoxContainer.new()
	for spec in [["Preview", preview], ["Reset", reset_preview], ["Undo", undo], ["Redo", redo]]:
		var button := Button.new()
		button.text = spec[0]
		button.pressed.connect(spec[1])
		actions.add_child(button)
	add_child(actions)
	var files := HBoxContainer.new()
	for spec in [["Save fields", save_fields], ["Load fields", load_fields]]:
		var button := Button.new()
		button.text = spec[0]
		button.pressed.connect(spec[1])
		files.add_child(button)
	add_child(files)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	host.population_toggle.toggled.connect(_apply_preview_visibility)

func begin(definition, scene_root: Node3D) -> void:
	session.begin(definition, scene_root)
	_source_sockets = definition.population_sockets(scene_root)
	_fixed_obstacles = definition.fixed_population_obstacles(scene_root)
	# Use the authored deck's known slab thickness for clearance under a floor.
	for id in session.surfaces:
		var surface: Dictionary = session.surfaces[id]
		if surface.level > 0:
			var rect := Session.rectangle(surface)
			_fixed_obstacles.append(AABB(Vector3(rect.position.x - 0.5, surface.level - 0.22, rect.position.y - 0.5), Vector3(rect.size.x, 0.22, rect.size.y)))
	start_cell = null
	surface_picker.clear()
	seed_input.value = 17
	density.value = 65
	var ids: Array = session.surfaces.keys()
	ids.sort()
	for id in ids:
		surface_picker.add_item("%s · level %d" % [id, session.surfaces[id].level])
		surface_picker.set_item_metadata(surface_picker.item_count - 1, id)
	tool_picker.select(0)
	heading_picker.hide()
	refresh("Paint parking permission, then draw a row along the edge facing its aisle.")

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
	if tool_picker.selected == 0: return false
	if event is InputEventMouseMotion and start_cell != null:
		drag_cell = cell_at(event.position)
		refresh("Release to commit the previewed rectangle.")
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var cell: Variant = cell_at(event.position)
		if event.pressed:
			if tool_picker.selected == 2 and cell != null:
				session.erase_at(surface_id(), cell)
				refresh()
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
	if tool_picker.selected == 3:
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
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1, 0.3, 0.2, 0.32) if protected else Color(0.15, 0.8, 1, 0.28)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		if not cells.values().has(protected): continue
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
		for cell: Vector3i in cells:
			if cells[cell] != protected: continue
			for offset in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]:
				mesh.surface_add_vertex(Vector3(cell) + offset + Vector3.UP * 0.07)
		mesh.surface_end()
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.position = host.displayed_parcel.position
		overlay.add_child(visual)
	var bays: Array[Dictionary] = session.parking_bays(_source_sockets, _fixed_obstacles, provisional if provisional.get("preset") == Session.PARKING_ROW else {})
	var fitting := _draw_bays(bays)
	status.text = "%d draft areas · cyan permitted / red protected\n%s" % [session.fields.size(), message]
	if not bays.is_empty():
		status.text += "\n%d bays fit · %d rejected. Gold: bay · green: aisle." % [fitting, bays.size() - fitting]
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
		var candidate := _vehicle_candidate(bay, map_seed)
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
	status.text = "%d authored sockets + %d row bays occupied. %d overlap conflicts rejected. Draft preview only." % [choices.size() - row_count, row_count, session.conflict_count]

func _draw_bays(bays: Array[Dictionary]) -> int:
	if bays.is_empty(): return 0
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
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

func _vehicle_candidate(bay: Dictionary, map_seed: int) -> Dictionary:
	if not is_instance_valid(_parking_reference):
		_parking_reference = ParkingReference.instantiate()
		for node_name in ["SedanWest", "SuvMid", "TaxiEast"]:
			var vehicle := _parking_reference.get_node(node_name) as Node3D
			var bounds := AssetPlacement.mesh_bounds(vehicle, vehicle.transform.affine_inverse())
			var solid := vehicle.get_node("TacticalVolume") as Node3D
			var dimensions: Vector3 = solid.get_meta("solid_size")
			bounds = bounds.merge(solid.transform * AABB(-dimensions * 0.5, dimensions))
			if maxf(absf(bounds.position.x), absf(bounds.end.x)) > Session.BAY_WIDTH * 0.5 or maxf(absf(bounds.position.z), absf(bounds.end.z)) > Session.BAY_DEPTH * 0.5:
				continue
			if bounds.position.y < -0.05 or bounds.end.y > Session.PARKING_HEADROOM:
				continue
			_vehicle_templates.append({"template": vehicle, "asset_id": String(vehicle.get_meta("asset_id")), "bounds": bounds})
	if _vehicle_templates.is_empty(): return {}
	var key := JSON.stringify([map_seed, session.parcel_id, bay.id, "parking_vehicle_v1"])
	var index := posmod(key.sha256_text().substr(0, 8).hex_to_int(), _vehicle_templates.size())
	var option: Dictionary = _vehicle_templates[index]
	var rect: Rect2i = bay.rect
	var pivot := Vector3(rect.position.x + (rect.size.x - 1) * 0.5, bay.level, rect.position.y + (rect.size.y - 1) * 0.5)
	var transform := Transform3D(Basis(Vector3.UP, -int(bay.heading) * PI * 0.5), pivot)
	return {"socket_id": StringName(bay.id), "surface_id": bay.surface, "asset_id": option.asset_id, "allowed_yaw_turns": PackedInt32Array([0, 2]), "local_position": pivot, "local_bounds": transform * option.bounds, "heading": bay.heading, "template": option.template}

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

func _exit_tree() -> void:
	if is_instance_valid(_parking_reference): _parking_reference.free()

func reset_preview() -> void:
	refresh("Source population restored.")

func undo() -> void:
	session.undo()
	reset_preview()

func redo() -> void:
	session.redo()
	reset_preview()

func save_fields() -> void:
	session.preview_seed = int(seed_input.value)
	session.occupancy = int(density.value)
	refresh("Saved " + session.path() if session.save_to(session.path()) else session.last_error)

func load_fields() -> void:
	if session.load_from(session.path()):
		seed_input.value = session.preview_seed
		density.value = session.occupancy
		reset_preview()
	else: status.text = session.last_error
