class_name PassivePassengerPose
extends RefCounted
## A passive, limp humanoid pose for a body draped face-down over a carrier's shoulders (a fireman's carry), written as
## BONE DIRECTIONS in the body's own frame: x = the body's left, y = up the spine, z = the way the face looks. Each entry
## says where a bone's child should lie, so the same table fits another skeleton or other proportions: bones keep their
## own lengths and only turn. No animation player, no IK, no physics; applied once, parents first.
##
## The body is face-down, so GRAVITY IS +z in this frame. That makes the table read like the real posture: the spine and
## the thighs are folded forward (toward +z) around the carrier's shoulder like a coat over a rail, and everything that
## hangs (head, arms, lower legs) points close to +z.
##
##   spine:  the abdomen lies across the shoulder (flexion ~20 degrees), curving to a hanging head (~80 degrees)
##   legs:   thighs hang ~80 degrees from the body's vertical, knees slightly bent so the lower legs hang a little less
##   arms:   dangle down past the head, slightly apart, elbows loose
##
## Only Mixamo-named skeletons are posed (the MIRA rig). Other skeletons are left in rest pose.

const PREFIX := "mixamorig_"
## The bone the passenger is attached by: the abdomen, which is what lies on the carrier's shoulder.
const ATTACH_BONE := "Spine"


## Direction in the body frame for a segment folded `degrees` forward from the spine's up direction (+y toward +z).
static func _fold(degrees: float) -> Vector3:
	var a := deg_to_rad(degrees)
	return Vector3(0.0, cos(a), sin(a))


## Direction for a leg segment `degrees` forward of straight down the body (-y toward +z), with a little side spread.
static func _leg(degrees: float, spread := 0.0) -> Vector3:
	var a := deg_to_rad(degrees)
	return Vector3(spread, -cos(a), sin(a))


## Tunable values (body frame), overridable per call: spine fold angles (abdomen to head), the legs, and the two arms. The
## LEFT arm is the one the carrier holds by the wrist: it is brought forward to where the carrier's hand can reach it
## (upper arm hanging, forearm raised toward the carrier's right hand; derived from the contact geometry, see docs), the right arm just hangs.
const DEFAULTS := {
	"fold": [2.0, 6.0, 14.0, 45.0, 70.0, 65.0],
	"thigh": 77.0, "shin": 69.0, "foot": 55.0, "thigh_spread": 0.09, "shin_spread": 0.09,
	"held_upper": Vector3(-0.220, -0.093, 0.971), "held_fore": Vector3(0.895, 0.380, 0.235),
	"free_upper": Vector3(-0.22, 0.12, 0.97), "free_fore": Vector3(-0.10, 0.28, 0.95),
}


## The same table for a body lying on its back: straight spine, straight legs with the toes up (+z is the face, so up), both arms
## at the sides and resting a little way out. Body frame as above; gravity is -z here. The pickup blends from this to the draped
## pose (`blend`), and the release back.
const LYING := {
	"fold": [0.0, 0.0, 0.0, 0.0, 6.0, 8.0],
	"thigh": 0.0, "shin": 0.0, "foot": 70.0, "thigh_spread": 0.12, "shin_spread": 0.12,
	"held_upper": Vector3(0.30, -0.95, -0.10), "held_fore": Vector3(0.16, -0.97, -0.18),
	"free_upper": Vector3(-0.30, -0.95, -0.10), "free_fore": Vector3(-0.16, -0.97, -0.18),
}


## Parameter sets mixed by `t` (0 = `from`, 1 = `to`): numbers, direction vectors and the spine's fold angles one by one.
## Missing keys come from DEFAULTS.
static func blend(from: Dictionary, to: Dictionary, t: float) -> Dictionary:
	var result := {}
	for key in DEFAULTS:
		var a: Variant = from.get(key, DEFAULTS[key])
		var b: Variant = to.get(key, DEFAULTS[key])
		if a is Array:
			var mixed := []
			for i in (a as Array).size():
				mixed.append(lerpf(float(a[i]), float(b[i]), t))
			result[key] = mixed
		elif a is Vector3:
			result[key] = (a as Vector3).lerp(b as Vector3, t)
		else:
			result[key] = lerpf(float(a), float(b), t)
	return result


## [bone, child, direction of the child from the bone (body frame); side entries give the left and right directions].
static func chain(overrides := {}) -> Array:
	var p := DEFAULTS.duplicate()
	p.merge(overrides, true)
	var fold: Array = p.fold
	return [
		["Hips", "Spine", _fold(fold[0])],
		["Spine", "Spine1", _fold(fold[1])],
		["Spine1", "Spine2", _fold(fold[2])],
		["Spine2", "Neck", _fold(fold[3])],
		["Neck", "Head", _fold(fold[4])],
		["Head", "HeadTop_End", _fold(fold[5])],
		["%sArm", "%sForeArm", p.held_upper, p.free_upper],
		["%sForeArm", "%sHand", p.held_fore, p.free_fore],
		["%sUpLeg", "%sLeg", _leg(p.thigh, p.thigh_spread), _leg(p.thigh, -p.thigh_spread)],
		["%sLeg", "%sFoot", _leg(p.shin, p.shin_spread), _leg(p.shin, -p.shin_spread)],
		["%sFoot", "%sToeBase", _leg(p.foot, 0.02), _leg(p.foot, -0.02)],
	]


## True when the skeleton has the bones this pose needs.
static func supports(skeleton: Skeleton3D) -> bool:
	return skeleton.find_bone(PREFIX + "Hips") >= 0 and skeleton.find_bone(PREFIX + "LeftArm") >= 0 and skeleton.find_bone(PREFIX + "LeftUpLeg") >= 0


## Poses the skeleton from rest. `body_to_skeleton` turns a body-frame direction into the skeleton's space (identity
## when the model is not rotated inside its skeleton).
static func apply(skeleton: Skeleton3D, body_to_skeleton := Basis.IDENTITY, overrides := {}) -> bool:
	if not supports(skeleton):
		return false
	skeleton.reset_bone_poses()
	for entry in chain(overrides):
		var sided: bool = entry.size() > 3
		for side in ["Left", "Right"] if sided else [""]:
			var bone := skeleton.find_bone(PREFIX + (String(entry[0]) % side if sided else String(entry[0])))
			var child := skeleton.find_bone(PREFIX + (String(entry[1]) % side if sided else String(entry[1])))
			if bone < 0 or child < 0:
				continue
			var direction: Vector3 = entry[3] if side == "Right" else entry[2]
			_aim(skeleton, bone, child, body_to_skeleton * direction.normalized())
	return true


## Turns `bone` by the least rotation from its rest orientation so that the direction to `child` points along
## `direction` (skeleton space).
static func _aim(skeleton: Skeleton3D, bone: int, child: int, direction: Vector3) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	var rest_basis := skeleton.get_bone_rest(bone).basis.orthonormalized()
	var rest_direction := rest_basis * skeleton.get_bone_rest(child).origin.normalized()
	var wanted := parent_basis.inverse() * direction.normalized()
	var turn := Quaternion(rest_direction, wanted)
	skeleton.set_bone_pose_rotation(bone, (turn * rest_basis.get_rotation_quaternion()).normalized())
