@tool
extends "res://presentation/characters/runtime/character_rig.gd"

@onready var status_label: Label = get_node_or_null("UI/Status") as Label
@onready var camera: Camera3D = get_node_or_null("Camera3D") as Camera3D
var side_view := false
var preview_direction := Vector2(0, 1)
var preview_speed := 1.6
var preview_turning := false
var _preview_pivot: Node3D
var _preview_turn_time := 0.0
var _orbit_dragging := false
var _demo_passenger: Node3D
const ORBIT_FOCUS := Vector3(0, 0.85, 0)

# --- Hand-contact diagnostics (workbench only; see presentation/diagnostics/). Nothing here is created
# until H is pressed, and nothing here changes how the rig poses itself.
var _diagnostics: HandContactDiagnostics
## Diagnostic camera views: 0 is the workbench's own camera (orbit and C still work there).
const DIAGNOSTIC_VIEW_NAMES := ["workbench camera", "full body", "dominant hand close-up", "support hand close-up", "both hands and weapon"]
var _diagnostic_view := 0
## Crouch presets drive the existing CoverCrouchModifier the way UnitVisualAdapter does, with its ramp speeds.
## They exist so crouch, kneel and aim-while-crouched can be inspected here; there is no cover yaw.
const POSE_PRESET_NAMES := ["standing", "crouch", "half-kneel"]
var _pose_preset := 0

func _preview_locomotion(direction: Vector2) -> void:
	preview_turning = false
	if is_instance_valid(_preview_pivot):
		_preview_pivot.rotation.y = 0.0
	preview_direction = direction
	animation_controller.set_locomotion(direction, preview_speed / 1.6)
	if animation_controller.current_state != &"move":
		animation_controller.play(&"move")
	_update_status()

func _ready() -> void:
	_build_character()
	_build_weapon_attachment()
	_build_arm_ik()
	if Engine.is_editor_hint():
		await get_tree().process_frame
		await get_tree().process_frame
		_align_weapon_to_aim()
		_update_weapon_pose()
		return
	_build_animation_controller()
	skeleton.skeleton_updated.connect(_align_weapon_to_aim)
	camera.look_at(Vector3(0.42, 0.72, 0.0), Vector3.UP)
	_update_status()
	# BoneAttachment3D receives its final pose after the skeleton modifier pass.
	# Wait for that pose, then establish the proof's authored rifle orientation.
	await get_tree().process_frame
	await get_tree().process_frame
	_align_weapon_to_aim()
	if "--side-view" in OS.get_cmdline_user_args():
		camera.position = Vector3(3.4, 1.3, 0.1)
		camera.look_at(Vector3(0, 0.85, 0), Vector3.UP)
	if "--auto-sequence" in OS.get_cmdline_user_args():
		animation_controller.play_sequence()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_orbit_dragging = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _orbit_dragging:
		var offset := camera.position - ORBIT_FOCUS
		var radius := offset.length()
		var yaw: float = atan2(offset.x, offset.z) - event.relative.x * 0.005
		var elevation := clampf(asin(offset.y / radius) + event.relative.y * 0.005, -0.15, 1.35)
		camera.position = ORBIT_FOCUS + Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation)) * radius
		camera.look_at(ORBIT_FOCUS, Vector3.UP)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_V, KEY_B, KEY_N, KEY_L, KEY_R, KEY_P, KEY_M, KEY_E, KEY_SPACE]:
			preview_turning = false
			if is_instance_valid(_preview_pivot):
				_preview_pivot.rotation.y = 0.0
		match event.keycode:
			KEY_H:
				_toggle_diagnostics()
			KEY_J:
				if is_instance_valid(_diagnostics): _diagnostics.set_labels_visible(not _diagnostics.labels_visible)
				_update_status()
			KEY_G:
				_mark_contact_reference()
			KEY_Z:
				_cycle_pose_preset()
			KEY_X:
				_cycle_diagnostic_view()
			KEY_R:
				animation_controller.play(&"pickup")
			KEY_P:
				animation_controller.play(&"carry_idle")
			KEY_M:
				animation_controller.play(&"carry_move")
			KEY_E:
				animation_controller.play(&"boarding")
			KEY_7:
				animation_controller.play(&"cover_low")
			KEY_8:
				animation_controller.play(&"cover_high")
			KEY_9:
				animation_controller.play(&"shoot_left")
			KEY_0:
				animation_controller.play(&"shoot_right")
			KEY_V:
				animation_controller.play(&"vault")
			KEY_B:
				animation_controller.play(&"climb")
			KEY_N:
				animation_controller.play(&"descend")
			KEY_L:
				animation_controller.play(&"land")
			KEY_UP:
				_preview_locomotion(Vector2(0, 1))
			KEY_DOWN:
				_preview_locomotion(Vector2(0, -1))
			KEY_LEFT:
				_preview_locomotion(Vector2(-1, 0))
			KEY_RIGHT:
				_preview_locomotion(Vector2(1, 0))
			KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
				preview_speed = clampf(preview_speed + (-0.4 if event.keycode == KEY_BRACKETLEFT else 0.4), 0.4, 6.0)
				animation_controller.set_locomotion(preview_direction, preview_speed / 1.6)
				_update_status()
			KEY_T:
				_preview_locomotion(Vector2(0, 1))
				if not is_instance_valid(_preview_pivot):
					_preview_pivot = Node3D.new()
					_preview_pivot.name = "LocomotionPreviewPivot"
					add_child(_preview_pivot)
					character_root.reparent(_preview_pivot)
				_preview_turn_time = 0.0
				preview_turning = true
				_update_status()
			KEY_I:
				ik_enabled = not ik_enabled
				arm_ik.active = ik_enabled
				_update_status()
			KEY_C:
				side_view = not side_view
				camera.position = Vector3(3.4, 1.3, 0.1) if side_view else Vector3(2.8, 1.65, 3.55)
				camera.look_at(Vector3(0, 0.85, 0) if side_view else Vector3(0.42, 0.72, 0), Vector3.UP)
			KEY_ESCAPE:
				get_tree().quit()
			KEY_1:
				animation_controller.play(&"rifle_idle")
			KEY_2:
				_preview_locomotion(Vector2(0, 1))
			KEY_3:
				animation_controller.play(&"aim")
			KEY_4:
				animation_controller.play(&"shoot")
			KEY_5:
				animation_controller.play(&"hit")
			KEY_6:
				animation_controller.play(&"defeat")
			KEY_SPACE:
				animation_controller.play_sequence()


