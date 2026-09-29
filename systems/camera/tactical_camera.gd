class_name TacticalCamera
extends Node3D

@export var map_floor: CSGBox3D
@export var camera: Camera3D
@export var pan_speed: float = 12.0
@export var edge_margin: float = 36.0
@export var outside_edge_tolerance: float = 72.0
@export var map_margin: float = 2.0
@export var rotation_speed: float = 90.0
@export var drag_sensitivity: float = 0.3
@export var min_zoom: float = 4.0
@export var max_zoom: float = 56.0
@export var zoom_step: float = 3.0
@export var turn_manager: TurnManager
@export var height_follow_speed: float = 8.0

var _transitioning := false
var _transition_tween: Tween
var _transition_veil: ColorRect

var _tactical_fov := 25.70093
var _zoom: float = 42.0
var _rotating: bool = false
var _dragging := false
var _drag_anchor := Vector3.ZERO
var _cinematic_actor: TacticalUnit
var _cinematic_focus := Vector3.ZERO
var _cinematic_side := 1.0
var _cinematic_active := false
var _cinematic_camera_position := Vector3.ZERO
var _cinematic_look_target := Vector3.ZERO

func _ready() -> void:
	if not map_floor or not camera:
		push_error("TacticalCamera: missing map floor or camera reference")
		set_process(false)
		return
	_tactical_fov = camera.fov
	_set_zoom(camera.position.z)

func _process(delta: float) -> void:
	if _transitioning:
		return
	if _cinematic_active:
		_update_cinematic_camera(delta)
		return
	if not get_window().has_focus():
		_dragging = false
		_rotating = false
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_dragging = false
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_rotating = false
	var selected := _selected_unit()
	if selected and not _dragging and not _rotating:
		global_position.y = lerpf(global_position.y, selected.global_position.y, 1.0 - exp(-height_follow_speed * delta))
	var input_direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_direction.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_direction.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_direction.y -= 1.0

	var mouse := get_viewport().get_mouse_position()
	var viewport_size := get_viewport().get_visible_rect().size
	var edge_scroll_area := Rect2(Vector2.ONE * -outside_edge_tolerance, viewport_size + Vector2.ONE * outside_edge_tolerance * 2.0)
	if not _rotating and not _dragging and edge_scroll_area.has_point(mouse) and not get_viewport().gui_get_hovered_control():
		if mouse.x <= edge_margin:
			input_direction.x -= 1.0
		elif mouse.x >= viewport_size.x - edge_margin:
			input_direction.x += 1.0
		if mouse.y <= edge_margin:
			input_direction.y += 1.0
		elif mouse.y >= viewport_size.y - edge_margin:
			input_direction.y -= 1.0

	if input_direction != Vector2.ZERO:
		_pan(input_direction.normalized(), delta)

	var turn_direction := 0.0
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_PAGEUP):
		turn_direction -= 1.0
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_PAGEDOWN):
		turn_direction += 1.0
	if turn_direction != 0.0:
		rotate_y(deg_to_rad(-turn_direction * rotation_speed * delta))

func _unhandled_input(event: InputEvent) -> void:
	if _cinematic_active:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_F, KEY_HOME]:
		focus_selected_unit()
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_rotating = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
			if _dragging:
				var point = _ground_point(event.position)
				_dragging = point != null
				if _dragging:
					_drag_anchor = point
		elif event.pressed and not event.alt_pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(_zoom - minf(zoom_step, _zoom * 0.15))
		elif event.pressed and not event.alt_pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(_zoom + minf(zoom_step, _zoom * 0.15))
	elif event is InputEventMouseMotion and _rotating:
		rotate_y(deg_to_rad(-event.relative.x * drag_sensitivity))
	elif event is InputEventMouseMotion and _dragging:
		var point = _ground_point(event.position)
		if point != null:
			global_position += _drag_anchor - point
			_clamp_to_map()

func _ground_point(screen_position: Vector2) -> Variant:
	return Plane(Vector3.UP, global_position.y).intersects_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))

func _selected_unit() -> TacticalUnit:
	if not turn_manager or not is_instance_valid(turn_manager.active_unit):
		return null
	var level := get_parent() as BattleLevel
	if level and not level.battle_controller.is_current_phase_manually_controlled():
		return null
	return turn_manager.active_unit

func focus_selected_unit() -> void:
	var unit := _selected_unit()
	if unit:
		focus_position(unit.global_position)

