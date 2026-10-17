extends Control
## Standalone presentation sandbox; no battle, grid singleton, or combat state.
const Catalog = preload("res://tools/asset_lab/asset_catalog.gd")
const Placement = preload("res://presentation/environment_asset_placement.gd")
const PlacementConventions = preload("res://tools/asset_lab/asset_placement_conventions.gd")
const OrbitCamera = preload("res://tools/inspection_orbit_camera.gd")
const MIRA_REFERENCE_HEIGHT := 1.64
const MIRA_RUNTIME_HEIGHT := 1.60
@export_file("*.json") var calibration_path := Catalog.DATA_PATH
var world: Node3D
var content: Node3D
var overlays: Node3D
var viewport: SubViewport
var camera: Camera3D
var asset_list: ItemList
var search: LineEdit
var family_filter: OptionButton
var review_filter: OptionButton
var semantic_filter: OptionButton
var info: Label
var mode: OptionButton
var anchor: OptionButton
var factor: SpinBox
var angle: SpinBox
var x_offset: SpinBox
var y_offset: SpinBox
var z_offset: SpinBox
var pitch: SpinBox
var duplicate_piece: CheckBox
var bounds_toggle: CheckBox
var mira_toggle: CheckBox
var ids: Array[String] = []
var selected := "factory_kit/structure-doorway-wide"
var changing := false
var orbit: RefCounted
var current_bounds := AABB()
var display_bounds := AABB()
var native_bounds := AABB()
var comparison: Node3D
var copy_button: Button
var reset_button: Button
var save_button: Button
var reviewed_toggle: CheckBox
var category_label: Label
var category_scale: SpinBox
var fallback_scale: SpinBox
var save_status: Label
var classification: OptionButton
var footprint_x: SpinBox
var footprint_z: SpinBox
var calibration_notes: TextEdit
var dimensions_label: Label
var calibration_data: Dictionary
var bounds_data: Dictionary
var write_controls: Array[Control] = []

