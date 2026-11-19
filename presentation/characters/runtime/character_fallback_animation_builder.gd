class_name CharacterFallbackAnimationBuilder
extends RefCounted
## Procedural safety-net clips for rigs missing authored animations.
## Runtime playback and state transitions belong to character_animation_controller.gd.

var skeleton: Skeleton3D
var hips: StringName
var spine: StringName
var chest: StringName
var head: StringName
var left_upper_leg: StringName
var left_lower_leg: StringName
var left_foot: StringName
var right_upper_leg: StringName
var right_lower_leg: StringName
var right_foot: StringName
var _mixamo := false

func _init(target_skeleton: Skeleton3D) -> void:
	skeleton = target_skeleton
	_mixamo = skeleton.find_bone(&"mixamorig_Hips") >= 0
	hips = &"mixamorig_Hips" if _mixamo else &"J_Bip_C_Hips"
	spine = &"mixamorig_Spine" if _mixamo else &"J_Bip_C_Spine"
	chest = &"mixamorig_Spine2" if _mixamo else &"J_Bip_C_Chest"
	head = &"mixamorig_Head" if _mixamo else &"J_Bip_C_Head"
	left_upper_leg = &"mixamorig_LeftUpLeg" if _mixamo else &"J_Bip_L_UpperLeg"
	left_lower_leg = &"mixamorig_LeftLeg" if _mixamo else &"J_Bip_L_LowerLeg"
	left_foot = &"mixamorig_LeftFoot" if _mixamo else &"J_Bip_L_Foot"
	right_upper_leg = &"mixamorig_RightUpLeg" if _mixamo else &"J_Bip_R_UpperLeg"
	right_lower_leg = &"mixamorig_RightLeg" if _mixamo else &"J_Bip_R_LowerLeg"
	right_foot = &"mixamorig_RightFoot" if _mixamo else &"J_Bip_R_Foot"


func _make_directional_move(direction: Vector2) -> Animation:
	var animation := _make_move()
	# Re-author thigh swing in travel direction, keeping knee flexion anatomical.
	# Lift happens during the first half-cycle for the left leg and second for right.
	for side in ["L", "R"]:
		var bone := left_upper_leg if side == "L" else right_upper_leg
		var track := animation.find_track(NodePath(".:%s" % bone), Animation.TYPE_ROTATION_3D)
		animation.remove_track(track)
		var sign_value := 1.0 if side == "L" else -1.0
		var start := _rotation(-22.0 * direction.y * sign_value, 0, 18.0 * direction.x * sign_value)
		var end := _rotation(22.0 * direction.y * sign_value, 0, -18.0 * direction.x * sign_value)
		_add_rotation(animation, bone, [0.0, 0.5, 1.0], [start, end, start])
	return animation


func _make_idle() -> Animation:
	var animation := _new_animation(2.0, true)
	_add_rotation(animation, chest, [0.0, 1.0, 2.0], [_rotation(0.0, 0.0, -1.0), _rotation(-2.4, 0.0, 1.5), _rotation(0.0, 0.0, -1.0)])
	_add_rotation(animation, head, [0.0, 1.0, 2.0], [_rotation(0.0, -1.0, 0.0), _rotation(0.8, 1.0, 0.0), _rotation(0.0, -1.0, 0.0)])
	_add_grip(animation)
	return animation


const SPREAD_SIGN := 1.0

