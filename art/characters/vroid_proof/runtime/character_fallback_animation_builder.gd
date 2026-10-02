class_name CharacterFallbackAnimationBuilder
extends RefCounted
## Procedural safety-net clips for rigs missing authored animations.
## Runtime playback and state transitions belong to character_animation_controller.gd.

const HIPS := &"J_Bip_C_Hips"
const SPINE := &"J_Bip_C_Spine"
const CHEST := &"J_Bip_C_Chest"
const HEAD := &"J_Bip_C_Head"
const LEFT_UPPER_LEG := &"J_Bip_L_UpperLeg"
const LEFT_LOWER_LEG := &"J_Bip_L_LowerLeg"
const LEFT_FOOT := &"J_Bip_L_Foot"
const RIGHT_UPPER_LEG := &"J_Bip_R_UpperLeg"
const RIGHT_LOWER_LEG := &"J_Bip_R_LowerLeg"
const RIGHT_FOOT := &"J_Bip_R_Foot"

var skeleton: Skeleton3D

func _init(target_skeleton: Skeleton3D) -> void:
	skeleton = target_skeleton


func _make_directional_move(direction: Vector2) -> Animation:
	var animation := _make_move()
	# Re-author thigh swing in travel direction, keeping knee flexion anatomical.
	# Lift happens during the first half-cycle for the left leg and second for right.
	for side in ["L", "R"]:
		var bone := LEFT_UPPER_LEG if side == "L" else RIGHT_UPPER_LEG
		var track := animation.find_track(NodePath(".:%s" % bone), Animation.TYPE_ROTATION_3D)
		animation.remove_track(track)
		var sign_value := 1.0 if side == "L" else -1.0
		var start := _rotation(-22.0 * direction.y * sign_value, 0, 18.0 * direction.x * sign_value)
		var end := _rotation(22.0 * direction.y * sign_value, 0, -18.0 * direction.x * sign_value)
		_add_rotation(animation, bone, [0.0, 0.5, 1.0], [start, end, start])
	return animation


func _make_idle() -> Animation:
	var animation := _new_animation(2.0, true)
	_add_rotation(animation, CHEST, [0.0, 1.0, 2.0], [_rotation(0.0, 0.0, -1.0), _rotation(-2.4, 0.0, 1.5), _rotation(0.0, 0.0, -1.0)])
	_add_rotation(animation, HEAD, [0.0, 1.0, 2.0], [_rotation(0.0, -1.0, 0.0), _rotation(0.8, 1.0, 0.0), _rotation(0.0, -1.0, 0.0)])
	_add_grip(animation)
	return animation


func _make_tactical_pose(pose: StringName) -> Animation:
	# Blocking poses: knee flexion stays negative on this imported rig.
	# Root travel is supplied by the tactical path, never by these clips.
	var landing := pose == &"land"
	var animation := _new_animation(0.3 if landing else 0.8, not landing)
	var crouch := 0.10 if pose == &"cover_low" else 0.012
	var thigh := 30.0 if pose == &"cover_low" else 10.0
	var knee := -60.0 if pose == &"cover_low" else -20.0
	if pose in [&"vault", &"climb", &"descend", &"land"]:
		crouch = 0.10
		thigh = 45.0
		knee = -80.0
	if pose == &"descend":
		crouch = 0.05
		thigh = 25.0
		knee = -55.0
	var end := animation.length
	var times := [0.0, end * 0.5, end]
	_add_position(animation, HIPS, times, [Vector3(0, -crouch, 0), Vector3(0, -crouch - 0.015, 0), Vector3.ZERO if landing else Vector3(0, -crouch, 0)])
	for side in ["L", "R"]:
		var upper := LEFT_UPPER_LEG if side == "L" else RIGHT_UPPER_LEG
		var lower := LEFT_LOWER_LEG if side == "L" else RIGHT_LOWER_LEG
		var foot := LEFT_FOOT if side == "L" else RIGHT_FOOT
		var alternating := pose in [&"climb", &"descend"]
		var a := thigh * (0.35 if alternating and side == "R" else 1.0)
		var b := thigh * (0.35 if alternating and side == "L" else 1.0)
		_add_rotation(animation, upper, times, [_rotation(a, 0, 0), _rotation(b, 0, 0), Quaternion.IDENTITY if landing else _rotation(a, 0, 0)])
		_add_rotation(animation, lower, times, [_rotation(knee, 0, 0), _rotation(knee * 0.8, 0, 0), Quaternion.IDENTITY if landing else _rotation(knee, 0, 0)])
		_add_rotation(animation, foot, times, [_rotation(-a - knee, 0, 0), _rotation(-b - knee * 0.8, 0, 0), Quaternion.IDENTITY if landing else _rotation(-a - knee, 0, 0)])
	_add_rotation(animation, CHEST, [0.0], [_rotation(-5, 12, -6) if pose == &"cover_high" else _rotation(-8, 0, 0)])
	_add_grip(animation)
	return animation