func focus_position(point: Vector3) -> void:
	clear_cinematic_view()
	global_position = point
	_clamp_to_map()

func frame_cinematic_action(actor: TacticalUnit, focus_point: Vector3) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(camera):
		return
	_cancel_camera_transition()
	var previous_transform := camera.global_transform
	var previous_fov := camera.fov
	_cinematic_actor = actor
	_cinematic_focus = focus_point
	_cinematic_active = true
	_update_cinematic_camera(1.0)
	var next_transform := camera.global_transform
	var next_fov := camera.fov
	camera.global_transform = previous_transform
	camera.fov = previous_fov
	var distance := previous_transform.origin.distance_to(next_transform.origin)
	var angle := previous_transform.basis.get_rotation_quaternion().angle_to(next_transform.basis.get_rotation_quaternion())
	if distance < 0.05 and angle < 0.02:
		camera.global_transform = next_transform
		camera.fov = next_fov
		return
	_transitioning = true
	_transition_tween = create_tween()
	_transition_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Fade large relocations, large turns, or routes through terrain instead of
	# sweeping across the battlefield. The replay UI remains visible above it.
	if distance > 6.0 or angle > deg_to_rad(75.0) or not _camera_path_clear(previous_transform.origin, next_transform.origin):
		_ensure_transition_veil()
		_transition_tween.tween_property(_transition_veil, "color:a", 1.0, 0.22)
		_transition_tween.tween_callback(func():
			camera.global_transform = next_transform
			camera.fov = next_fov
		)
		_transition_tween.tween_property(_transition_veil, "color:a", 0.0, 0.28)
	else:
		_transition_tween.tween_method(func(weight: float):
			camera.global_transform = previous_transform.interpolate_with(next_transform, weight)
			camera.fov = lerpf(previous_fov, next_fov, weight)
		, 0.0, 1.0, 0.5)
	_transition_tween.tween_callback(func(): _transitioning = false)

func is_camera_transitioning() -> bool:
	return _transitioning

func _ensure_transition_veil() -> void:
	if is_instance_valid(_transition_veil):
		return
	var canvas := CanvasLayer.new()
	canvas.layer = 0
	add_child(canvas)
	_transition_veil = ColorRect.new()
	_transition_veil.color = Color(0.015, 0.02, 0.03, 0.0)
	_transition_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_transition_veil)
	_transition_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _cancel_camera_transition() -> void:
	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()
	_transitioning = false
	if is_instance_valid(_transition_veil):
		_transition_veil.color.a = 0.0

func clear_cinematic_view() -> void:
	_cancel_camera_transition()
	if not _cinematic_active:
		return
	_cinematic_active = false
	_cinematic_actor = null
	camera.position = Vector3(0.0, 0.0, _zoom)
	camera.rotation = Vector3.ZERO
	camera.fov = _tactical_fov
	_set_zoom(_zoom)

func return_to_tactical_view() -> void:
	if not _cinematic_active:
		return
	_cancel_camera_transition()
	var previous_transform := camera.global_transform
	var previous_fov := camera.fov
	var actor := _cinematic_actor
	_cinematic_active = false
	_cinematic_actor = null
	if is_instance_valid(actor):
		global_position = actor.global_position
		_clamp_to_map()
	camera.position = Vector3(0.0, 0.0, _zoom)
	camera.rotation = Vector3.ZERO
	camera.fov = _tactical_fov
	var next_transform := camera.global_transform
	camera.global_transform = previous_transform
	camera.fov = previous_fov
	_transitioning = true
	_transition_tween = create_tween()
	_transition_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_ensure_transition_veil()
	_transition_tween.tween_property(_transition_veil, "color:a", 1.0, 0.2)
	_transition_tween.tween_callback(func():
		camera.global_transform = next_transform
		camera.fov = _tactical_fov
	)
	_transition_tween.tween_property(_transition_veil, "color:a", 0.0, 0.25)
	_transition_tween.tween_callback(func(): _transitioning = false)