func _make_tactical_pose(pose: StringName) -> Animation:
	# Blocking poses: knee flexion stays negative on this imported rig.
	# Root travel is supplied by the tactical path, never by these clips.
	var landing := pose == &"land"
	var animation := _new_animation(0.3 if landing else 0.8, not landing)
	var crouch := 0.135 if pose == &"cover_low" else 0.012
	var thigh := 55.0 if pose == &"cover_low" else 10.0
	var knee := -105.0 if pose == &"cover_low" else -20.0
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
	_add_position(animation, hips, times, [Vector3(0, -crouch, 0), Vector3(0, -crouch - 0.015, 0), Vector3.ZERO if landing else Vector3(0, -crouch, 0)])
	for side in ["L", "R"]:
		var upper := left_upper_leg if side == "L" else right_upper_leg
		var lower := left_lower_leg if side == "L" else right_lower_leg
		var foot := left_foot if side == "L" else right_foot
		var alternating := pose in [&"climb", &"descend"]
		var a := thigh * (0.35 if alternating and side == "R" else 1.0)
		var b := thigh * (0.35 if alternating and side == "L" else 1.0)
		# Mirrored hip abduction: a deep crouch needs the knees apart, not pinched under the hips.
		var spread := (SPREAD_SIGN if side == "L" else -SPREAD_SIGN) * 0.0
		_add_rotation(animation, upper, times, [_rotation(a, 0, spread), _rotation(b, 0, spread), Quaternion.IDENTITY if landing else _rotation(a, 0, spread)])
		_add_rotation(animation, lower, times, [_rotation(knee, 0, 0), _rotation(knee * 0.8, 0, 0), Quaternion.IDENTITY if landing else _rotation(knee, 0, 0)])
		_add_rotation(animation, foot, times, [_rotation(-a - knee, 0, 0), _rotation(-b - knee * 0.8, 0, 0), Quaternion.IDENTITY if landing else _rotation(-a - knee, 0, 0)])
	_add_rotation(animation, chest, [0.0], [_rotation(-5, 12, -6) if pose == &"cover_high" else _rotation(-8, 0, 0)])
	_add_grip(animation)
	return animation

func _make_rescue_pose(pose: StringName) -> Animation:
	var moving := pose == &"carry_move"
	var animation := _make_move(true) if moving else _new_animation(0.6, pose == &"carry_idle")
	if moving:
		animation.remove_track(animation.find_track(NodePath(".:%s" % chest), Animation.TYPE_ROTATION_3D))
	var times := [0.0, 0.3, 0.6]
	var angles := [-10.0, -12.0, -10.0]
	if pose == &"pickup":
		angles = [-5.0, -35.0, -10.0]
	elif pose == &"boarding":
		angles = [-10.0, -30.0, -5.0]
	if pose == &"carry_idle" or pose == &"carry_move":
		# Pitching the chest about its own x axis leaned the carrier sideways on this rig. The carry's forward lean comes from
		# CoverCrouchModifier's measured forward axis instead (UnitVisualAdapter, CARRY_LEAN_DEGREES).
		angles = [0.0, 0.0, 0.0]
	if moving:
		times = [0.0, 0.5, 1.0]
	_add_rotation(animation, chest, times, [_rotation(angles[0], 0, 0), _rotation(angles[1], 0, 0), _rotation(angles[2], 0, 0)])
	if not moving:
		_add_grip(animation)
	for side in ["L", "R"]:
		var sign_value := -1.0 if side == "L" else 1.0
		_add_rotation(animation, _arm_bone(side, "UpperArm"), [0.0], [_rotation(-20, 0, 45 * sign_value)])
		_add_rotation(animation, _arm_bone(side, "LowerArm"), [0.0], [_rotation(-65, 0, 0)])
	return animation


## The loaded gait (carry_move): what changes from the unloaded walk, in one place. Presentation only; speed and action costs are
## the tactical layer's. A narrower, shorter step with the knee lifted less, a smaller bob and a steadier trunk, because the
## carrier is a capable android under a load, not a tired person: nothing here sags or drags.
const LOADED_GAIT := {
	"thigh_swing": 14.0,     # degrees either side of vertical (unloaded 22)
	"knee_lift": -36.0,      # swing-leg knee flexion at its peak (unloaded -48)
	"foot_swing": 7.0,       # ankle rock (unloaded 10 and -8)
	"bob": 0.010,            # hip rise per step, metres (unloaded 0.018)
	"trunk_sway": Vector3(-1.5, 1.2, 0.6),   # chest rotation at the ends of the cycle, degrees (unloaded -3, 2, 1)
}

