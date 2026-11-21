class_name LocomotionPoseModifier
extends SkeletonModifier3D
## Body adjustments that depend on the situation and not on the gait cycle, added on top of whatever the animation tree produced:
##  * TWIST: when the facing changes at once (a shot, a cover turn) the chest and weapon are at the new facing immediately, as gameplay and
##    aiming need, while the hips and feet are shown still turning to catch up: the hips yaw back by `twist_degrees` and the spine unwinds it so
##    the chest's net yaw is zero. Two repositioning steps (`step_lift`) lift the feet while it unwinds.
##  * BANK: a lean into a turn while moving (about the character's forward axis).
##  * PITCH: trunk pitch from acceleration (forward when speeding up, back when braking).
##
## It runs FIRST in the skeleton's modifier order (Locomotion, CoverCrouch, WeaponPose, WeaponArmIK, HandGrip), so the weapon pose reads the
## chest with its torso counter-rotation already applied and nothing here ever touches the arms or the weapon targets. The axes are the anatomical
## ones measured by CharacterFallbackAnimationBuilder (skeleton space); no bone-local axis is assumed.

var twist_degrees := 0.0
var bank_degrees := 0.0
var pitch_degrees := 0.0
## Knee flexion of the left and right foot-lifting steps, degrees (0 = planted).
var step_lift := [0.0, 0.0]

## The typed way in (RigInput): the presentation hands a RigInput and the modifier takes its locomotion fields. The four public fields above stay readable and writable for existing
## readers and tests; apply_input is the only writer the rig uses.
func apply_input(input: RigInput) -> void:
	twist_degrees = input.twist_degrees
	bank_degrees = input.bank_degrees
	pitch_degrees = input.pitch_degrees
	step_lift = [input.step_lift_left, input.step_lift_right]

var _up := Vector3.UP
var _forward := Vector3.BACK
var _hinge := Vector3.RIGHT
var _hips := -1
var _spine: Array[int] = []
var _legs := []   # per side: [upper, lower]


func setup(target: Skeleton3D, axes: Dictionary) -> bool:
	var mixamo := target.find_bone(&"mixamorig_Hips") >= 0
	_hips = target.find_bone(&"mixamorig_Hips" if mixamo else &"J_Bip_C_Hips")
	for bone_name in ([&"mixamorig_Spine", &"mixamorig_Spine1", &"mixamorig_Spine2"] if mixamo else [&"J_Bip_C_Spine", &"J_Bip_C_Chest", &"J_Bip_C_UpperChest"]):
		var index := target.find_bone(bone_name)
		if index >= 0:
			_spine.append(index)
	var left := [target.find_bone(&"mixamorig_LeftUpLeg" if mixamo else &"J_Bip_L_UpperLeg"), target.find_bone(&"mixamorig_LeftLeg" if mixamo else &"J_Bip_L_LowerLeg")]
	var right := [target.find_bone(&"mixamorig_RightUpLeg" if mixamo else &"J_Bip_R_UpperLeg"), target.find_bone(&"mixamorig_RightLeg" if mixamo else &"J_Bip_R_LowerLeg")]
	_legs = [left, right]
	_up = axes.up
	_forward = axes.forward
	_hinge = axes.hinge
	return _hips >= 0 and not _spine.is_empty() and left[0] >= 0 and right[0] >= 0


func _process_modification_with_delta(_delta: float) -> void:
	var target := get_skeleton()
	if target == null or _hips < 0:
		return
	if absf(twist_degrees) < 0.01 and absf(bank_degrees) < 0.01 and absf(pitch_degrees) < 0.01 and step_lift[0] < 0.01 and step_lift[1] < 0.01:
		return
	if absf(twist_degrees) > 0.01:
		# Hips back by the twist; the spine, bottom to top, gives it back so the chest's net yaw is zero.
		_turn(target, _hips, _up, -twist_degrees)
		var share := twist_degrees / float(_spine.size())
		for bone in _spine:
			_turn(target, bone, _up, share)
	if absf(bank_degrees) > 0.01:
		_turn(target, _hips, _forward, -bank_degrees)
	if absf(pitch_degrees) > 0.01:
		_turn(target, _spine[0], _hinge, -pitch_degrees)
	for side in 2:
		var lift: float = step_lift[side]
		if lift > 0.01 and _legs[side][1] >= 0:
			_turn(target, _legs[side][0], _hinge, lift * 0.55)
			_turn(target, _legs[side][1], _hinge, -lift)


## Rotates `bone` by `degrees` about a skeleton-space axis, about the bone's own position, whatever the bone's local axes are.
func _turn(target: Skeleton3D, bone: int, axis: Vector3, degrees: float) -> void:
	var parent := target.get_bone_parent(bone)
	var parent_basis := target.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	var local_axis := parent_basis.inverse() * axis
	target.set_bone_pose_rotation(bone, (Quaternion(local_axis.normalized(), deg_to_rad(degrees)) * target.get_bone_pose_rotation(bone)).normalized())
