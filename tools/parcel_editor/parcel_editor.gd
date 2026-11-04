class_name ParcelEditor
extends Node3D
## Small registered-parcel inspection shell. This deliberately does not restore
## the retired chunk generator, publication system, or runtime dependencies.

const Catalog = preload("res://systems/generation/authored_parcel_catalog.gd")

var parcel_picker: OptionButton
var metadata_label: Label
var validation_label: Label
var population_toggle: CheckButton
var tactical_toggle: CheckButton
var camera: Camera3D
var displayed_parcel_id: StringName = &""
var displayed_parcel: Node3D
var tactical_overlay: Node3D

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
	panel.size = Vector2(360, 560)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
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
	var failures: PackedStringArray = definition.validate()
	validation_label.text = "VALID — registered scene and contracts agree" if failures.is_empty() else "INVALID — %s" % "; ".join(failures)
	validation_label.modulate = Color("79d99b") if failures.is_empty() else Color("ff7a7a")
	population_toggle.button_pressed = true
	population_toggle.disabled = definition.population_sockets().is_empty()
	set_population_visible(true)
	_frame()

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
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
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
			var scale := _distance * 0.0018
			var right := camera.global_basis.x
			var forward := Vector3(camera.global_basis.z.x, 0, camera.global_basis.z.z).normalized()
			_camera_target += right * -event.relative.x * scale + forward * -event.relative.y * scale
			_update_camera()