func _update_status() -> void:
	if not is_instance_valid(status_label):
		return
	var state_name: StringName = animation_controller.current_state if is_instance_valid(animation_controller) else &"setup"
	# Keep controls in the demo so individual poses are easy to inspect.
	status_label.text = "STATE: %s    IK: %s\n1 Idle  2 Move  3 Aim  4 Shoot  5 Hit  6 Defeat\nArrows: forward/back/strafe    T: turn preview\n[ / ]: pace %.1f m/s    Direction: %s\nRMB drag: orbit    C: camera preset\nSpace: sequence    I: IK    Esc: close\nLocomotion preview is in place" % [state_name, "ON" if ik_enabled else "OFF", preview_speed, "turning" if preview_turning else str(preview_direction)]
	status_label.text += "\n7/8: low/high cover    9/0: expose left/right\nV: vault    B: climb    N: descend    L: landing"
	status_label.text += "\nR: pickup    P: carry idle    M: carry move    E: boarding"
	var diagnostics_on := is_instance_valid(_diagnostics) and _diagnostics.enabled
	status_label.text += "\nH: hand diagnostics %s    J: labels    G: mark contact    Z: pose %s    X: view %s" % ["ON" if diagnostics_on else "off", POSE_PRESET_NAMES[_pose_preset], DIAGNOSTIC_VIEW_NAMES[_diagnostic_view]]


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if preview_turning and animation_controller.current_state == &"move":
		_preview_turn_time += _delta
		var target_yaw := PI if int(_preview_turn_time / 2.0) % 2 == 0 else 0.0
		_preview_pivot.rotation.y = rotate_toward(_preview_pivot.rotation.y, target_yaw, TAU * _delta)
		var local_travel := _preview_pivot.basis.inverse() * Vector3.FORWARD
		preview_direction = Vector2(local_travel.x, local_travel.z)
		animation_controller.set_locomotion(preview_direction, preview_speed / 1.6)
	_ramp_pose_preset(_delta)
	_follow_diagnostic_view()
	_update_weapon_pose()