func _ready() -> void:
	calibration_data = Catalog.load_calibrations(calibration_path)
	bounds_data = PlacementConventions.load_bounds()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 365
	row.add_child(scroll)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size.x = 345
	scroll.add_child(panel)
	var title := Label.new()
	title.text = "FUSEFIRE / ASSET LAB\nVisual calibration — no tactical occupancy"
	panel.add_child(title)
	mode = OptionButton.new()
	for label in ["Individual asset", "Assembly: road + sidewalk", "Assembly: wall + entrance", "Assembly: loading / machinery", "Assembly: space floor + wall"]:
		mode.add_item(label)
	panel.add_child(mode)
	mode.item_selected.connect(func(_i): rebuild(true))
	family_filter = OptionButton.new()
	family_filter.add_item("All asset families")
	for label in ["City Kit Industrial", "City Kit Roads", "Factory Kit", "Modular Space Kit"]:
		family_filter.add_item(label)
	panel.add_child(family_filter)
	review_filter = OptionButton.new()
	for label in ["All review states", "Unreviewed only", "Reviewed only"]:
		review_filter.add_item(label)
	panel.add_child(review_filter)
	semantic_filter = OptionButton.new()
	semantic_filter.add_item("All semantic categories")
	var semantic_categories: Array[String] = []
	for id in Catalog.all_ids():
		var semantic := Catalog.semantic_category(id)
		if semantic not in semantic_categories:
			semantic_categories.append(semantic)
	semantic_categories.sort()
	for semantic in semantic_categories:
		semantic_filter.add_item(semantic.replace("_", " ").capitalize())
		semantic_filter.set_item_metadata(semantic_filter.item_count - 1, semantic)
	panel.add_child(semantic_filter)
	search = LineEdit.new()
	search.placeholder_text = "Search pack/model (all 315)"
	panel.add_child(search)
	asset_list = ItemList.new()
	asset_list.custom_minimum_size.y = 220
	panel.add_child(asset_list)
	search.text_changed.connect(_filter)
	family_filter.item_selected.connect(func(_i): _filter(search.text))
	review_filter.item_selected.connect(func(_i): _filter(search.text))
	semantic_filter.item_selected.connect(func(_i): _filter(search.text))
	asset_list.item_selected.connect(func(i): select_asset(asset_list.get_item_metadata(i)))
	_filter("")
	factor = _number(panel, "Uniform scale", 0.01, 50, 0.01, Catalog.DEFAULT_SCALE)
	var scale_buttons := HBoxContainer.new()
	panel.add_child(scale_buttons)
	for entry in [["−1", -1.0], ["−0.1", -0.1], ["+0.1", 0.1], ["+1", 1.0]]:
		var scale_button := Button.new()
		scale_button.text = entry[0]
		scale_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scale_button.pressed.connect(func(): factor.value = clampf(factor.value + entry[1], factor.min_value, factor.max_value))
		scale_buttons.add_child(scale_button)
	angle = _number(panel, "Yaw degrees (Y-up)", -360, 360, 90, 0)
	anchor = OptionButton.new()
	for label in ["Anchor: floor center", "Anchor: source origin", "Anchor: top center"]:
		anchor.add_item(label)
	panel.add_child(anchor)
	anchor.item_selected.connect(func(_i): rebuild())
	x_offset = _number(panel, "Anchor X (0.5 snap)", -30, 30, 0.5, 0)
	y_offset = _number(panel, "Anchor Y", -10, 20, 0.1, 0)
	z_offset = _number(panel, "Anchor Z (0.5 snap)", -30, 30, 0.5, 0)
	pitch = _number(panel, "Neighbor pitch X", 0.1, 20, 0.1, 1)
	duplicate_piece = _check(panel, "Neighbor / seam comparison", false)
	bounds_toggle = _check(panel, "Bounds + pivot axes + anchor", true)
	mira_toggle = _check(panel, "MIRA reference (runtime visual)", true)
	var camera_help := Label.new()
	camera_help.text = "VIEW  RMB orbit · MMB pan · wheel zoom · F frame\n1 front · 3 side · 7 top · Q/E rotate asset"
	camera_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(camera_help)
	var camera_buttons := HBoxContainer.new()
	panel.add_child(camera_buttons)
	for label in ["Frame", "Front", "Side", "Top"]:
		var view_button := Button.new()
		view_button.text = label
		camera_buttons.add_child(view_button)
		if label == "Frame": view_button.pressed.connect(_frame_camera)
		elif label == "Front": view_button.pressed.connect(func(): orbit.set_view(0.0, 0.12))
		elif label == "Side": view_button.pressed.connect(func(): orbit.set_view(PI / 2.0, 0.12))
		else: view_button.pressed.connect(func(): orbit.set_view(0.0, 1.5))
	reset_button = Button.new()
	reset_button.text = "Reset to catalog calibration / frame"
	reset_button.pressed.connect(func(): select_asset(selected))
	panel.add_child(reset_button)
	copy_button = Button.new()
	copy_button.text = "Copy current calibration JSON"
	copy_button.pressed.connect(func(): DisplayServer.clipboard_set(JSON.stringify(calibration_record(), "\t")))
	panel.add_child(copy_button)
	save_button = Button.new()
	save_button.text = "Save calibration"
	save_button.pressed.connect(_save_override)
	panel.add_child(save_button)
	write_controls.append(save_button)
	var clear_button := Button.new()
	clear_button.text = "Reset to inherited preset"
	clear_button.pressed.connect(_clear_override)
	panel.add_child(clear_button)
	write_controls.append(clear_button)
	reviewed_toggle = CheckBox.new()
	reviewed_toggle.text = "Reviewed (saves current calibration)"
	reviewed_toggle.toggled.connect(_set_reviewed)
	panel.add_child(reviewed_toggle)
	write_controls.append(reviewed_toggle)
	classification = OptionButton.new()
	for label in ["Unclassified", "Structural module", "Ground module", "Entrance / connector", "Tactical obstacle", "Decorative prop"]:
		classification.add_item(label)
	panel.add_child(classification)
	classification.item_selected.connect(func(_i): rebuild())
	write_controls.append(classification)
	footprint_x = _number(panel, "Suggested footprint X (cells)", 0, 100, 1, 0)
	footprint_z = _number(panel, "Suggested footprint Z (cells)", 0, 100, 1, 0)
	write_controls.append(footprint_x)
	write_controls.append(footprint_z)
	calibration_notes = TextEdit.new()
	calibration_notes.placeholder_text = "Verified orientation, intended combinations, clearance, or scale notes"
	calibration_notes.custom_minimum_size.y = 72
	calibration_notes.text_changed.connect(_update_save_status)
	panel.add_child(calibration_notes)
	write_controls.append(calibration_notes)
	dimensions_label = Label.new()
	dimensions_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(dimensions_label)
	var next_button := Button.new()
	next_button.text = "Next unreviewed asset"
	next_button.pressed.connect(_next_unreviewed)
	panel.add_child(next_button)
	category_label = Label.new()
	panel.add_child(category_label)
	category_scale = _number(panel, "Category preset scale", 0.01, 50, 0.01, 1)
	write_controls.append(category_scale)
	var category_button := Button.new()
	category_button.text = "Save category scale preset"
	category_button.pressed.connect(_save_category_preset)
	panel.add_child(category_button)
	write_controls.append(category_button)
	fallback_scale = _number(panel, "General fallback scale", 0.01, 50, 0.01, float(calibration_data.fallback.scale))
	write_controls.append(fallback_scale)
	var fallback_button := Button.new()
	fallback_button.text = "Save general fallback"
	fallback_button.pressed.connect(_save_fallback)
	panel.add_child(fallback_button)
	write_controls.append(fallback_button)
	var reload_button := Button.new()
	reload_button.text = "Reload saved calibrations"
	reload_button.pressed.connect(_reload_calibrations)
	panel.add_child(reload_button)
	save_status = Label.new()
	save_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(save_status)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 335
	panel.add_child(info)
	var view := SubViewportContainer.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.stretch = true
	row.add_child(view)
	viewport = SubViewport.new()
	viewport.size = Vector2i(900, 800)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.add_child(viewport)
	view.gui_input.connect(_view_input)
	world = Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202b38")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	_box(world, Vector3(60, 0.05, 60), Vector3(0, -0.3, 0), Color("414b56"))
	var lines := PackedVector3Array()
	for i in range(-30, 31):
		lines.append_array([Vector3(i, -0.14, -30), Vector3(i, -0.14, 30), Vector3(-30, -0.14, i), Vector3(30, -0.14, i)])
	_lines(world, lines, Color("677888"))
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 48
	world.add_child(camera)
	orbit = OrbitCamera.new(camera)
	select_asset(selected)

