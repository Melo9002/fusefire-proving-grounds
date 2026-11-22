class_name RigBones
extends RefCounted
## The skeleton configuration the animation stack runs on (Task 07 package 9): which bone plays which anatomical role, as typed fields, derived ONCE from a rig profile (the BoneMap of the profile names every
## role in Godot's humanoid vocabulary) and checked against the skeleton it is for. Nothing else in the stack names a bone: the rig, the clip builder, every modifier, the passenger pose and the tools read
## roles from here, so a skeleton with different names is a different profile and no code. Roles a skeleton does not have are empty and recorded in `absent`; the stage that needs one reports it (`degraded`)
## instead of failing without a word. Asset-specific names live in the profile resource (art/characters/<name>/<name>_rig_profile.tres).

const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Little"]

var hips: StringName = &""
var spine: StringName = &""
var chest: StringName = &""
var upper_chest: StringName = &""
var neck: StringName = &""
var head: StringName = &""
## The bone at the very top of the head (an end bone the profile's anatomy names), or the head when there is none.
var head_top: StringName = &""
## The bone the chest frame, the carried passenger and the stow anchor follow: the highest of upper chest, chest, spine.
var torso: StringName = &""
var left_shoulder: StringName = &""
var right_shoulder: StringName = &""
## [upper arm, forearm, hand], per side.
var left_arm: Array[StringName] = []
var right_arm: Array[StringName] = []
## [upper leg, lower leg, foot], per side.
var left_leg: Array[StringName] = []
var right_leg: Array[StringName] = []
var left_toes: StringName = &""
var right_toes: StringName = &""
## The profile's own name, for reports.
var profile_name := ""
## Roles the profile maps to a bone the skeleton does not have.
var absent: Array[StringName] = []
## Stages that cannot run on this skeleton, each with the role that is missing: filled by the rig as it builds, read by diagnostics and tests.
var degraded: Array[String] = []

var _by_role := {}   # role -> StringName
var _by_name := {}   # bone name -> role

## Reads the profile's bone map against `skeleton`. A role whose bone the skeleton lacks is recorded in `absent` and left empty.
static func from_profile(profile: Resource, skeleton: Skeleton3D) -> RigBones:
	var result := RigBones.new()
	if profile == null or skeleton == null:
		return result
	result.profile_name = String(profile.display_name)
	var map: BoneMap = profile.skeleton_map
	if map == null:
		return result
	for role_key: StringName in _all_roles():
		var bone := map.get_skeleton_bone_name(role_key)
		if bone == &"":
			continue
		if skeleton.find_bone(bone) < 0:
			result.absent.append(role_key)
			continue
		result._by_role[role_key] = bone
		result._by_name[bone] = role_key
	var anatomy = profile.anatomy
	result.hips = result.role(&"Hips")
	result.spine = result.role(&"Spine")
	result.chest = result.role(&"Chest")
	result.upper_chest = result.role(&"UpperChest")
	result.neck = result.role(&"Neck")
	result.head = result.role(&"Head")
	result.head_top = anatomy.head_top_bone if anatomy != null and anatomy.head_top_bone != &"" and skeleton.find_bone(anatomy.head_top_bone) >= 0 else result.head
	result.torso = result.upper_chest if result.upper_chest != &"" else (result.chest if result.chest != &"" else result.spine)
	result.left_shoulder = result.role(&"LeftShoulder")
	result.right_shoulder = result.role(&"RightShoulder")
	result.left_arm = [result.role(&"LeftUpperArm"), result.role(&"LeftLowerArm"), result.role(&"LeftHand")]
	result.right_arm = [result.role(&"RightUpperArm"), result.role(&"RightLowerArm"), result.role(&"RightHand")]
	result.left_leg = [result.role(&"LeftUpperLeg"), result.role(&"LeftLowerLeg"), result.role(&"LeftFoot")]
	result.right_leg = [result.role(&"RightUpperLeg"), result.role(&"RightLowerLeg"), result.role(&"RightFoot")]
	result.left_toes = result.role(&"LeftToes")
	result.right_toes = result.role(&"RightToes")
	if result.head_top != result.head and result.head_top != &"":
		result._by_name[result.head_top] = &"HeadTop"
	return result

