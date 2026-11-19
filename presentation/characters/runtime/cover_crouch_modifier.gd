class_name CoverCrouchModifier
extends SkeletonModifier3D
## Procedural crouch layer. Lowers the hips by `depth` metres while both feet stay planted, by
## solving the two-bone legs (thigh + shin), levelling the feet, moving the hips back over the
## heels and leaning the spine forward, as a person does in a deep crouch. Presentation only.
##
## Human limits are built in: knee flexion, hip flexion and shin lean are capped, so asking for
## more depth than a body can give stops at the deepest natural crouch (`max_depth`).
##
## Imported skeletons disagree about which local axis bends a limb forward, so setup() measures
## it from the rest pose and the character's forward direction instead of assuming one.

const MAX_KNEE_FLEXION := deg_to_rad(130.0)
const MAX_HIP_FLEXION := deg_to_rad(95.0)
## Shin lean from vertical with the heel down (ankle dorsiflexion limit).
const MAX_SHIN_LEAN := deg_to_rad(50.0)
## Balance: the hips move back until the body's centre of mass is this far ahead of the ankles
## (over the middle of the foot), measured along the facing direction.
const BALANCE_TARGET_AHEAD := 0.05
const MAX_HIPS_BACK := 0.30
## Rough mass shares: head + torso + arms + rifle, thighs, shins, feet.
const MASS_UPPER := 0.64
const MASS_THIGHS := 0.20
const MASS_SHINS := 0.12
const MASS_FEET := 0.04
## Where the upper body's centre of mass sits along the hip-to-head line.
const UPPER_COM_FRACTION := 0.6
## Spine forward lean per metre of depth, capped.
const LEAN_DEGREES_PER_METRE := 85.0
const MAX_LEAN_DEGREES := 40.0

## Half-kneel, for cover lower than a crouch can hide behind: the front foot stays planted, the
## rear knee goes down. The hips are placed from the leg geometry, so it needs no tuning per body.
const KNEEL_REAR_THIGH_BACK := deg_to_rad(8.0)
const KNEEL_REAR_SHIN_BACK := deg_to_rad(80.0)
const KNEEL_KNEE_HEIGHT := 0.06
const KNEEL_FRONT_SHIN_LEAN := deg_to_rad(10.0)
const KNEEL_LEAN_DEGREES := 22.0
## How far the resting rear foot points its toes down from "flat".
const KNEEL_TOE_DEGREES := 55.0

## Requested hip drop in metres. Clamped to max_depth.
var depth := 0.0
## Extra forward lean of the torso, degrees, independent of any crouch (aiming leans into the rifle,
## which also brings the support hand to the front handle).
var aim_lean_degrees := 0.0
## The support-side shoulder reaches forward (shoulder-blade protraction), degrees. Lengthens the
## support arm's reach to the front handle without bending the torso further.
var support_reach_degrees := 0.0
## 0 = crouch, 1 = half-kneel. Blends the two.
var kneel := 0.0
## Which leg goes down in the kneel: 0 = left, 1 = right (right-handed shooter).
var kneel_leg := 1
## Deepest natural crouch for this body, metres. Valid after setup().
var max_depth := 0.0
## Standing head-top height above the ankle-height floor, metres. Valid after setup().
var standing_head_height := 0.0

var _hips := -1
var _upper: Array[int] = []
var _lower: Array[int] = []
var _foot: Array[int] = []
var _spine: Array[int] = []
var _support_clavicle := -1
## Per bone: the local axis (sign included) whose positive rotation swings the child joint forward.
var _forward_axis := {}
var _forward_skeleton := Vector3.BACK
var _upper_length := 0.0
var _lower_length := 0.0
var _hip_to_ankle := 0.0
var _ankle_height := 0.0
var _kneel_drop := 0.0
var _kneel_back := 0.0
var _kneel_front := {}
var _scale := 1.0