func _number(panel: VBoxContainer, label: String, low: float, high: float, step: float, value: float) -> SpinBox:
	var row := HBoxContainer.new()
	panel.add_child(row)
	var text := Label.new()
	text.text = label
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var box := SpinBox.new()
	box.min_value = low
	box.max_value = high
	box.step = step
	box.value = value
	row.add_child(box)
	box.value_changed.connect(func(_v): rebuild())
	return box

func _check(panel: VBoxContainer, label: String, initial: bool) -> CheckBox:
	var check := CheckBox.new()
	check.text = label
	check.button_pressed = initial
	panel.add_child(check)
	check.toggled.connect(func(_v): rebuild())
	return check

func _filter(query: String) -> void:
	asset_list.clear()
	ids = Catalog.all_ids()
	var selected_pack: String = "" if family_filter.selected == 0 else Catalog.PACKS[family_filter.selected - 1]
	for id in ids:
		var reviewed: bool = id in calibration_data.get("reviewed", [])
		var review_matches: bool = review_filter.selected == 0 or (review_filter.selected == 1 and not reviewed) or (review_filter.selected == 2 and reviewed)
		var selected_semantic: String = "" if semantic_filter.selected == 0 else str(semantic_filter.get_item_metadata(semantic_filter.selected))
		var semantic_matches := selected_semantic.is_empty() or Catalog.semantic_category(id) == selected_semantic
		if review_matches and semantic_matches and (selected_pack.is_empty() or id.begins_with(selected_pack + "/")) and (query.is_empty() or query.to_lower() in id.to_lower()):
			var index := asset_list.add_item(("* " if Catalog.PROFILES.has(id) else "") + id)
			asset_list.set_item_metadata(index, id)
			asset_list.set_item_tooltip(index, id)