func _update_cinematic_camera(delta: float) -> void:
	if not is_instance_valid(_cinematic_actor):
		clear_cinematic_view()
		return
	var actor_position := _cinematic_actor.global_position - Vector3.UP * _cinematic_actor.standing_height
	if is_instance_valid(_cinematic_actor.visual_adapter):
		actor_position = _cinematic_actor.visual_adapter.global_position
	var direction := _cinematic_focus - actor_position
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = _cinematic_actor.visual_adapter.global_basis.z if is_instance_valid(_cinematic_actor.visual_adapter) else Vector3.BACK
	else:
		direction = direction.normalized()
	var visual := _cinematic_actor.visual_adapter
	var body_height := 1.6
	var focus := actor_position + Vector3.UP * 1.05
	var eye := actor_position + Vector3.UP * 1.5
	if is_instance_valid(visual):
		body_height = visual.get_camera_height()
		focus = visual.get_camera_focus()
		eye = visual.get_camera_eye()
	var size_scale := body_height / 1.6
	var shoulder_side := direction.cross(Vector3.UP).normalized()
	var base := eye + Vector3.UP * (0.25 * size_scale) - direction * (2.8 * size_scale)
	var desired_position := base + shoulder_side * (0.65 * size_scale * _cinematic_side)
	if not _camera_path_clear(focus, desired_position):
		var opposite := base - shoulder_side * (0.65 * size_scale * _cinematic_side)
		if _camera_path_clear(focus, opposite):
			_cinematic_side *= -1.0
			desired_position = opposite
		else:
			# Both shoulders blocked: try an elevated tactical angle first.
			var elevated := focus - direction * (3.0 * size_scale) + Vector3.UP * (3.0 * size_scale)
			desired_position = elevated if _camera_path_clear(focus, elevated) else _safe_camera_position(focus, desired_position)
	var distance_to_focus := actor_position.distance_to(_cinematic_focus)
	var forward_interest := minf(distance_to_focus * 0.2, 1.8 * size_scale)
	var desired_target := focus + direction * forward_interest
	var blend := 1.0 if delta >= 0.99 else 1.0 - exp(-8.0 * delta)
	var eased_position := _cinematic_camera_position.lerp(desired_position, blend)
	# Never ease through a wall when changing shoulders. Pull inward immediately.
	_cinematic_camera_position = eased_position if _camera_path_clear(focus, eased_position) else desired_position
	_cinematic_look_target = desired_target if delta >= 0.99 else _cinematic_look_target.lerp(desired_target, blend)
	camera.fov = 55.0
	camera.global_position = _cinematic_camera_position
	camera.look_at(_cinematic_look_target, Vector3.UP)

# Terrain uses collision layers 1 and 2; units on layer 3 do not block cameras.
func _safe_camera_position(origin: Vector3, destination: Vector3) -> Vector3:
	var motion := destination - origin
	if motion.length_squared() < 0.00001:
		return origin
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(0.15, camera.near * 2.0)
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.motion = motion
	query.collision_mask = 3
	var fractions := get_world_3d().direct_space_state.cast_motion(query)
	var fraction := fractions[0] if not fractions.is_empty() else 0.0
	# A ray also catches thin surfaces and provides a conservative wall margin.
	var ray := PhysicsRayQueryParameters3D.create(origin, destination, 3)
	ray.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		fraction = minf(fraction, maxf(0.0, origin.distance_to(hit.position) - sphere.radius) / motion.length())
	return origin + motion * fraction

func _camera_path_clear(origin: Vector3, destination: Vector3) -> bool:
	return _safe_camera_position(origin, destination).distance_squared_to(destination) < 0.0001

func _pan(direction: Vector2, delta: float) -> void:
	var right = Vector3.RIGHT.rotated(Vector3.UP, rotation.y)
	var forward = Vector3.FORWARD.rotated(Vector3.UP, rotation.y)
	global_position += (right * direction.x + forward * direction.y) * pan_speed * delta
	_clamp_to_map()

func _set_zoom(value: float) -> void:
	_zoom = clampf(value, min_zoom, max_zoom)
	if _cinematic_active:
		return
	# Lower the viewing angle continuously inside the old closest zoom.
	var close_blend := smoothstep(min_zoom, 20.0, _zoom)
	rotation.x = deg_to_rad(lerpf(-12.0, -45.0, close_blend))
	camera.position = Vector3(0.0, 0.0, _zoom)

func _clamp_to_map() -> void:
	var center = map_floor.global_position
	var half_width = map_floor.size.x * 0.5 + map_margin
	var half_depth = map_floor.size.z * 0.5 + map_margin
	global_position.x = clampf(global_position.x, center.x - half_width, center.x + half_width)
	global_position.z = clampf(global_position.z, center.z - half_depth, center.z + half_depth)