func _make_move(loaded := false) -> Animation:
	var animation := _new_animation(1.0, true)
	if loaded:
		var g := LOADED_GAIT
		var swing: float = g.thigh_swing
		var knee: float = g.knee_lift
		var foot: float = g.foot_swing
		var bob: float = g.bob
		var sway: Vector3 = g.trunk_sway
		_add_position(animation, hips, [0.0, 0.25, 0.5, 0.75, 1.0], [Vector3.ZERO, Vector3(0, bob, 0), Vector3.ZERO, Vector3(0, bob, 0), Vector3.ZERO])
		_add_rotation(animation, left_upper_leg, [0.0, 0.5, 1.0], [_rotation(-swing, 0, 0), _rotation(swing, 0, 0), _rotation(-swing, 0, 0)])
		_add_rotation(animation, right_upper_leg, [0.0, 0.5, 1.0], [_rotation(swing, 0, 0), _rotation(-swing, 0, 0), _rotation(swing, 0, 0)])
		_add_rotation(animation, left_lower_leg, [0.0, 0.25, 0.5, 1.0], [_rotation(-5, 0, 0), _rotation(knee, 0, 0), _rotation(-5, 0, 0), _rotation(-5, 0, 0)])
		_add_rotation(animation, right_lower_leg, [0.0, 0.5, 0.75, 1.0], [_rotation(-5, 0, 0), _rotation(-5, 0, 0), _rotation(knee, 0, 0), _rotation(-5, 0, 0)])
		_add_rotation(animation, left_foot, [0.0, 0.5, 1.0], [_rotation(-foot, 0, 0), _rotation(foot, 0, 0), _rotation(-foot, 0, 0)])
		_add_rotation(animation, right_foot, [0.0, 0.5, 1.0], [_rotation(foot, 0, 0), _rotation(-foot, 0, 0), _rotation(foot, 0, 0)])
		_add_rotation(animation, chest, [0.0, 0.5, 1.0], [_rotation(sway.x, -sway.y, sway.z), _rotation(sway.x, sway.y, -sway.z), _rotation(sway.x, -sway.y, sway.z)])
		_add_grip(animation)
		return animation
	_add_position(animation, hips, [0.0, 0.25, 0.5, 0.75, 1.0], [Vector3.ZERO, Vector3(0, 0.018, 0), Vector3.ZERO, Vector3(0, 0.018, 0), Vector3.ZERO])
	# Swing the bent leg forward along the rig's +Z facing direction.
	_add_rotation(animation, left_upper_leg, [0.0, 0.5, 1.0], [_rotation(-22, 0, 0), _rotation(22, 0, 0), _rotation(-22, 0, 0)])
	_add_rotation(animation, right_upper_leg, [0.0, 0.5, 1.0], [_rotation(22, 0, 0), _rotation(-22, 0, 0), _rotation(22, 0, 0)])
	_add_rotation(animation, left_lower_leg, [0.0, 0.25, 0.5, 1.0], [_rotation(-5, 0, 0), _rotation(-48, 0, 0), _rotation(-5, 0, 0), _rotation(-5, 0, 0)])
	_add_rotation(animation, right_lower_leg, [0.0, 0.5, 0.75, 1.0], [_rotation(-5, 0, 0), _rotation(-5, 0, 0), _rotation(-48, 0, 0), _rotation(-5, 0, 0)])
	_add_rotation(animation, left_foot, [0.0, 0.5, 1.0], [_rotation(-8, 0, 0), _rotation(10, 0, 0), _rotation(-8, 0, 0)])
	_add_rotation(animation, right_foot, [0.0, 0.5, 1.0], [_rotation(10, 0, 0), _rotation(-8, 0, 0), _rotation(10, 0, 0)])
	_add_rotation(animation, chest, [0.0, 0.5, 1.0], [_rotation(-3, -2, 1), _rotation(-3, 2, -1), _rotation(-3, -2, 1)])
	_add_grip(animation)
	return animation


