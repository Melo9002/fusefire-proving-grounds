extends VBoxContainer
## Small editor-only UI; field data and persistence live in PopulationFieldDraft.
const Session = preload("res://tools/parcel_editor/population_field_draft.gd")
var session = Session.new()
var surface_picker: OptionButton
var preset_picker: OptionButton
var tool_picker: OptionButton
var seed_input: SpinBox
var density: SpinBox
var status: Label
var host: Node3D
var overlay: Node3D
var start_cell: Variant = null

func setup(editor: Node3D) -> void:
	host = editor
	var title := Label.new()
	title.text = "POPULATION FIELDS / DRAFT"
	add_child(title)
	surface_picker = OptionButton.new()
	add_child(surface_picker)
	preset_picker = OptionButton.new()
	for preset in Session.PRESETS:
		preset_picker.add_item(preset.capitalize())
		preset_picker.set_item_metadata(preset_picker.item_count - 1, preset)
	add_child(preset_picker)
	tool_picker = OptionButton.new()
	for text in ["Inspect / camera", "Draw field (LMB drag)", "Erase field (LMB click)"]:
		tool_picker.add_item(text)
	tool_picker.item_selected.connect(func(_index): start_cell = null)
	add_child(tool_picker)
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
	density.suffix = "% occupied"
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

func begin(definition, scene_root: Node3D) -> void:
	session.begin(definition, scene_root)
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
	refresh("Choose a surface and preset, then draw. Preview uses existing authored sockets only.")

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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var cell: Variant = cell_at(event.position)
		if event.pressed:
			if tool_picker.selected == 2 and cell != null:
				session.erase_at(surface_id(), cell)
				refresh()
			else:
				start_cell = cell
		elif start_cell != null and cell != null:
			var lower: Vector2i = Vector2i(mini(start_cell.x, cell.x), mini(start_cell.y, cell.y))
			var extent: Vector2i = Vector2i(absi(cell.x - start_cell.x) + 1, absi(cell.y - start_cell.y) + 1)
			var ok: bool = session.add(surface_id(), String(preset_picker.get_selected_metadata()), Rect2i(lower, extent))
			refresh("Field added." if ok else session.last_error)
			start_cell = null
		return true
	return false

func refresh(message := "") -> void:
	if is_instance_valid(overlay): overlay.free()
	overlay = Node3D.new()
	host.add_child(overlay)
	for field: Dictionary in session.fields:
		var rect := Session.rectangle(field)
		var box := BoxMesh.new()
		box.size = Vector3(rect.size.x, 0.025, rect.size.y)
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1, 0.3, 0.2, 0.32) if field.preset == "protected" else Color(0.15, 0.8, 1, 0.28)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		box.material = material
		var visual := MeshInstance3D.new()
		visual.mesh = box
		visual.position = host.displayed_parcel.position + Vector3(rect.position.x + (rect.size.x - 1) * 0.5, session.surfaces[field.surface].level + 0.07, rect.position.y + (rect.size.y - 1) * 0.5)
		overlay.add_child(visual)
	status.text = "%d fields · cyan permitted / red protected\n%s" % [session.fields.size(), message]

func preview() -> void:
	if host.draft.dirty:
		status.text = "Preview requires source transforms. Reload the parcel after saving your visual draft."
		return
	var definition = host.Catalog.get_definition(host.displayed_parcel_id)
	var choices: Array[Dictionary] = session.preview(definition.population_sockets(), int(seed_input.value), int(density.value))
	var by_id := {}
	for choice in choices: by_id[choice.socket_id] = choice
	for node in host.displayed_parcel.find_children("*", "Node3D", true, false):
		if not node.has_meta("population_socket_id"): continue
		var id: StringName = node.get_meta("population_socket_id")
		node.visible = by_id.has(id)
		if not node.has_meta("field_preview_base_yaw"): node.set_meta("field_preview_base_yaw", node.rotation.y)
		node.rotation.y = float(node.get_meta("field_preview_base_yaw")) - int(by_id.get(id, {}).get("yaw_turns", 0)) * PI * 0.5
	status.text = "%d authored sockets accepted. Empty fields need compatible authored sockets. Draft preview only; mission/count certification is pending." % choices.size()

func reset_preview() -> void:
	host.set_population_visible(true)
	for node in host.displayed_parcel.find_children("*", "Node3D", true, false):
		if node.has_meta("field_preview_base_yaw"): node.rotation.y = node.get_meta("field_preview_base_yaw")
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
