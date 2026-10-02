extends "res://art/characters/vroid_proof/runtime/character_rig.gd"

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


func _process(_delta: float) -> void:
	if preview_turning and animation_controller.current_state == &"move":
		_preview_turn_time += _delta
		var target_yaw := PI if int(_preview_turn_time / 2.0) % 2 == 0 else 0.0
		_preview_pivot.rotation.y = rotate_toward(_preview_pivot.rotation.y, target_yaw, TAU * _delta)
		var local_travel := _preview_pivot.basis.inverse() * Vector3.FORWARD
		preview_direction = Vector2(local_travel.x, local_travel.z)
		animation_controller.set_locomotion(preview_direction, preview_speed / 1.6)
	_update_weapon_pose()


func _on_animation_state_changed(state_name: StringName) -> void:
	var rescue_pose := state_name in [&"pickup", &"carry_idle", &"carry_move", &"boarding"]
	if rescue_pose and not is_instance_valid(_demo_passenger):
		_demo_passenger = preload("res://art/characters/vroid_proof/runtime/rescue_passenger.gd").new()
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
