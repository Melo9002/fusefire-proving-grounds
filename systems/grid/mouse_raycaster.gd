extends Node3D
class_name MouseRaycaster
signal floor_clicked(raw_position: Vector3)
signal unit_clicked(unit: TacticalUnit)

@export var camera: Camera3D
@export var grid_manager: GridManager
@export var click_drag_threshold := 6.0

var _left_pressed := false
var _left_press_position := Vector2.ZERO
var _left_dragged := false
var _surface_index := 0
var _surface_cells: Array[Vector3i] = []
var _preferred_floor_height := INF
var _floor_hint: Label
var _level_panel: PanelContainer
var _level_label: Label
var _level_buttons: HBoxContainer
var _level_signature := ""

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.name = "FloorSelectionHint"
	add_child(layer)
	_floor_hint = Label.new()
	_floor_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor_hint.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	_floor_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	_floor_hint.add_theme_constant_override("shadow_offset_x", 2)
	_floor_hint.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_floor_hint)
	_floor_hint.hide()
	_build_level_panel(layer)

func _build_level_panel(layer: CanvasLayer) -> void:
	_level_panel = PanelContainer.new()
	_level_panel.name = "LevelInspection"
	_level_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_level_panel.position = Vector2(-290, 78)
	_level_panel.size = Vector2(278, 84)
	layer.add_child(_level_panel)
	var rows := VBoxContainer.new()
	_level_panel.add_child(rows)
	_level_label = Label.new()
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_level_label)
	_level_buttons = HBoxContainer.new()
	rows.add_child(_level_buttons)
	var hint := Label.new()
	hint.text = "Alt + wheel: cycle floors under cursor"
	hint.add_theme_font_size_override("font_size", 12)
	rows.add_child(hint)
	_level_panel.hide()

func _inspect_level(height: float) -> void:
	var rig := camera.get_parent() as TacticalCamera if camera else null
	if not rig:
		return
	var point := rig.global_position
	var roofs := get_tree().get_nodes_in_group("tactical_roof_cutaways")
	if not roofs.is_empty():
		point = (roofs[0] as Node3D).global_position
	point.y = height
	rig.inspect_floor(point)
	_update_level_panel()

func _update_level_panel() -> void:
	var rig := camera.get_parent() as TacticalCamera if camera else null
	var levels := _available_levels()
	_level_panel.visible = rig != null and levels.size() > 1
	if not _level_panel.visible:
		return
	_sync_level_buttons(levels)
	var height := rig.inspected_floor_height()
	var level := _nearest_level(height, levels)
	_level_label.text = "VIEW: %s · Level %d" % [grid_manager.map_data.get_elevation_label(level), level]

func _available_levels() -> Array[int]:
	return grid_manager.map_data.get_inspectable_elevation_levels() if grid_manager else []

func _sync_level_buttons(levels: Array[int]) -> void:
	var signature := ",".join(levels.map(func(level: int) -> String: return str(level)))
	if signature == _level_signature:
		return
	_level_signature = signature
	for child in _level_buttons.get_children():
		child.queue_free()
	for level in levels:
		var button := Button.new()
		button.text = grid_manager.map_data.get_elevation_label(level)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_inspect_level.bind(float(level) * grid_manager.elevation_step))
		_level_buttons.add_child(button)

func _nearest_level(height: float, levels: Array[int]) -> int:
	var nearest := levels[0]
	for level in levels:
		if absf(float(level) * grid_manager.elevation_step - height) < absf(float(nearest) * grid_manager.elevation_step - height):
			nearest = level
	return nearest

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_left_pressed = false

