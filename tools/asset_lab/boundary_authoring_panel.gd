extends VBoxContainer
## Candidate geometry is deliberately isolated from runtime MapData and calibration writes.
const Baker = preload("res://tools/asset_lab/mesh_boundary_baker.gd")
var source: Node3D
var asset_id := ""
var dependency: Dictionary
var parts: Array = []
var drafts := {}
var history: Array = []
var selected_part := -1
var overlay: Node3D
var part_list: ItemList
var part_name: LineEdit
var role: OptionButton
var limits: Array[SpinBox] = []
var status: Label
var export_button: Button
var file_dialog: FileDialog
var changing := false
var opening := false
var footer: VBoxContainer

func _ready() -> void:
	var help := Label.new()
	help.text = "Clip a part → Fit mesh → choose role → Export\nGreen box: clip region. Yellow: fitted boundary.\nConvex hulls can close openings. Exported drafts do not change gameplay."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	_button("Use whole model bounds", reset_region)
	for axis in ["X", "Y", "Z"]:
		var row := HBoxContainer.new()
		add_child(row)
		var label := Label.new()
		label.text = axis + " min / max"
		row.add_child(label)
		for _end in 2:
			var spin := SpinBox.new()
			spin.min_value = -1000
			spin.max_value = 1000
			spin.step = 0.05
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(spin)
			limits.append(spin)
			spin.value_changed.connect(func(_value): _region_changed())
	part_name = LineEdit.new()
	part_name.text = "Part1"
	part_name.placeholder_text = "Part name (Cargo, Cab, Wall…)"
	add_child(part_name)
	part_name.text_changed.connect(func(_text): _region_changed())
	role = OptionButton.new()
	for label in ["Choose tactical role", "Solid: movement + shots + cover", "Movement only", "Shot blocker only", "Low cover", "Visual / no tactical effect"]: role.add_item(label)
	add_child(role)
	role.item_selected.connect(_change_role)
	_action_row(["Fit mesh / replace", "New part"], [bake_part, new_part])
	part_list = ItemList.new()
	part_list.custom_minimum_size.y = 72
	part_list.item_selected.connect(_select_part)
	add_child(part_list)
	_action_row(["Remove part", "Undo"], [remove_part, undo])
	footer = VBoxContainer.new()
	add_child(footer)
	var exports := _action_row(["Export draft…", "Open draft…"], [choose_export, func(): _choose_file(true)], footer)
	export_button = exports.get_child(0)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(status)
	_refresh()

func _button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(action)
	add_child(button)
	return button

func _action_row(labels: Array, actions: Array, target: Node = null) -> HBoxContainer:
	var row := HBoxContainer.new()
	(target if target else self).add_child(row)
	for index in labels.size():
		var button := Button.new()
		button.text = labels[index]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(actions[index])
		row.add_child(button)
	return row

func bind_source(model: Node3D, id: String, placement: Dictionary) -> void:
	# Rebuilding view overlays preserves a draft; changing model/calibration selects
	# its own in-memory draft rather than relabeling stale shapes as current.
	if not asset_id.is_empty(): drafts[JSON.stringify(dependency)] = {"parts": parts, "history": history}
	source = model
	asset_id = id
	var source_path := "res://art/environments/kenney/%s/models/%s.glb" % [id.get_slice("/", 0), id.get_slice("/", 1)]
	dependency = {"asset_id": id, "geometry_sha256": FileAccess.get_sha256(source_path), "import_sha256": FileAccess.get_sha256(source_path + ".import"), "placement": placement}
	var draft: Dictionary = drafts.get(JSON.stringify(dependency), {"parts": [], "history": []})
	parts = draft.parts
	history = draft.history
	selected_part = -1
	reset_region()
	_refresh()

func reset_region() -> void:
	if not is_instance_valid(source): return
	var bounds := Baker.source_bounds(source)
	for axis in 3:
		limits[axis * 2].value = floorf(bounds.position[axis] / 0.05) * 0.05
		limits[axis * 2 + 1].value = ceilf(bounds.end[axis] / 0.05) * 0.05

func region() -> AABB:
	var start := Vector3(limits[0].value, limits[2].value, limits[4].value)
	return AABB(start, Vector3(limits[1].value, limits[3].value, limits[5].value) - start)

func bake_part() -> void:
	if not is_instance_valid(source):
		status.text = "Select one asset; assembly and duplicate views cannot bake a profile."
		return
	if parts.size() >= 32 and selected_part < 0:
		status.text = "32-part authoring budget reached."
		return
	var name_value := part_name.text.strip_edges().validate_node_name()
	if name_value.is_empty():
		status.text = "Give the part a name."
		return
	for index in parts.size():
		if index != selected_part and parts[index].name == name_value:
			status.text = "Part names must be unique."
			return
	var candidate := Baker.bake(source, region())
	if not candidate.error.is_empty():
		status.text = candidate.error
		return
	_remember()
	candidate.name = name_value
	candidate.role = Baker.ROLES[role.selected]
	if selected_part < 0:
		parts.append(candidate)
		selected_part = parts.size() - 1
	else: parts[selected_part] = candidate
	_refresh()
	status.text = "Fitted %d source points. Inspect the hull: openings inside a convex hull are closed." % candidate.points.size()

func _remember() -> void:
	history.append(parts.duplicate(true))
	if history.size() > 32: history.pop_front()