func _on_animation_state_changed(state_name: StringName) -> void:
	var rescue_pose := state_name in [&"pickup", &"carry_idle", &"carry_move", &"boarding"]
	if rescue_pose and not is_instance_valid(_demo_passenger):
		_demo_passenger = preload("res://presentation/characters/runtime/rescue_passenger.gd").new()
		character_root.add_child(_demo_passenger)
		_demo_passenger.position = passenger_position
	if is_instance_valid(_demo_passenger):
		_demo_passenger.visible = rescue_pose
		arm_ik.active = ik_enabled and not rescue_pose
		if rescue_pose:
			weapon.reparent(character_root)
			weapon.position = stowed_weapon_position
			weapon.rotation_degrees = stowed_weapon_angles_degrees
		else:
			weapon.reparent(weapon_attachment)
	_update_status()
	super._on_animation_state_changed(state_name)

func _align_weapon_to_aim() -> void:
	if is_instance_valid(_demo_passenger) and _demo_passenger.visible:
		return
	super._align_weapon_to_aim()

func _update_weapon_pose() -> void:
	if is_instance_valid(_demo_passenger) and _demo_passenger.visible:
		return
	super._update_weapon_pose()


## H: switches the hand-contact diagnostics (overlay and readout) on or off. They are created on first use.
func _toggle_diagnostics() -> void:
	if not is_instance_valid(_diagnostics):
		_diagnostics = HandContactDiagnostics.attach(self)
		if _diagnostics == null:
			push_warning("Hand-contact diagnostics are unavailable for this rig")
			return
	_diagnostics.set_enabled(not _diagnostics.enabled)
	_update_status()

## G: marks the current hand contact (palms and wrists in the weapon's frame) as the reference for the shift readout.
func _mark_contact_reference() -> void:
	if is_instance_valid(_diagnostics) and _diagnostics.enabled:
		_diagnostics.mark_reference()

## Z: standing, then crouch, then half-kneel. Sets only the public inputs of the existing crouch modifier.
func _cycle_pose_preset() -> void:
	_pose_preset = (_pose_preset + 1) % POSE_PRESET_NAMES.size()
	_update_status()

func _pose_preset_depth() -> float:
	if crouch_modifier == null:
		return 0.0
	match _pose_preset:
		1: return crouch_modifier.clamp_depth(0.41)   # about the depth for hiding behind 1.15 m cover
		2: return crouch_modifier.max_depth           # what the adapter asks for behind cover too low to crouch behind
	return 0.0

func _ramp_pose_preset(delta: float) -> void:
	if crouch_modifier == null or Engine.is_editor_hint():
		return
	crouch_modifier.depth = move_toward(crouch_modifier.depth, _pose_preset_depth(), UnitVisualAdapter.CROUCH_SPEED * delta)
	crouch_modifier.kneel = move_toward(crouch_modifier.kneel, 1.0 if _pose_preset == 2 else 0.0, UnitVisualAdapter.KNEEL_SPEED * delta)

## X: cycles fixed diagnostic camera views. The close-ups follow the hands as the pose changes.
func _cycle_diagnostic_view() -> void:
	_diagnostic_view = (_diagnostic_view + 1) % DIAGNOSTIC_VIEW_NAMES.size()
	if _diagnostic_view == 0:
		camera.position = Vector3(2.8, 1.65, 3.55)
		camera.look_at(Vector3(0.42, 0.72, 0), Vector3.UP)
		camera.fov = 34.0
	_update_status()

func _follow_diagnostic_view() -> void:
	if _diagnostic_view == 0 or not is_instance_valid(camera) or not is_instance_valid(weapon):
		return
	var facing := character_root.global_basis.orthonormalized()
	var firing := weapon.to_global(handling.firing_grip)
	var support := weapon.to_global(handling.support_grip)
	var focus := ORBIT_FOCUS
	var offset := Vector3.ZERO
	camera.fov = 30.0
	match _diagnostic_view:
		1:
			focus = Vector3(0, 0.82, 0)
			offset = facing * Vector3(-1.4, 0.55, 2.4)
		2:
			focus = firing
			offset = facing * Vector3(-0.50, 0.14, 0.34)
			camera.fov = 26.0
		3:
			focus = support
			offset = facing * Vector3(0.50, 0.14, 0.34)
			camera.fov = 26.0
		4:
			focus = (firing + support) * 0.5
			offset = facing * Vector3(-0.85, 0.30, 0.75)
	camera.position = focus + offset
	camera.look_at(focus, Vector3.UP)