func _make_rescue_pose(pose: StringName) -> Animation:
	var moving := pose == &"carry_move"
	var animation := _make_move() if moving else _new_animation(0.6, pose == &"carry_idle")
	if moving:
		animation.remove_track(animation.find_track(NodePath(".:%s" % CHEST), Animation.TYPE_ROTATION_3D))
	var times := [0.0, 0.3, 0.6]
	var angles := [-10.0, -12.0, -10.0]
	if pose == &"pickup":
		angles = [-5.0, -35.0, -10.0]
	elif pose == &"boarding":
		angles = [-10.0, -30.0, -5.0]
	if moving:
		times = [0.0, 0.5, 1.0]
	_add_rotation(animation, CHEST, times, [_rotation(angles[0], 0, 0), _rotation(angles[1], 0, 0), _rotation(angles[2], 0, 0)])
	if not moving:
		_add_grip(animation)
	for side in ["L", "R"]:
		var sign_value := -1.0 if side == "L" else 1.0
		_add_rotation(animation, StringName("J_Bip_%s_UpperArm" % side), [0.0], [_rotation(-20, 0, 45 * sign_value)])
		_add_rotation(animation, StringName("J_Bip_%s_LowerArm" % side), [0.0], [_rotation(-65, 0, 0)])
	return animation


func _make_move() -> Animation:
	var animation := _new_animation(1.0, true)
	_add_position(animation, HIPS, [0.0, 0.25, 0.5, 0.75, 1.0], [Vector3.ZERO, Vector3(0, 0.018, 0), Vector3.ZERO, Vector3(0, 0.018, 0), Vector3.ZERO])
	# Swing the bent leg forward along the rig's +Z facing direction.
	_add_rotation(animation, LEFT_UPPER_LEG, [0.0, 0.5, 1.0], [_rotation(-22, 0, 0), _rotation(22, 0, 0), _rotation(-22, 0, 0)])
	_add_rotation(animation, RIGHT_UPPER_LEG, [0.0, 0.5, 1.0], [_rotation(22, 0, 0), _rotation(-22, 0, 0), _rotation(22, 0, 0)])
	_add_rotation(animation, LEFT_LOWER_LEG, [0.0, 0.25, 0.5, 1.0], [_rotation(-5, 0, 0), _rotation(-48, 0, 0), _rotation(-5, 0, 0), _rotation(-5, 0, 0)])
	_add_rotation(animation, RIGHT_LOWER_LEG, [0.0, 0.5, 0.75, 1.0], [_rotation(-5, 0, 0), _rotation(-5, 0, 0), _rotation(-48, 0, 0), _rotation(-5, 0, 0)])
	_add_rotation(animation, LEFT_FOOT, [0.0, 0.5, 1.0], [_rotation(-8, 0, 0), _rotation(10, 0, 0), _rotation(-8, 0, 0)])
	_add_rotation(animation, RIGHT_FOOT, [0.0, 0.5, 1.0], [_rotation(10, 0, 0), _rotation(-8, 0, 0), _rotation(10, 0, 0)])
	_add_rotation(animation, CHEST, [0.0, 0.5, 1.0], [_rotation(-3, -2, 1), _rotation(-3, 2, -1), _rotation(-3, -2, 1)])
	_add_grip(animation)
	return animation


func _make_aim() -> Animation:
	var animation := _new_animation(0.5, false)
	_add_rotation(animation, SPINE, [0.0, 0.5], [Quaternion.IDENTITY, _rotation(-3, 0, 0)])
	_add_rotation(animation, CHEST, [0.0, 0.5], [Quaternion.IDENTITY, _rotation(-5, 0, 0)])
	_add_rotation(animation, HEAD, [0.0, 0.5], [Quaternion.IDENTITY, _rotation(2, 0, -5)])
	_add_grip(animation)
	return animation