## `forward_world` is the character's facing direction in world space.
func setup(target: Skeleton3D, bones: Dictionary, forward_world: Vector3) -> bool:
	_hips = target.find_bone(bones.hips)
	for side in ["left", "right"]:
		_upper.append(target.find_bone(bones[side + "_upper"]))
		_lower.append(target.find_bone(bones[side + "_lower"]))
		_foot.append(target.find_bone(bones[side + "_foot"]))
	for bone_name in bones.spine:
		_spine.append(target.find_bone(bone_name))
	var top := target.find_bone(bones.head_top)
	if _hips < 0 or top < 0 or _upper.has(-1) or _lower.has(-1) or _foot.has(-1) or _spine.has(-1):
		return false
	_refresh_scale(target)
	_support_clavicle = target.find_bone(bones.get("support_clavicle", &""))
	_forward_skeleton = (target.global_basis.inverse() * forward_world).normalized()
	var chain: Array[int] = []
	chain.append_array(_upper)
	chain.append_array(_lower)
	chain.append_array(_foot)
	for index in _upper.size():
		_forward_axis[_upper[index]] = _measure_axis(target, _upper[index], _lower[index])
		_forward_axis[_lower[index]] = _measure_axis(target, _lower[index], _foot[index])
		# The foot has no useful child: swing a point straight below the ankle instead.
		_forward_axis[_foot[index]] = _measure_axis(target, _foot[index], -1)
	for index in _spine.size():
		var next := _spine[index + 1] if index + 1 < _spine.size() else target.find_bone(bones.head_top)
		_forward_axis[_spine[index]] = _measure_axis(target, _spine[index], next)
	if _support_clavicle >= 0:
		_forward_axis[_support_clavicle] = _measure_axis(target, _support_clavicle, target.find_bone(bones.get("support_arm", &"")))
	var hip := target.get_bone_global_rest(_upper[0]).origin
	var knee := target.get_bone_global_rest(_lower[0]).origin
	var ankle := target.get_bone_global_rest(_foot[0]).origin
	_upper_length = hip.distance_to(knee) * _scale
	_lower_length = knee.distance_to(ankle) * _scale
	_hip_to_ankle = (hip.y - ankle.y) * _scale
	standing_head_height = (target.get_bone_global_rest(top).origin.y - ankle.y) * _scale
	_ankle_height = ankle.y * _scale
	max_depth = _find_max_depth()
	_solve_kneel()
	return true

## Half-kneel geometry. The rear knee rests on the ground under the hip, so the hip height follows
## from the thigh length; the front leg is then solved with its shin leaning slightly forward.
func _solve_kneel() -> void:
	var hip_height := _upper_length * cos(KNEEL_REAR_THIGH_BACK) + KNEEL_KNEE_HEIGHT
	_kneel_drop = _hip_to_ankle + _ankle_height - hip_height
	var best_error := INF
	var back := 0.0
	while back <= 0.8:
		var pose := _solve(_kneel_drop, back)
		if pose.ok:
			var error := absf(pose.shin_lean - KNEEL_FRONT_SHIN_LEAN)
			if error < best_error:
				best_error = error
				_kneel_back = back
				_kneel_front = pose
		back += 0.005

func _refresh_scale(target: Skeleton3D) -> void:
	_scale = target.global_basis.get_scale().y if target.is_inside_tree() else 1.0
	if _scale <= 0.0001:
		_scale = 1.0

## The local axis, signed, that swings `child` forward when the bone rotates positively about it.
func _measure_axis(target: Skeleton3D, bone: int, child: int) -> Vector3:
	if bone < 0:
		return Vector3.RIGHT
	var basis := target.get_bone_global_rest(bone).basis
	var offset := target.get_bone_rest(child).origin if child >= 0 else basis.inverse() * (Vector3.DOWN * 0.1 / _scale)
	var best := Vector3.RIGHT
	var best_score := 0.0
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var moved: Vector3 = basis * (Quaternion(axis, 0.2) * offset - offset)
		var score := moved.dot(_forward_skeleton)
		if absf(score) > absf(best_score):
			best_score = score
			best = axis * signf(score)
	return best

