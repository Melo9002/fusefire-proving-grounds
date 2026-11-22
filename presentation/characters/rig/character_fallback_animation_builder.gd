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
var left_toes: StringName
var right_toes: StringName
var _bones: RigBones
## This body's leg over the reference body's (RigBones.body_ratio): the gait's pelvis motion is authored in metres for the reference body and scales with the leg.
var body_ratio := 1.0

## The bones come from the rig's profile (RigBones): the builder names none.
func _init(target_skeleton: Skeleton3D, rig_bones: RigBones) -> void:
	skeleton = target_skeleton
	_bones = rig_bones
	body_ratio = rig_bones.body_ratio(target_skeleton)
	hips = rig_bones.hips
	spine = rig_bones.spine
	chest = rig_bones.torso
	head = rig_bones.head
	left_upper_leg = rig_bones.left_leg[0]
	left_lower_leg = rig_bones.left_leg[1]
	left_foot = rig_bones.left_leg[2]
	right_upper_leg = rig_bones.right_leg[0]
	right_lower_leg = rig_bones.right_leg[1]
	right_foot = rig_bones.right_leg[2]
	left_toes = rig_bones.left_toes
	right_toes = rig_bones.right_toes


func _make_directional_move(direction: Vector2) -> Animation:
	return make_gait(profile.walk, direction)


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
		# CoverCrouchModifier's measured forward axis instead (TacticalCharacterAdapter, CARRY_LEAN_DEGREES).
		angles = [0.0, 0.0, 0.0]
	if moving:
		times = [0.0, 0.5, 1.0]
	_add_rotation(animation, chest, times, [_rotation(angles[0], 0, 0), _rotation(angles[1], 0, 0), _rotation(angles[2], 0, 0)])
	if not moving:
		_add_grip(animation)
	for side in ["L", "R"]:
		# The upper-arm track this clip once carried ((-20, 0, 45) degrees) never reached a MIRA bone: it named "mixamorig_%sUpperArm", and the bone is "mixamorig_%sArm". Resolving the role correctly would
		# have changed the carried pose, so the dead track was dropped to keep the shown pose exactly as it was. Restoring it is an animation decision.
		_add_rotation(animation, _arm_bone(side, "LowerArm"), [0.0], [_rotation(-65, 0, 0)])
	return animation


func _make_move(loaded := false) -> Animation:
	return make_gait(profile.loaded_walk if loaded else profile.walk, Vector2(0.0, 1.0))


## The forward clips the animation tree blends by speed: "jog" and "run" (ordinary), and "loaded_fast" (a carrier at speed).
func make_forward_clip(kind: StringName) -> Animation:
	match kind:
		&"jog": return make_gait(profile.jog, Vector2(0.0, 1.0))
		&"run": return make_gait(profile.run, Vector2(0.0, 1.0))
		&"loaded_fast": return make_gait(profile.loaded_fast, Vector2(0.0, 1.0))
	return make_gait(profile.walk, Vector2(0.0, 1.0))


## MOVEMENT COORDINATE CONTRACT
##  * The humanoid's anatomical forward is the way its TOES point; measured from the rest pose (ankle to toe base, vertical removed), in
##    skeleton space. Up is hips to head. The hip hinge axis is forward x up.
##  * The visual root (the rig's Character node) faces +Z, the tactical unit turns the rig to its travel direction (TacticalCharacterAdapter
##    .update_locomotion), so for ordinary tactical movement the travel direction IS the anatomical forward.
##  * Locomotion direction is a Vector2 in the character's own frame: x = toward the character's LEFT, y = forward. (0, 1) forward,
##    (0, -1) backward, (1, 0) side-step left, (-1, 0) side-step right.
## The imported bones' local axes are NOT assumed to match this: on the MIRA rig a rotation about a leg bone's local x swings the leg
## SIDEWAYS and the knee's hinge is local z, which is what the old walk got wrong. Every gait rotation here is built as "rotate about the
## hip hinge (or the vertical, or forward)" and converted into each bone's own local axis from its rest orientation.
var profile := LocomotionProfile.new()
var _up := Vector3.UP
var _forward := Vector3.BACK
var _hinge := Vector3.RIGHT
var _axes_measured := false


## Anatomical axes (skeleton space), measured once from the rest pose. Safe to call again.
func measure_axes() -> void:
	var hips_i := skeleton.find_bone(hips)
	var head_i := skeleton.find_bone(head)
	var foot_i := skeleton.find_bone(left_foot)
	var toe_i := skeleton.find_bone(left_toes)
	_axes_measured = true
	if hips_i < 0 or head_i < 0:
		return
	_up = (skeleton.get_bone_global_rest(head_i).origin - skeleton.get_bone_global_rest(hips_i).origin).normalized()
	if foot_i >= 0 and toe_i >= 0:
		var toe := skeleton.get_bone_global_rest(toe_i).origin - skeleton.get_bone_global_rest(foot_i).origin
		toe -= _up * toe.dot(_up)
		if toe.length() > 0.005:
			_forward = toe.normalized()
	_hinge = _forward.cross(_up).normalized()


