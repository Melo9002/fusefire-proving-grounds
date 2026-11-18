class_name HandGripModifier
extends SkeletonModifier3D
## Closes the fingers around whatever the hands hold, and pulls the trigger finger. Presentation only.
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

var _fingers := [[], []]
var _axes := {}

func setup(target: Skeleton3D, prefix: String) -> bool:
	for hand in 2:
		var side := "Left" if hand == 0 else "Right"
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

func _process_modification() -> void:
	var target := get_skeleton()
	if target == null or _fingers[0].is_empty():
		return
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