## Leg angles for a hip `drop` metres lower and `back` metres behind the ankles, in radians.
func _solve(drop: float, back: float) -> Dictionary:
	var vertical := _hip_to_ankle - drop
	if vertical <= 0.05:
		return {"ok": false}
	var distance := sqrt(vertical * vertical + back * back)
	if distance > _upper_length + _lower_length - 0.0001:
		return {"thigh": 0.0, "knee": 0.0, "shin_lean": 0.0, "ok": true}
	if distance < absf(_upper_length - _lower_length) + 0.01:
		return {"ok": false}
	var interior := acos(clampf((_upper_length * _upper_length + _lower_length * _lower_length - distance * distance) / (2.0 * _upper_length * _lower_length), -1.0, 1.0))
	var knee := PI - interior
	var line := atan2(back, vertical)
	var thigh := line + acos(clampf((distance * distance + _upper_length * _upper_length - _lower_length * _lower_length) / (2.0 * distance * _upper_length), -1.0, 1.0))
	return {"thigh": thigh, "knee": knee, "shin_lean": knee - thigh, "ok": true}

func _within_limits(pose: Dictionary) -> bool:
	return pose.ok and pose.knee <= MAX_KNEE_FLEXION and pose.thigh <= MAX_HIP_FLEXION and pose.shin_lean <= MAX_SHIN_LEAN

func _find_max_depth() -> float:
	var best := 0.0
	var drop := 0.0
	while drop < _hip_to_ankle:
		if not _within_limits(_solve(drop, balanced_back(drop))):
			break
		best = drop
		drop += 0.005
	return best

## Where the whole body's centre of mass lies ahead of the ankles (metres, forward positive) for a
## hip `drop` low, `back` behind the ankles, torso leaning `lean` radians.
func _com_ahead(drop: float, back: float, lean: float) -> float:
	var pose := _solve(drop, back)
	if not pose.ok:
		return -INF
	var hip := Vector2(-back, _hip_to_ankle - drop)
	var knee := hip + Vector2(sin(pose.thigh), -cos(pose.thigh)) * _upper_length
	var upper_length := (standing_head_height - _hip_to_ankle) * UPPER_COM_FRACTION
	var upper := hip + Vector2(sin(lean), cos(lean)) * upper_length
	return (upper.x * MASS_UPPER + (hip.x + knee.x) * 0.5 * MASS_THIGHS + knee.x * 0.5 * MASS_SHINS + 0.06 * MASS_FEET)

## The hip set-back that puts the centre of mass over the feet: a leaning torso needs the hips
## further back, an upright one less. Found by bisection.
func balanced_back(drop: float) -> float:
	var lean := deg_to_rad(lean_degrees(drop))
	if _com_ahead(drop, 0.0, lean) <= BALANCE_TARGET_AHEAD:
		return 0.0
	var low := 0.0
	var high := MAX_HIPS_BACK
	for i in 14:
		var middle := (low + high) * 0.5
		if _com_ahead(drop, middle, lean) > BALANCE_TARGET_AHEAD:
			low = middle
		else:
			high = middle
	return high

## Depth for a requested drop, capped at what a person can do.
func clamp_depth(requested: float) -> float:
	return clampf(requested, 0.0, max_depth)

## Forward lean of the torso for the current depth, degrees.
func current_lean_degrees() -> float:
	return lerpf(lean_degrees(clamp_depth(depth)), KNEEL_LEAN_DEGREES, kneel)

func lean_degrees(for_depth: float) -> float:
	return minf(for_depth * LEAN_DEGREES_PER_METRE, MAX_LEAN_DEGREES)