func select_asset(id: String) -> void:
	changing = true
	selected = id
	mode.select(0)
	var profile := Catalog.profile(id, calibration_data)
	factor.value = profile.scale
	angle.value = profile.yaw_degrees
	anchor.select(profile.anchor)
	var position: Array = profile.anchor_position
	x_offset.value = position[0]
	y_offset.value = position[1]
	z_offset.value = position[2]
	var category: String = profile.calibration_category
	category_label.text = "Semantic: %s\nScale group: %s" % [profile.semantic_category, category]
	category_scale.value = float(calibration_data.get("category_presets", {}).get(category, calibration_data.fallback).scale)
	fallback_scale.value = float(calibration_data.fallback.scale)
	reviewed_toggle.button_pressed = profile.reviewed
	classification.select(_classification_index(str(profile.get("classification", "unclassified"))))
	var suggested: Array = profile.get("suggested_footprint", [0, 0])
	footprint_x.value = float(suggested[0])
	footprint_z.value = float(suggested[1])
	calibration_notes.text = str(profile.get("calibration_notes", ""))
	for i in asset_list.item_count:
		if asset_list.get_item_metadata(i) == id:
			asset_list.select(i)
			asset_list.ensure_current_is_visible()
	changing = false
	rebuild(true)

func rebuild(frame := false) -> void:
	if changing or not is_instance_valid(world):
		return
	if is_instance_valid(content):
		content.free()
	if is_instance_valid(overlays):
		overlays.free()
	for control in [factor, angle, x_offset, y_offset, z_offset, pitch, footprint_x, footprint_z]:
		control.editable = mode.selected == 0
	anchor.disabled = mode.selected != 0
	duplicate_piece.disabled = mode.selected != 0
	copy_button.disabled = mode.selected != 0
	for control in write_controls:
		if control is BaseButton:
			control.disabled = mode.selected != 0
		elif control is SpinBox:
			control.editable = mode.selected == 0
		elif control is TextEdit:
			control.editable = mode.selected == 0
		elif control is OptionButton:
			control.disabled = mode.selected != 0
	content = Node3D.new()
	overlays = Node3D.new()
	world.add_child(content)
	world.add_child(overlays)
	if mode.selected == 0:
		var at := Vector3(x_offset.value, y_offset.value, z_offset.value)
		var piece := Placement.instantiate_calibrated(content, Catalog.path_for(selected), at, factor.value, deg_to_rad(angle.value), anchor.selected)
		native_bounds = piece.occlusion_bounds
		current_bounds = piece.transform * native_bounds
		if duplicate_piece.button_pressed:
			Placement.instantiate_calibrated(content, Catalog.path_for(selected), at + Vector3(pitch.value, 0, 0), factor.value, deg_to_rad(angle.value), anchor.selected)
		var p := Catalog.profile(selected, calibration_data)
		var convention := PlacementConventions.record(selected, calibration_data, bounds_data)
		info.text = "%s\n%s · %s · %s\n%s\nNative bounds: %s\nPlaced size: %s\nVisual envelope ceil X/Z: %d × %d (NOT occupancy)\n%s\n" % [selected, p.semantic_category, p.calibration_category, p.calibration_source, p.orientation, native_bounds, current_bounds.size, ceili(current_bounds.size.x - 0.0001), ceili(current_bounds.size.z - 0.0001), p.note]
		info.text += "Snap X/Z: %s · assembly pitch: %s\nTactical policy: %s · authored footprint: %s\n%s\n" % [convention.origin_snap, convention.assembly_pitch, convention.tactical_policy, convention.authored_tactical_footprint if not convention.authored_tactical_footprint.is_empty() else "none", convention.note]
		_axes(overlays, at, 0.65)
	else:
		_build_assembly(mode.selected)
		info.text = "Assembly %d — family calibration policy, authored origins.\nBounds are visual envelopes, not solids.\nIndividual controls apply only in asset mode.\n" % mode.selected
	current_bounds = Placement.mesh_bounds(content)
	display_bounds = current_bounds
	if mode.selected == 0:
		dimensions_label.text = "MEASURED\nNative: %.3f × %.3f × %.3f\nCalibrated: %.3f × %.3f × %.3f\nSuggested footprint is planning metadata; it does not change MapData." % [native_bounds.size.x, native_bounds.size.y, native_bounds.size.z, current_bounds.size.x, current_bounds.size.y, current_bounds.size.z]
	else:
		dimensions_label.text = "Assembly envelope: %.3f × %.3f × %.3f" % [current_bounds.size.x, current_bounds.size.y, current_bounds.size.z]
	if bounds_toggle.button_pressed:
		for piece in content.get_children():
			if piece is TacticalVisualOccluder:
				_bounds(overlays, piece.transform * piece.occlusion_bounds)
				_axes(overlays, piece.position, 0.45)
	else:
		for child in overlays.get_children():
			child.visible = false
	if mira_toggle.button_pressed:
		comparison = load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate()
		# Adapter scene is parented at y=-1 under units; use floor-space origin here.
		comparison.position = Vector3(current_bounds.end.x + 1.1, 0, current_bounds.get_center().z)
		comparison.scale = Vector3.ONE * (MIRA_REFERENCE_HEIGHT / MIRA_RUNTIME_HEIGHT)
		content.add_child(comparison)
		display_bounds = display_bounds.merge(Placement.mesh_bounds(comparison))
	info.text += "\nGrid = 1 world unit. Lab MIRA reference = %.2f m. Red +X / green +Y / blue +Z.\nRMB orbit · MMB pan · wheel zoom · F frame.\n* = additional orientation/anchor metadata; use the review filter for calibration progress.\nCopy exports the individual asset settings only." % MIRA_REFERENCE_HEIGHT
	if frame:
		_frame_camera()
	orbit.apply()
	_update_save_status()