func anatomical_forward() -> Vector3:
	if not _axes_measured:
		measure_axes()
	return _forward


func anatomical_up() -> Vector3:
	if not _axes_measured:
		measure_axes()
	return _up


func hip_hinge() -> Vector3:
	if not _axes_measured:
		measure_axes()
	return _hinge


## Rotation of `bone` by `degrees` about a skeleton-space axis, as a local rotation (what _add_rotation expects).
func _about(bone: StringName, axis_skeleton: Vector3, degrees: float) -> Quaternion:
	var index := skeleton.find_bone(bone)
	if index < 0:
		return Quaternion.IDENTITY
	var local_axis := skeleton.get_bone_global_rest(index).basis.orthonormalized().inverse() * axis_skeleton
	return Quaternion(local_axis.normalized(), deg_to_rad(degrees))


## A skeleton-space offset as a position offset in the bone's parent frame.
func _local_offset(bone: StringName, offset_skeleton: Vector3) -> Vector3:
	var index := skeleton.find_bone(bone)
	if index < 0:
		return Vector3.ZERO
	var parent := skeleton.get_bone_parent(index)
	var basis := skeleton.get_bone_global_rest(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	return basis.inverse() * offset_skeleton


## One looping stride (1 s; the controller scales it to speed). `direction`: x toward the character's left, y forward (see contract).
func make_gait(g: LocomotionGait, direction: Vector2) -> Animation:
	if not _axes_measured:
		measure_axes()
	var animation := _new_animation(1.0, true)
	var keys := 16
	var times := []
	for k in keys + 1:
		times.append(k / float(keys))
	var forward_weight := absf(direction.y)
	var side_weight := absf(direction.x)
	var reverse := direction.y < 0.0
	var amplitude := g.backward_scale if reverse else 1.0
	var lateral := _up.cross(_forward)   # toward the character's left
	var legs := [[left_upper_leg, left_lower_leg, left_foot, 0.0, 1.0], [right_upper_leg, right_lower_leg, right_foot, 0.5, -1.0]]
	for leg in legs:
		var thigh_values := []
		var knee_values := []
		var ankle_values := []
		for t in times:
			var phase := fposmod(float(t) + float(leg[3]), 1.0)
			var table_phase := 1.0 - phase if reverse else phase
			var hip := LocomotionGait.sample(g.thigh_table, table_phase) * g.hip_scale * amplitude * forward_weight
			var knee := LocomotionGait.sample(g.knee_table, table_phase) * g.knee_scale * amplitude * forward_weight
			var ankle := LocomotionGait.sample(g.ankle_table, table_phase) * g.ankle_scale * amplitude * forward_weight
			# Keep the foot level while it carries weight: cancel the shin's pitch, fading out through push-off and swing.
			var flat := clampf(-hip + knee, -35.0, 35.0) * _stance_weight(table_phase, g.stance_fraction)
			var side_phase := 0.5 - 0.5 * cos(TAU * phase)
			var side_swing := g.side_step_degrees * side_phase * signf(direction.x) * side_weight
			var side_knee := g.side_step_knee_degrees * side_phase * side_phase * side_weight
			var spread := g.stance_spread_degrees * float(leg[4])
			# Side stepping moves the leg out and back in the frontal plane (about forward), with a lifted knee.
			thigh_values.append(_about(leg[0], _hinge, hip) * _about(leg[0], _forward, side_swing + spread))
			knee_values.append(_about(leg[1], _hinge, -maxf(knee, 0.0) - side_knee))
			ankle_values.append(_about(leg[2], _hinge, ankle + flat * forward_weight + side_knee * 0.5))
		_add_rotation(animation, leg[0], times, thigh_values)
		_add_rotation(animation, leg[1], times, knee_values)
		_add_rotation(animation, leg[2], times, ankle_values)
	# Pelvis: highest at mid-stance, shifted over the stance leg, turned toward the swinging leg; the chest counter-rotates.
	var hip_positions := []
	var pelvis_rotations := []
	var chest_rotations := []
	for t in times:
		var bob := g.pelvis_bob * body_ratio * (1.0 + cos(2.0 * TAU * (float(t) - g.bob_peak_phase))) * 0.5
		var sway := g.pelvis_sway * body_ratio * sin(TAU * float(t))
		hip_positions.append(_local_offset(hips, _up * bob + lateral * sway * forward_weight))
		var yaw := -g.pelvis_yaw_degrees * cos(TAU * float(t)) * forward_weight * (-1.0 if reverse else 1.0)
		pelvis_rotations.append(_about(hips, _up, yaw))
		chest_rotations.append(_about(chest, _up, -g.torso_counter_rotation * yaw))
	if g.forward_lean_degrees > 0.0:
		# A held forward lean of the trunk (running): the spine pitches about the hip hinge, forward being the way the hips swing the leg back.
		var lean_rotations := []
		for t in times:
			lean_rotations.append(_about(spine, _hinge, -g.forward_lean_degrees * forward_weight))
		_add_rotation(animation, spine, times, lean_rotations)
	_add_position(animation, hips, times, hip_positions)
	_add_rotation(animation, hips, times, pelvis_rotations)
	_add_rotation(animation, chest, times, chest_rotations)
	_add_grip(animation)
	return animation


## How much of the foot-flat compensation applies at a point of the cycle: full while the foot carries weight, fading through push-off (the end of
## stance), off in the swing, coming back for the approach to contact.
static func _stance_weight(phase: float, stance_fraction: float) -> float:
	var push_off := stance_fraction
	if phase < 0.08:
		return lerpf(0.6, 1.0, phase / 0.08)
	if phase < push_off - 0.1:
		return 1.0
	if phase < push_off:
		return lerpf(1.0, 0.2, (phase - (push_off - 0.1)) / 0.1)
	if phase < push_off + 0.12:
		return lerpf(0.2, 0.0, (phase - push_off) / 0.12)
	if phase < 0.88:
		return 0.0
	return lerpf(0.0, 0.6, (phase - 0.88) / 0.12)


## A shot with the body leaning to one side to look round a corner: side -1 leans toward the character's LEFT, +1 toward its right (the clips are named
## shoot_left / shoot_right). The hip shift is built on the measured anatomical axes (a bone-local x offset moved the hips the wrong way, and further).
func make_lean_shot(side: int) -> Animation:
	if not _axes_measured:
		measure_axes()
	var shot := _make_shoot()
	var lateral := _up.cross(_forward)   # toward the character's left
	var lean := [0.10, 0.14, 0.10]
	# Bone positions are in the skeleton's own units (the model is scaled up in the rig), so the metres are divided by that scale.
	var unit := maxf(skeleton.global_basis.get_scale().y if skeleton.is_inside_tree() else 1.0, 0.01)
	var offsets := []
	for amount in lean:
		offsets.append(_local_offset(hips, (lateral * (-float(side) * amount) - _up * 0.03) / unit))
	_add_position(shot, hips, [0.0, 0.07, 0.32], offsets)
	return shot


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


## A one-shot gesture (CharacterAnimationController.GESTURES). Gestures are authored as DIRECTIONS in the body's own frame (up, forward, the hip hinge), never as per-bone euler angles, so one recipe fits every humanoid
## whatever its rest pose and bone axes. They start and end at rest, so the crossfades in and out are short. The ARMS are not in a clip: the rig's arm stage places them from IK targets after the clip (see
## CharacterRig.apply_relaxed_hand_targets and CharacterPresenter.gesture_hand), so a gesture that needs a hand asks for it there.
func make_gesture(gesture: StringName) -> Animation:
	match gesture:
		&"acknowledge":
			return _make_acknowledge()
	push_warning("No recipe for the gesture %s" % gesture)
	return _new_animation(0.5, false)


const ACKNOWLEDGE_SECONDS := 1.7


## A nod and a settling of the torso (the raised hand of an unarmed character is the rig's: it comes from the hand target while this plays).
func _make_acknowledge() -> Animation:
	if not _axes_measured:
		measure_axes()
	var animation := _new_animation(ACKNOWLEDGE_SECONDS, false)
	var times := [0.0, 0.35, 0.7, 1.0, 1.35, ACKNOWLEDGE_SECONDS]
	_add_rotation(animation, head, times, [Quaternion.IDENTITY, _about(head, _hinge, 9.0), _about(head, _hinge, -3.0), _about(head, _hinge, 6.0), _about(head, _hinge, -2.0), Quaternion.IDENTITY])
	_add_rotation(animation, chest, times, [Quaternion.IDENTITY, _about(chest, _hinge, 3.0), _about(chest, _hinge, 1.5), _about(chest, _hinge, 3.0), _about(chest, _hinge, 1.5), Quaternion.IDENTITY])
	_add_grip(animation)
	return animation


func _add_grip(animation: Animation, sides: Array = ["L", "R"]) -> void:
	for side in sides:
		var direction := -1.0 if side == "L" else 1.0
		for finger in ["Index", "Middle", "Ring", "Little"]:
			for joint in [1, 2, 3]:
				var bone := _finger_bone(side, finger, joint)
				_add_rotation(animation, bone, [0.0], [_rotation(0, 0, 42.0 * direction if joint == 1 else 58.0 * direction)])
		for joint in [1, 2, 3]:
			var thumb := _finger_bone(side, "Thumb", joint)
			_add_rotation(animation, thumb, [0.0], [_rotation(0, 18.0 * direction, 22.0 * direction)])


func _arm_bone(side: String, part: String) -> StringName:
	var arm := _bones.left_arm if side == "L" else _bones.right_arm
	return arm[0] if part == "UpperArm" else (arm[1] if part == "LowerArm" else arm[2])


func _finger_bone(side: String, finger_name: String, joint: int) -> StringName:
	return _bones.finger("Left" if side == "L" else "Right", "Little" if finger_name == "Pinky" else finger_name, joint)


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