func _process(_delta: float) -> void:
	_update_level_panel()
	if not get_window().has_focus() or get_viewport().gui_get_hovered_control():
		_floor_hint.hide()
		return
	var hit := get_floor_raycast_result()
	_floor_hint.visible = not hit.is_empty() and _surface_cells.size() > 1
	if _floor_hint.visible:
		var cell: Vector3i = hit.grid_position
		_floor_hint.text = "Floor %d · %d/%d\nAlt + wheel: choose floor" % [cell.y, _surface_index + 1, _surface_cells.size()]
		var point := get_viewport().get_mouse_position() + Vector2(18, 22)
		var limit := get_viewport().get_visible_rect().size - _floor_hint.size - Vector2(8, 8)
		_floor_hint.position = point.clamp(Vector2.ZERO, limit.max(Vector2.ZERO))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.alt_pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		cycle_surface(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_left_pressed = true
			_left_dragged = false
			_left_press_position = event.position
			return
		var valid_press := _left_pressed
		_left_pressed = false
		if not valid_press or _left_dragged or event.position.distance_to(_left_press_position) >= click_drag_threshold:
			return
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			return
		var floor_hit = get_floor_raycast_result()
		var clicked_unit = get_unit_under_mouse()
		if clicked_unit:
			unit_clicked.emit(clicked_unit)
			return

		if not floor_hit.is_empty():
			floor_clicked.emit(floor_hit.position)
	elif event is InputEventMouseMotion and _left_pressed:
		if event.position.distance_to(_left_press_position) >= click_drag_threshold:
			_left_dragged = true

func get_floor_raycast_result(screen_position := Vector2.INF) -> Dictionary:
	if screen_position == Vector2.INF:
		screen_position = get_viewport().get_mouse_position()
	var candidates := get_floor_candidates(screen_position)
	var cells: Array[Vector3i] = []
	for candidate in candidates:
		cells.append(candidate.grid_position)
	var rig := camera.get_parent() as TacticalCamera if camera else null
	var height := INF
	if rig and _available_levels().size() > 1:
		height = rig.inspected_floor_height()
	if cells != _surface_cells or height != _preferred_floor_height:
		_surface_index = 0
		_surface_cells = cells
		_preferred_floor_height = height
		# Opt-in layered warehouse presentation: avoid ordering a rooftop Move
		# when its hidden collider lies above the inspected interior floor.
		if is_finite(height):
			var nearest := INF
			for index in candidates.size():
				var distance: float = absf(candidates[index].position.y - height)
				if distance < nearest:
					nearest = distance
					_surface_index = index
	if candidates.is_empty():
		return {}
	_surface_index = clampi(_surface_index, 0, candidates.size() - 1)
	# Inspection is a ceiling, not permission to select whichever higher surface
	# happens to be nearest. Retain all candidates for explicit floor cycling.
	if is_finite(height) and candidates[_surface_index].position.y > height + 0.1:
		return {}
	return candidates[_surface_index]

func cycle_surface(direction: int, screen_position := Vector2.INF) -> void:
	get_floor_raycast_result(screen_position)
	if not _surface_cells.is_empty():
		_surface_index = posmod(_surface_index + direction, _surface_cells.size())
		var rig := camera.get_parent() as TacticalCamera if camera else null
		if rig and _available_levels().size() > 1:
			rig.inspect_floor(grid_manager.get_cell_data(_surface_cells[_surface_index]).world_position)

func get_floor_candidates(screen_position: Vector2) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if not grid_manager or not get_viewport().get_visible_rect().has_point(screen_position):
		return candidates
	if not camera:
		camera = get_viewport().get_camera_3d()
		if not camera:
			return candidates

	var mouse_pos = screen_position
	var ray_length = 1000.0
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * ray_length

	var space_state = get_world_3d().direct_space_state
	var excluded: Array[RID] = []
	var seen: Dictionary = {}
	for _index in range(64):
		var query := PhysicsRayQueryParameters3D.create(from, to, 2)
		query.exclude = excluded
		var result := space_state.intersect_ray(query)
		if result.is_empty():
			break
		excluded.append(result.rid)
		# Side faces and solid equipment bases are not destinations.
		if result.normal.y < 0.35:
			continue
		var coordinate := grid_manager.world_to_grid(result.position)
		var cell := grid_manager.get_cell_data(coordinate)
		if not cell or not cell.walkable or not cell.can_stop or seen.has(coordinate):
			continue
		seen[coordinate] = true
		result.grid_position = coordinate
		# Hover, preview and orders must resolve to the same legal cell.
		result.position = cell.world_position
		candidates.append(result)
	return candidates

func get_unit_under_mouse(screen_position := Vector2.INF) -> TacticalUnit:
	if not camera:
		camera = get_viewport().get_camera_3d()
		if not camera:
			return null

	var mouse_pos: Vector2 = get_viewport().get_mouse_position() if screen_position == Vector2.INF else screen_position
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	var floor_hit := get_floor_raycast_result(mouse_pos)
	var excluded: Array[RID] = []
	for _index in range(32):
		var query := PhysicsRayQueryParameters3D.create(from, to, 4)
		query.exclude = excluded
		var result := get_world_3d().direct_space_state.intersect_ray(query)
		if result.is_empty():
			return null
		excluded.append(result.rid)
		var unit := result.collider as TacticalUnit
		if not unit or not unit.is_visible_in_tree() or not unit.stats or unit.stats.is_defeated:
			continue
		if is_finite(_preferred_floor_height):
			var cell := grid_manager.get_cell_data(unit.grid_position)
			if cell and cell.world_position.y > _preferred_floor_height + 0.1:
				continue
		if _surface_index > 0 and not floor_hit.is_empty() and unit.grid_position.y != floor_hit.grid_position.y:
			continue
		return unit
	return null
