extends Control
## Standalone presentation sandbox; no battle, grid singleton, or combat state.
const Catalog = preload("res://tools/asset_lab/asset_catalog.gd")
const Placement = preload("res://presentation/environment_asset_placement.gd")
var world: Node3D
var content: Node3D
var overlays: Node3D
var viewport: SubViewport
var camera: Camera3D
var asset_list: ItemList
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
var distance := 12.0
var azimuth := 0.65
var altitude := 0.45
var focus := Vector3(0, 1, 0)
var current_bounds := AABB()
var native_bounds := AABB()
var comparison: Node3D
var copy_button: Button

func _ready() -> void:
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
	var search := LineEdit.new()
	search.placeholder_text = "Search pack/model (all 315)"
	panel.add_child(search)
	asset_list = ItemList.new()
	asset_list.custom_minimum_size.y = 170
	panel.add_child(asset_list)
	search.text_changed.connect(_filter)
	asset_list.item_selected.connect(func(i): select_asset(asset_list.get_item_metadata(i)))
	_filter("")
	factor = _number(panel, "Uniform scale", 0.01, 20, 0.01, 1)
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
	var reset := Button.new()
	reset.text = "Reset to catalog calibration / frame"
	reset.pressed.connect(func(): select_asset(selected))
	panel.add_child(reset)
	copy_button = Button.new()
	copy_button.text = "Copy current calibration JSON"
	copy_button.pressed.connect(func(): DisplayServer.clipboard_set(JSON.stringify(calibration_record(), "\t")))
	panel.add_child(copy_button)
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
	for id in ids:
		if query.is_empty() or query.to_lower() in id.to_lower():
			var index := asset_list.add_item(("* " if Catalog.PROFILES.has(id) else "") + id)
			asset_list.set_item_metadata(index, id)
			asset_list.set_item_tooltip(index, id)

func select_asset(id: String) -> void:
	changing = true
	selected = id
	mode.select(0)
	var profile := Catalog.profile(id)
	factor.value = profile.scale
	angle.value = 0
	anchor.select(profile.anchor)
	x_offset.value = 0
	y_offset.value = -0.12 if id == "city_kit_roads/road-side" else 0
	z_offset.value = 0
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
	for control in [factor, angle, x_offset, y_offset, z_offset, pitch]:
		control.editable = mode.selected == 0
	anchor.disabled = mode.selected != 0
	duplicate_piece.disabled = mode.selected != 0
	copy_button.disabled = mode.selected != 0
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
		var p := Catalog.profile(selected)
		info.text = "%s\n%s\n%s\nNative bounds: %s\nPlaced size: %s\nVisual envelope ceil X/Z: %d × %d (NOT occupancy)\n%s\n" % [selected, p.category, p.orientation, native_bounds, current_bounds.size, ceili(current_bounds.size.x - 0.0001), ceili(current_bounds.size.z - 0.0001), p.note]
		_axes(overlays, at, 0.65)
	else:
		_build_assembly(mode.selected)
		info.text = "Assembly %d — fixed family scales, authored origins.\nBounds are visual envelopes, not solids.\nIndividual controls apply only in asset mode.\n" % mode.selected
	current_bounds = Placement.mesh_bounds(content)
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
		content.add_child(comparison)
	info.text += "\nGrid = 1 world unit. Red +X / green +Y / blue +Z.\nRMB drag: orbit · wheel: zoom · F: frame.\n* = curated calibration; others unreviewed.\nCopy exports the individual asset settings only."
	if frame:
		focus = current_bounds.get_center() + Vector3(0.7, 0, 0)
		distance = maxf(7, current_bounds.size.length() * 1.35)
	_update_camera()

func _build_assembly(index: int) -> void:
	match index:
		1:
			for x in [-6, 0, 6]:
				Catalog.place(content, "city_kit_roads/road-side", Vector3(x, -0.12, 0))
				Catalog.place(content, "city_kit_roads/tile-low", Vector3(x, 0, -7.86))
		2:
			Catalog.place(content, "factory_kit/structure-doorway-wide", Vector3.ZERO)
			for x in [-3.75, -2.25, 2.25, 3.75]:
				Catalog.place(content, "factory_kit/structure-wall", Vector3(x, 0, 0))
		3:
			Catalog.place(content, "city_kit_industrial/shipping-container-a", Vector3(-4, 0, 0), PI / 2)
			Catalog.place(content, "factory_kit/crane", Vector3(3.5, 0, 0))
			Catalog.place(content, "factory_kit/machine", Vector3(-1, 0, 4))
			for x in [1, 3]:
				_box(content, Vector3(2, 0.4, 1), Vector3(x, 0.2, 4), Color("555e68"))
				Catalog.place(content, "factory_kit/conveyor-long", Vector3(x, 0.4, 4))
		4:
			for x in [-2, 2]:
				Catalog.place(content, "modular_space_kit/template-floor", Vector3(x, 0, 0))
				Catalog.place(content, "modular_space_kit/template-wall", Vector3(x, 0, -1))

func calibration_record() -> Dictionary:
	return {"id": selected, "path": Catalog.path_for(selected), "scale": factor.value, "yaw_degrees": angle.value,
		"anchor": anchor.selected, "anchor_position": [x_offset.value, y_offset.value, z_offset.value],
		"native_position": [native_bounds.position.x, native_bounds.position.y, native_bounds.position.z],
		"native_size": [native_bounds.size.x, native_bounds.size.y, native_bounds.size.z], "tactical_occupancy": "not authored"}

func _view_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		azimuth -= event.relative.x * 0.008
		altitude = clampf(altitude + event.relative.y * 0.008, -0.1, 1.4)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(1, distance * 0.9)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(100, distance / 0.9)
	_update_camera()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		rebuild(true)

func _update_camera() -> void:
	camera.position = focus + Vector3(sin(azimuth) * cos(altitude), sin(altitude), cos(azimuth) * cos(altitude)) * distance
	camera.look_at(focus)

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