func _make_shoot() -> Animation:
	var animation := _new_animation(0.32, false)
	_add_rotation(animation, CHEST, [0.0, 0.07, 0.18, 0.32], [_rotation(-5, 0, 0), _rotation(-15, 8, -4), _rotation(-4, 8, 1), _rotation(-5, 0, 0)])
	_add_rotation(animation, HEAD, [0.0, 0.07, 0.32], [_rotation(2, 0, -5), _rotation(-2, -5, 0), _rotation(2, 0, -5)])
	_add_grip(animation)
	return animation


func _make_hit() -> Animation:
	var animation := _new_animation(0.55, false)
	_add_rotation(animation, HIPS, [0.0, 0.12, 0.32, 0.55], [Quaternion.IDENTITY, _rotation(0, -7, -4), _rotation(0, 4, 2), Quaternion.IDENTITY])
	_add_rotation(animation, CHEST, [0.0, 0.12, 0.32, 0.55], [Quaternion.IDENTITY, _rotation(20, -24, -18), _rotation(-7, 12, 8), Quaternion.IDENTITY])
	_add_rotation(animation, HEAD, [0.0, 0.12, 0.55], [Quaternion.IDENTITY, _rotation(-8, 10, 8), Quaternion.IDENTITY])
	_add_grip(animation)
	return animation


func _make_defeat() -> Animation:
	var animation := _new_animation(1.2, false)
	_add_rotation(animation, HIPS, [0.0, 0.3, 1.2], [Quaternion.IDENTITY, _rotation(4, 0, -5), _rotation(7, 0, -10)])
	_add_rotation(animation, CHEST, [0.0, 0.3, 0.72, 1.2], [Quaternion.IDENTITY, _rotation(12, 5, -5), _rotation(22, -6, -12), _rotation(18, -8, -18)])
	_add_rotation(animation, HEAD, [0.0, 0.3, 1.2], [Quaternion.IDENTITY, _rotation(-10, 8, 4), _rotation(15, -10, 10)])
	_add_rotation(animation, LEFT_UPPER_LEG, [0.0, 1.2], [Quaternion.IDENTITY, _rotation(-8, 4, 0)])
	_add_rotation(animation, RIGHT_UPPER_LEG, [0.0, 1.2], [Quaternion.IDENTITY, _rotation(10, -4, 0)])
	_add_grip(animation)
	return animation


func _add_grip(animation: Animation) -> void:
	for side in ["L", "R"]:
		var direction := -1.0 if side == "L" else 1.0
		for finger in ["Index", "Middle", "Ring", "Little"]:
			for joint in [1, 2, 3]:
				var bone := StringName("J_Bip_%s_%s%d" % [side, finger, joint])
				_add_rotation(animation, bone, [0.0], [_rotation(0, 0, 42.0 * direction if joint == 1 else 58.0 * direction)])
		for joint in [1, 2, 3]:
			var thumb := StringName("J_Bip_%s_Thumb%d" % [side, joint])
			_add_rotation(animation, thumb, [0.0], [_rotation(0, 18.0 * direction, 22.0 * direction)])


func _new_animation(length: float, looping: bool) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	return animation


func _add_rotation(animation: Animation, bone: StringName, times: Array, values: Array) -> void:
	var bone_index := skeleton.find_bone(bone)
	if bone_index < 0:
		return
	var rest_rotation := skeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion()
	var track := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, NodePath(".:%s" % bone))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	for index in times.size():
		animation.rotation_track_insert_key(track, float(times[index]), rest_rotation * values[index])


func _add_position(animation: Animation, bone: StringName, times: Array, values: Array) -> void:
	var bone_index := skeleton.find_bone(bone)
	if bone_index < 0:
		return
	var rest_position := skeleton.get_bone_rest(bone_index).origin
	var track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, NodePath(".:%s" % bone))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	for index in times.size():
		animation.position_track_insert_key(track, float(times[index]), rest_position + values[index])


func _rotation(x_degrees: float, y_degrees: float, z_degrees: float) -> Quaternion:
	return Quaternion.from_euler(Vector3(deg_to_rad(x_degrees), deg_to_rad(y_degrees), deg_to_rad(z_degrees)))