func _change_role(index: int) -> void:
	if changing or selected_part < 0: return
	_remember()
	parts[selected_part].role = Baker.ROLES[index]
	_refresh()

func _select_part(index: int) -> void:
	selected_part = index
	changing = true
	part_name.text = parts[index].name
	role.select(Baker.ROLES.find(parts[index].role))
	var bounds: AABB = parts[index].region
	for axis in 3:
		limits[axis * 2].value = bounds.position[axis]
		limits[axis * 2 + 1].value = bounds.end[axis]
	changing = false
	_draw()

func new_part() -> void:
	selected_part = -1
	part_list.deselect_all()
	part_name.text = "Part%d" % (parts.size() + 1)
	role.select(0)
	_refresh()

func remove_part() -> void:
	if selected_part < 0: return
	_remember()
	parts.remove_at(selected_part)
	selected_part = -1
	_refresh()

func undo() -> void:
	if history.is_empty(): return
	parts = history.pop_back()
	selected_part = -1
	_refresh()

func _refresh() -> void:
	part_list.clear()
	for part in parts: part_list.add_item("%s · %s" % [part.name, part.role])
	if selected_part >= 0: part_list.select(selected_part)
	export_button.disabled = parts.is_empty() or not is_instance_valid(source) or _pending_edits() or parts.any(func(part): return part.role == "unclassified")
	var unclassified := parts.filter(func(part): return part.role == "unclassified").size()
	status.text = "%d candidate parts · %d need a role before export." % [parts.size(), unclassified] if unclassified > 0 else "%d candidate parts ready for export · unregistered authoring draft." % parts.size()
	_draw()

func _region_changed() -> void:
	if changing or limits.size() != 6 or not is_instance_valid(status): return
	if selected_part >= 0:
		var pending := _pending_edits()
		export_button.disabled = pending or parts.any(func(part): return part.role == "unclassified")
		if pending: status.text = "Part changed: click Fit mesh to update it before export."
		else: status.text = "Selected fitted part is current · unregistered authoring draft."
	_draw()

func _pending_edits() -> bool:
	if selected_part < 0: return false
	var previous: AABB = parts[selected_part].region
	return not previous.position.is_equal_approx(region().position) or not previous.size.is_equal_approx(region().size) or part_name.text != parts[selected_part].name

func _draw() -> void:
	if is_instance_valid(overlay): overlay.free()
	if not is_instance_valid(source): return
	overlay = Node3D.new()
	overlay.set_meta("boundary_preview", true)
	source.add_child(overlay)
	overlay.transform = source.transform.affine_inverse()
	if region().has_volume():
		var clip_box := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = region().size
		var fill := StandardMaterial3D.new()
		fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fill.no_depth_test = true
		fill.albedo_color = Color(0.2, 1, 0.4, 0.08)
		clip_box.mesh = box
		clip_box.material_override = fill
		clip_box.position = region().get_center()
		clip_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		overlay.add_child(clip_box)
	for index in parts.size():
		var mesh := MeshInstance3D.new()
		var hull: Mesh = parts[index].shape.get_debug_mesh()
		var wire := ImmediateMesh.new()
		var faces := hull.get_faces()
		wire.surface_begin(Mesh.PRIMITIVE_LINES)
		for face in range(0, faces.size(), 3):
			for edge in 3:
				wire.surface_add_vertex(faces[face + edge])
				wire.surface_add_vertex(faces[face + (edge + 1) % 3])
		wire.surface_end()
		mesh.mesh = wire
		var tint := StandardMaterial3D.new()
		tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tint.no_depth_test = true
		tint.albedo_color = Color("ffe072") if index == selected_part else Color("55dcec")
		mesh.material_override = tint
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		overlay.add_child(mesh)

func choose_export() -> void:
	_choose_file(false)

func _choose_file(opening_file: bool) -> void:
	if not file_dialog:
		file_dialog = FileDialog.new()
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		file_dialog.filters = PackedStringArray(["*.tscn ; Godot boundary draft"])
		file_dialog.file_selected.connect(func(path: String):
			if opening: open_profile(path)
			else: save_profile(path))
		add_child(file_dialog)
	opening = opening_file
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if opening else FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.current_file = asset_id.replace("/", "_") + "_boundaries.tscn"
	file_dialog.popup_centered_ratio(0.7)

func save_profile(path: String) -> void:
	if _pending_edits():
		status.text = "Fit the changed part before exporting."
		return
	if not is_instance_valid(source):
		status.text = "Select a single source asset before export."
		return
	var source_path := "res://art/environments/kenney/%s/models/%s.glb" % [asset_id.get_slice("/", 0), asset_id.get_slice("/", 1)]
	if FileAccess.get_sha256(source_path) != dependency.geometry_sha256 or FileAccess.get_sha256(source_path + ".import") != dependency.import_sha256:
		status.text = "Source geometry/import settings changed. Reload the asset and re-bake."
		return
	var result := Baker.export_profile(parts, asset_id, dependency, path)
	status.text = "Exported %s\nUnregistered authoring draft; runtime remains unchanged." % path if result == OK else "Export failed: " + error_string(result)

func open_profile(path: String) -> void:
	var result := Baker.read_profile(path, dependency)
	if not result.error.is_empty():
		status.text = result.error + " Current draft preserved."
		return
	_remember()
	parts = result.parts
	selected_part = -1
	_refresh()
	status.text = "Opened %s\nUnregistered authoring draft." % path