func _build_assembly(index: int) -> void:
	match index:
		1:
			for x in [-9, 0, 9]:
				Catalog.place(content, "city_kit_roads/road-side", Vector3(x, -0.18, 0), 0, calibration_data)
				Catalog.place(content, "city_kit_roads/tile-low", Vector3(x, 0, -11.79), 0, calibration_data)
		2:
			Catalog.place(content, "factory_kit/structure-doorway-wide", Vector3.ZERO, 0, calibration_data)
			for x in [-2.5, -1.5, 1.5, 2.5]:
				Catalog.place(content, "factory_kit/structure-wall", Vector3(x, 0, 0), 0, calibration_data)
		3:
			Catalog.place(content, "city_kit_industrial/shipping-container-a", Vector3(-6, 0, -2), PI / 2, calibration_data)
			Catalog.place(content, "factory_kit/crane", Vector3(4, 0, -1), 0, calibration_data)
			Catalog.place(content, "factory_kit/machine", Vector3(-2, 0, 4), 0, calibration_data)
			for x in [1, 3]:
				_box(content, Vector3(2, 0.4, 1), Vector3(x, 0.2, 4), Color("555e68"))
				Catalog.place(content, "factory_kit/conveyor-long", Vector3(x, 0.4, 4), 0, calibration_data)
		4:
			for x in [-2, 2]:
				Catalog.place(content, "modular_space_kit/template-floor", Vector3(x, 0, 0), 0, calibration_data)
				Catalog.place(content, "modular_space_kit/template-wall", Vector3(x, 0, -2), 0, calibration_data)