func _process_modification() -> void:
	var target := get_skeleton()
	if target == null or _hips < 0:
		return
	_apply_support_reach(target)
	if depth <= 0.002 and kneel <= 0.002:
		# Standing: only the aiming lean.
		if aim_lean_degrees > 0.05:
			_apply_lean(target, aim_lean_degrees)
		return
	_refresh_scale(target)
	var applied := clamp_depth(depth)
	var crouch_back := balanced_back(applied)
	var crouch_pose := _solve(applied, crouch_back)
	if not crouch_pose.get("ok", false):
		return
	var weight := clampf(kneel, 0.0, 1.0)
	var drop := lerpf(applied, _kneel_drop, weight) if not _kneel_front.is_empty() else applied
	var back := lerpf(crouch_back, _kneel_back, weight) if not _kneel_front.is_empty() else crouch_back
	# Absolute hip placement: the baked cover clip's own crouch must not add to this one.
	var parent := target.get_bone_parent(_hips)
	var parent_basis := target.get_bone_global_rest(parent).basis if parent >= 0 else Basis.IDENTITY
	var rest_origin := target.get_bone_rest(_hips).origin
	var delta_skeleton := Vector3(0.0, -drop, 0.0) / _scale - _forward_skeleton * (back / _scale)
	target.set_bone_pose_position(_hips, rest_origin + parent_basis.inverse() * delta_skeleton)
	for side in 2:
		var thigh := rad_to_deg(crouch_pose.thigh)
		var knee := rad_to_deg(crouch_pose.knee)
		var foot := -thigh + knee
		if weight > 0.0 and not _kneel_front.is_empty():
			var thigh_k := rad_to_deg(_kneel_front.thigh)
			var knee_k := rad_to_deg(_kneel_front.knee)
			var foot_k := -thigh_k + knee_k
			if side == kneel_leg:
				thigh_k = -rad_to_deg(KNEEL_REAR_THIGH_BACK)
				knee_k = rad_to_deg(KNEEL_REAR_SHIN_BACK - KNEEL_REAR_THIGH_BACK)
				foot_k = -thigh_k + knee_k + KNEEL_TOE_DEGREES
			thigh = lerpf(thigh, thigh_k, weight)
			knee = lerpf(knee, knee_k, weight)
			foot = lerpf(foot, foot_k, weight)
		_set_flexion(target, _upper[side], thigh)
		_set_flexion(target, _lower[side], -knee)
		_set_flexion(target, _foot[side], foot)
	_apply_lean(target, current_lean_degrees() + aim_lean_degrees)

func _apply_support_reach(target: Skeleton3D) -> void:
	if _support_clavicle < 0 or support_reach_degrees <= 0.05:
		return
	set_support_reach(target, support_reach_degrees)

func has_support_clavicle() -> bool:
	return _support_clavicle >= 0

func support_clavicle_bone() -> int:
	return _support_clavicle

## Sets the support-side shoulder protraction to `degrees`: the same rotation about the measured forward axis that
## `support_reach_degrees` applies. Public so the WeaponPose modifier can add reach for a target that needs it.
func set_support_reach(target: Skeleton3D, degrees: float) -> void:
	if _support_clavicle < 0:
		return
	var rest := target.get_bone_rest(_support_clavicle).basis.get_rotation_quaternion()
	target.set_bone_pose_rotation(_support_clavicle, rest * Quaternion(_forward_axis[_support_clavicle], deg_to_rad(degrees)))

## Leans the spine forward by `degrees` in total, shared between the spine bones.
func _apply_lean(target: Skeleton3D, degrees: float) -> void:
	var share := degrees / _spine.size()
	for bone in _spine:
		var rest := target.get_bone_rest(bone).basis.get_rotation_quaternion()
		target.set_bone_pose_rotation(bone, rest * Quaternion(_forward_axis[bone], deg_to_rad(share)))

## Replaces the animated flexion with the solved one about the bone's measured forward axis.
func _set_flexion(target: Skeleton3D, bone: int, degrees: float) -> void:
	var rest := target.get_bone_rest(bone).basis.get_rotation_quaternion()
	target.set_bone_pose_rotation(bone, rest * Quaternion(_forward_axis[bone], deg_to_rad(degrees)))