static func _all_roles() -> Array[StringName]:
	var roles: Array[StringName] = [&"Hips", &"Spine", &"Chest", &"UpperChest", &"Neck", &"Head", &"LeftShoulder", &"RightShoulder", &"LeftUpperArm", &"LeftLowerArm", &"LeftHand", &"RightUpperArm", &"RightLowerArm", &"RightHand",
		&"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot", &"RightUpperLeg", &"RightLowerLeg", &"RightFoot", &"LeftToes", &"RightToes"]
	for side in ["Left", "Right"]:
		for finger_name in FINGERS:
			for joint in _finger_roles(finger_name):
				roles.append(StringName(side + String(joint)))
	return roles

## The three mapped joint roles of a finger, from the knuckle out (without the side). The thumb has a metacarpal where the others have a proximal phalanx.
static func _finger_roles(finger_name: String) -> Array:
	if finger_name == "Thumb":
		return ["ThumbMetacarpal", "ThumbProximal", "ThumbDistal"]
	return [finger_name + "Proximal", finger_name + "Intermediate", finger_name + "Distal"]

## The bone of a role (empty when the profile does not map it or the skeleton lacks it).
func role(role_name: StringName) -> StringName:
	return _by_role.get(role_name, &"")

func has_role(role_name: StringName) -> bool:
	return _by_role.has(role_name)

## The hip-joint-to-ankle height (metres, standing) of the body that every authored length in metres was tuned for: MIRA as shown in the game. A length in metres in a shared profile (a stride, a pelvis bob,
## an authored crouch depth) means "this much on that body"; `body_ratio` is how much of it another body takes.
const REFERENCE_HIP_TO_ANKLE := 0.762127745

## This skeleton's leg relative to the reference body (1 for MIRA): the hip joint's height over the ankle at rest, as the model is scaled. 1 when the legs are not mapped.
func body_ratio(skeleton: Skeleton3D) -> float:
	var hip := skeleton.find_bone(left_leg[0]) if left_leg.size() > 0 else -1
	var ankle := skeleton.find_bone(left_leg[2]) if left_leg.size() > 2 else -1
	if hip < 0 or ankle < 0:
		return 1.0
	var unit := skeleton.global_basis.get_scale().y if skeleton.is_inside_tree() else 1.0
	var height := (skeleton.get_bone_global_rest(hip).origin.y - skeleton.get_bone_global_rest(ankle).origin.y) * unit
	return height / REFERENCE_HIP_TO_ANKLE if height > 0.01 else 1.0

## The role a bone plays in this rig (&"" for a bone no role names): the way back from a skeleton bone to the vocabulary.
func role_of_bone(bone_name: StringName) -> StringName:
	return _by_name.get(bone_name, &"")

## A finger joint's bone: `side` "Left" or "Right", `finger_name` one of FINGERS, `joint` 1 to 3 from the knuckle.
func finger(side: String, finger_name: String, joint: int) -> StringName:
	var joints := _finger_roles(finger_name)
	return role(StringName(side + String(joints[joint - 1]))) if joint >= 1 and joint <= 3 else &""

## A finger's skeleton indices: its three mapped joints and the end bone beyond the last (the distal's first child). Empty when any is missing.
func finger_chain(skeleton: Skeleton3D, side: String, finger_name: String) -> Array[int]:
	var chain: Array[int] = []
	for joint in [1, 2, 3]:
		var index := skeleton.find_bone(finger(side, finger_name, joint))
		if index < 0:
			return []
		chain.append(index)
	var tips := skeleton.get_bone_children(chain[2])
	if tips.is_empty():
		return []
	chain.append(tips[0])
	return chain

## The spine bones that exist, bottom to top (spine, chest, upper chest): what the turn twist is shared across.
func spine_chain() -> Array[StringName]:
	var chain: Array[StringName] = []
	for bone: StringName in [spine, chest, upper_chest]:
		if bone != &"":
			chain.append(bone)
	return chain

## The two lowest spine bones (spine, chest): what the cover crouch folds.
func lower_spine() -> Array[StringName]:
	var chain: Array[StringName] = []
	for bone: StringName in [spine, chest]:
		if bone != &"":
			chain.append(bone)
	return chain

## The roles of a stage that are missing (empty when the stage can run).
func missing_of(roles: Array) -> Array[StringName]:
	var missing: Array[StringName] = []
	for role_name: StringName in roles:
		if not has_role(role_name):
			missing.append(role_name)
	return missing

## Records that a stage cannot run on this skeleton, and why. One line per stage.
func degrade(stage: String, missing: Array) -> void:
	var names: Array[String] = []
	for role_name in missing:
		names.append(String(role_name))
	degraded.append("%s is not built (missing: %s)" % [stage, ", ".join(names)] if not names.is_empty() else "%s is not built" % stage)
