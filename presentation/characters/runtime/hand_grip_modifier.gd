class_name HandGripModifier
extends SkeletonModifier3D
## Orients the hands on the weapon, closes the fingers around its grips and pulls the trigger
## finger. Presentation only. Runs after the arm IK, which places the wrists but leaves each hand
## facing wherever the forearm happens to point.
##
## The curl axis of every finger joint is measured from the rest pose (the imported rest pose is a
## T-pose with the palms down, so "toward the palm" is "down"), so it works whichever local axis
## the skeleton uses and for both hands.

## Full-fist flexion per joint (knuckle, middle, tip), degrees.
const FIST_DEGREES := [80.0, 95.0, 60.0]
## Thumb joints flex less.
const THUMB_DEGREES := [25.0, 35.0, 30.0]
## The trigger finger rests slightly curled on the trigger guard and pulls to this curl.
const TRIGGER_REST_CURL := 0.35
const TRIGGER_PULLED_CURL := 0.95

## Grip tightness per hand, 0 = open, 1 = fist. Index 0 = left, 1 = right.
var curl := [0.0, 0.0]
## Right index finger: 0 = resting on the guard, 1 = trigger pulled.
var trigger_pull := 0.0
## Whether the right hand's index finger rests on the trigger (a pistol grip) instead of wrapping.
var right_trigger_finger := true

## The weapon's orientation in skeleton space, and how strongly the hands follow it (0 = animation).
var weapon_basis := Basis.IDENTITY
var orient_weight := 0.0
## Direction of the fingers' base and the palm-facing direction for each hand, in the weapon frame.
var hand_forward := Vector3(0.0, -0.5, 0.866)
var palm_normals := [Vector3.LEFT, Vector3.RIGHT]
## Contact orientation (skeleton space), per hand (index 0 = left, 1 = right): when `contact_weight` is above zero that hand
## is turned to this finger direction and palm-facing direction instead of following the weapon (a carried body's limb).
var contact_weight := [0.0, 0.0]
var contact_forward := [Vector3.FORWARD, Vector3.FORWARD]
var contact_normal := [Vector3.DOWN, Vector3.DOWN]
## Wrist to middle-finger knuckle, metres (half of it reaches the palm centre).
var palm_length := 0.09

var _fingers := [[], []]
var _axes := {}
var _hands := [-1, -1]
var _hand_parents := [-1, -1]
var _hand_rest_basis := [Basis.IDENTITY, Basis.IDENTITY]
var _finger_rest_direction := [Vector3.RIGHT, Vector3.LEFT]

func setup(target: Skeleton3D, prefix: String) -> bool:
	var scale_y := target.global_basis.get_scale().y if target.is_inside_tree() else 1.0
	for hand in 2:
		var side := "Left" if hand == 0 else "Right"
		_hands[hand] = target.find_bone("%s%sHand" % [prefix, side])
		var middle := target.find_bone("%s%sHandMiddle1" % [prefix, side])
		if _hands[hand] < 0 or middle < 0:
			return false
		_hand_parents[hand] = target.get_bone_parent(_hands[hand])
		_hand_rest_basis[hand] = target.get_bone_global_rest(_hands[hand]).basis.orthonormalized()
		var along: Vector3 = target.get_bone_global_rest(middle).origin - target.get_bone_global_rest(_hands[hand]).origin
		_finger_rest_direction[hand] = along.normalized()
		palm_length = along.length() * scale_y
		for finger in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			var joints: Array[int] = []
			for joint in [1, 2, 3, 4]:
				joints.append(target.find_bone("%s%sHand%s%d" % [prefix, side, finger, joint]))
			if joints.has(-1):
				return false
			_fingers[hand].append(joints)
			for index in 3:
				_axes[joints[index]] = _curl_axis(target, joints[index], joints[index + 1])
	return true

## The local axis, signed, whose positive rotation moves `child` toward the palm (down in the rest pose).
func _curl_axis(target: Skeleton3D, bone: int, child: int) -> Vector3:
	var basis := target.get_bone_global_rest(bone).basis
	var offset := target.get_bone_rest(child).origin
	var best := Vector3.BACK
	var best_score := 0.0
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var moved: Vector3 = basis * (Quaternion(axis, 0.2) * offset - offset)
		var score := moved.dot(Vector3.DOWN)
		if absf(score) > absf(best_score):
			best_score = score
			best = axis * signf(score)
	return best

## An orthonormal frame from a long axis and a palm normal.
static func _frame(forward: Vector3, normal: Vector3) -> Basis:
	var x := forward.normalized()
	var z := x.cross(normal).normalized()
	return Basis(x, z.cross(x), z)

## Turns each hand so its fingers point along `hand_forward` and its palm faces `palm_normals`,
## both given in the weapon frame. The rest pose is a T-pose with the palms down.
func _orient_hands(target: Skeleton3D) -> void:
	for hand in 2:
		var weight := orient_weight
		var forward := (weapon_basis * hand_forward).normalized()
		var normal: Vector3 = (weapon_basis * (palm_normals[hand] as Vector3)).normalized()
		if float(contact_weight[hand]) > 0.001:
			weight = contact_weight[hand]
			forward = (contact_forward[hand] as Vector3).normalized()
			normal = (contact_normal[hand] as Vector3).normalized()
		if weight <= 0.001:
			continue
		var rotation := _frame(forward, normal) * _frame(_finger_rest_direction[hand], Vector3.DOWN).inverse()
		var desired: Basis = rotation * _hand_rest_basis[hand]
		var parent_basis := target.get_bone_global_pose(_hand_parents[hand]).basis.orthonormalized()
		var local := (parent_basis.inverse() * desired).orthonormalized().get_rotation_quaternion()
		var current := target.get_bone_pose_rotation(_hands[hand])
		target.set_bone_pose_rotation(_hands[hand], current.slerp(local, clampf(weight, 0.0, 1.0)))

func _process_modification() -> void:
	var target := get_skeleton()
	if target == null or _fingers[0].is_empty():
		return
	_orient_hands(target)
	for hand in 2:
		for finger in 5:
			var amount: float = curl[hand]
			if hand == 1 and finger == 1 and right_trigger_finger:
				amount = lerpf(TRIGGER_REST_CURL, TRIGGER_PULLED_CURL, trigger_pull) * curl[hand]
			var limits: Array = THUMB_DEGREES if finger == 0 else FIST_DEGREES
			var joints: Array = _fingers[hand][finger]
			for index in 3:
				var bone: int = joints[index]
				var rest := target.get_bone_rest(bone).basis.get_rotation_quaternion()
				target.set_bone_pose_rotation(bone, rest * Quaternion(_axes[bone], deg_to_rad(limits[index] * amount)))