func _override_record() -> Dictionary:
	return {
		"scale": factor.value,
		"yaw_degrees": angle.value,
		"anchor": anchor.selected,
		"anchor_position": [x_offset.value, y_offset.value, z_offset.value],
		"classification": _classification_key(classification.selected),
		"suggested_footprint": [int(footprint_x.value), int(footprint_z.value)],
		"calibration_notes": calibration_notes.text.strip_edges(),
		"measured_native_size": [native_bounds.size.x, native_bounds.size.y, native_bounds.size.z],
		"measured_calibrated_size": [current_bounds.size.x, current_bounds.size.y, current_bounds.size.z]
	}

func _save_data(message: String) -> bool:
	var error := Catalog.save_calibrations(calibration_data, calibration_path)
	if error != OK:
		save_status.text = "SAVE FAILED: %s" % error_string(error)
		return false
	save_status.text = message
	return true

func _save_override() -> void:
	calibration_data.asset_overrides[selected] = _override_record()
	if _save_data("Saved asset override for " + selected):
		select_asset(selected)

func _clear_override() -> void:
	calibration_data.asset_overrides.erase(selected)
	if _save_data("Reset to inherited preset for " + selected):
		select_asset(selected)

func _save_category_preset() -> void:
	var category := Catalog.calibration_category(selected)
	calibration_data.category_presets[category] = {"scale": category_scale.value}
	if _save_data("Saved category preset: %s = %.2f" % [category, category_scale.value]):
		select_asset(selected)

func _save_fallback() -> void:
	calibration_data.fallback = {"scale": fallback_scale.value}
	if _save_data("Saved general fallback = %.2f" % fallback_scale.value):
		select_asset(selected)

func _set_reviewed(enabled: bool) -> void:
	if changing:
		return
	if enabled:
		# A reviewed flag must always refer to a durable per-asset record, never
		# merely to a provisional inherited preset or unsaved viewport state.
		calibration_data.asset_overrides[selected] = _override_record()
	var reviewed: Array = calibration_data.reviewed
	if enabled and selected not in reviewed:
		reviewed.append(selected)
		reviewed.sort()
	elif not enabled:
		reviewed.erase(selected)
	calibration_data.reviewed = reviewed
	if _save_data(("Marked reviewed: " if enabled else "Marked unreviewed: ") + selected):
		_filter(search.text)
		_update_save_status()

func _next_unreviewed() -> void:
	var all := Catalog.all_ids()
	var start := maxi(0, all.find(selected) + 1)
	for offset in all.size():
		var candidate: String = all[(start + offset) % all.size()]
		var selected_pack: String = "" if family_filter.selected == 0 else Catalog.PACKS[family_filter.selected - 1]
		var selected_semantic: String = "" if semantic_filter.selected == 0 else str(semantic_filter.get_item_metadata(semantic_filter.selected))
		if candidate not in calibration_data.reviewed and (selected_pack.is_empty() or candidate.begins_with(selected_pack + "/")) and (selected_semantic.is_empty() or Catalog.semantic_category(candidate) == selected_semantic) and (search.text.is_empty() or search.text.to_lower() in candidate.to_lower()):
			select_asset(candidate)
			return
	save_status.text = "No unreviewed assets match the current family/search."