func _make_aim() -> Animation:
	var animation := _new_animation(0.5, false)
	_add_rotation(animation, spine, [0.0, 0.5], [Quaternion.IDENTITY, _rotation(-3, 0, 0)])
	_add_rotation(animation, chest, [0.0, 0.5], [Quaternion.IDENTITY, _rotation(-5, 0, 0)])
	_add_rotation(animation, head, [0.0, 0.5], [Quaternion.IDENTITY, _rotation(2, 0, -5)])
	_add_grip(animation)
	return animation


func _make_shoot() -> Animation:
	var animation := _new_animation(0.32, false)
	_add_rotation(animation, chest, [0.0, 0.07, 0.18, 0.32], [_rotation(-5, 0, 0), _rotation(-15, 8, -4), _rotation(-4, 8, 1), _rotation(-5, 0, 0)])
	_add_rotation(animation, head, [0.0, 0.07, 0.32], [_rotation(2, 0, -5), _rotation(-2, -5, 0), _rotation(2, 0, -5)])
	_add_grip(animation)
	return animation


func _make_hit() -> Animation:
	var animation := _new_animation(0.55, false)
	_add_rotation(animation, hips, [0.0, 0.12, 0.32, 0.55], [Quaternion.IDENTITY, _rotation(0, -7, -4), _rotation(0, 4, 2), Quaternion.IDENTITY])
	_add_rotation(animation, chest, [0.0, 0.12, 0.32, 0.55], [Quaternion.IDENTITY, _rotation(20, -24, -18), _rotation(-7, 12, 8), Quaternion.IDENTITY])
	_add_rotation(animation, head, [0.0, 0.12, 0.55], [Quaternion.IDENTITY, _rotation(-8, 10, 8), Quaternion.IDENTITY])
	_add_grip(animation)
	return animation


func _make_defeat() -> Animation:
	var animation := _new_animation(1.2, false)
	_add_rotation(animation, hips, [0.0, 0.3, 1.2], [Quaternion.IDENTITY, _rotation(4, 0, -5), _rotation(7, 0, -10)])
	_add_rotation(animation, chest, [0.0, 0.3, 0.72, 1.2], [Quaternion.IDENTITY, _rotation(12, 5, -5), _rotation(22, -6, -12), _rotation(18, -8, -18)])
	_add_rotation(animation, head, [0.0, 0.3, 1.2], [Quaternion.IDENTITY, _rotation(-10, 8, 4), _rotation(15, -10, 10)])
	_add_rotation(animation, left_upper_leg, [0.0, 1.2], [Quaternion.IDENTITY, _rotation(-8, 4, 0)])
	_add_rotation(animation, right_upper_leg, [0.0, 1.2], [Quaternion.IDENTITY, _rotation(10, -4, 0)])
	_add_grip(animation)
	return animation


func _add_grip(animation: Animation) -> void:
	for side in ["L", "R"]:
		var direction := -1.0 if side == "L" else 1.0
		for finger in ["Index", "Middle", "Ring", "Little"]:
			for joint in [1, 2, 3]:
				var bone := _finger_bone(side, finger, joint)
				_add_rotation(animation, bone, [0.0], [_rotation(0, 0, 42.0 * direction if joint == 1 else 58.0 * direction)])
		for joint in [1, 2, 3]:
			var thumb := _finger_bone(side, "Thumb", joint)
			_add_rotation(animation, thumb, [0.0], [_rotation(0, 18.0 * direction, 22.0 * direction)])


func _arm_bone(side: String, part: String) -> StringName:
	if _mixamo:
		var full_side := "Left" if side == "L" else "Right"
		var mixamo_part := "ForeArm" if part == "LowerArm" else part
		return StringName("mixamorig_%s%s" % [full_side, mixamo_part])
	return StringName("J_Bip_%s_%s" % [side, part])


func _finger_bone(side: String, finger: String, joint: int) -> StringName:
	if _mixamo:
		var full_side := "Left" if side == "L" else "Right"
		return StringName("mixamorig_%sHand%s%d" % [full_side, finger, joint])
	return StringName("J_Bip_%s_%s%d" % [side, finger, joint])


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