func _reload_calibrations() -> void:
	calibration_data = Catalog.load_calibrations(calibration_path)
	_filter(search.text)
	select_asset(selected)
	save_status.text = "Reloaded " + calibration_path

func _update_save_status() -> void:
	if not is_instance_valid(save_status) or mode.selected != 0:
		return
	var p := Catalog.profile(selected, calibration_data)
	var saved := {"scale": p.scale, "yaw_degrees": p.yaw_degrees, "anchor": p.anchor, "anchor_position": p.anchor_position,
		"classification": p.get("classification", "unclassified"), "suggested_footprint": p.get("suggested_footprint", [0, 0]),
		"calibration_notes": p.get("calibration_notes", ""), "measured_native_size": p.get("measured_native_size", [native_bounds.size.x, native_bounds.size.y, native_bounds.size.z]),
		"measured_calibrated_size": p.get("measured_calibrated_size", [current_bounds.size.x, current_bounds.size.y, current_bounds.size.z])}
	var dirty := JSON.stringify(_override_record()) != JSON.stringify(saved)
	save_status.text = "%s | %s | %s" % [p.calibration_source, "reviewed" if p.reviewed else "unreviewed", "UNSAVED CHANGES" if dirty else "saved/inherited"]

func calibration_record() -> Dictionary:
	var record := _override_record()
	record.merge({"id": selected, "path": Catalog.path_for(selected),
		"native_position": [native_bounds.position.x, native_bounds.position.y, native_bounds.position.z],
		"calibration_source": Catalog.profile(selected, calibration_data).calibration_source,
		"reviewed": reviewed_toggle.button_pressed, "tactical_occupancy": "not authored"})
	return record

func _view_input(event: InputEvent) -> void:
	if orbit.handle_mouse(event):
		accept_event()

func _shortcut_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F: _frame_camera()
		KEY_1: orbit.set_view(0.0, 0.12)
		KEY_3: orbit.set_view(PI / 2.0, 0.12)
		KEY_7: orbit.set_view(0.0, 1.5)
		KEY_Q:
			if mode.selected == 0: angle.value -= 90.0
		KEY_E:
			if mode.selected == 0: angle.value += 90.0
		KEY_S:
			if event.ctrl_pressed and mode.selected == 0: _save_override()

func _frame_camera() -> void:
	if is_instance_valid(orbit) and current_bounds.size.length_squared() > 0.0:
		orbit.frame(display_bounds)

func _classification_key(index: int) -> String:
	return ["unclassified", "structural", "ground", "entrance", "tactical_obstacle", "decorative"][clampi(index, 0, 5)]

func _classification_index(value: String) -> int:
	var values := ["unclassified", "structural", "ground", "entrance", "tactical_obstacle", "decorative"]
	return maxi(0, values.find(value))

static func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	parent.add_child(mesh)

static func _lines(parent: Node3D, points: PackedVector3Array, color: Color) -> void:
	var immediate := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for point in points:
		immediate.surface_add_vertex(point)
	immediate.surface_end()
	var mesh := MeshInstance3D.new()
	mesh.mesh = immediate
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)

static func _axes(parent: Node3D, at: Vector3, length: float) -> void:
	_lines(parent, [at, at + Vector3.RIGHT * length], Color.RED)
	_lines(parent, [at, at + Vector3.UP * length], Color.GREEN)
	_lines(parent, [at, at + Vector3.BACK * length], Color.DODGER_BLUE)

static func _bounds(parent: Node3D, box: AABB) -> void:
	var points := PackedVector3Array()
	for i in 8:
		for j in range(i + 1, 8):
			var delta := box.get_endpoint(j) - box.get_endpoint(i)
			if int(absf(delta.x) > 0.00001) + int(absf(delta.y) > 0.00001) + int(absf(delta.z) > 0.00001) == 1:
				points.append_array([box.get_endpoint(i), box.get_endpoint(j)])
	_lines(parent, points, Color("ffd66b"))
