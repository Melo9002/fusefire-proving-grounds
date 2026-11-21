extends RefCounted
## Task 05 PROTOTYPE (experimental; nothing in production uses it). The role vocabulary is Godot's own: the bone names of `SkeletonProfileHumanoid` (56 roles in Godot 4.7.2). FuseFire adds
## only which of those roles *its* code requires, how they chain, and a few roles Godot's profile does not have (those are named in RigAnatomy, not invented here).

## Roles FuseFire's existing animation code cannot run without (a subset of Godot's editor-level "required" flags: Godot also requires the shoulders; FuseFire does not).
const REQUIRED := [
	&"Hips", &"Spine", &"Head",
	&"LeftUpperArm", &"LeftLowerArm", &"LeftHand", &"RightUpperArm", &"RightLowerArm", &"RightHand",
	&"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot", &"RightUpperLeg", &"RightLowerLeg", &"RightFoot",
]

## Parent-to-child expectations: each pair means "the second role's bone must be a descendant of the first role's bone" (intermediate twist bones are allowed and reported).
const CHAINS := [
	[&"Hips", &"Spine"], [&"Spine", &"Chest"], [&"Chest", &"UpperChest"], [&"UpperChest", &"Neck"], [&"Neck", &"Head"],
	[&"Hips", &"LeftUpperLeg"], [&"LeftUpperLeg", &"LeftLowerLeg"], [&"LeftLowerLeg", &"LeftFoot"], [&"LeftFoot", &"LeftToes"],
	[&"Hips", &"RightUpperLeg"], [&"RightUpperLeg", &"RightLowerLeg"], [&"RightLowerLeg", &"RightFoot"], [&"RightFoot", &"RightToes"],
	[&"LeftShoulder", &"LeftUpperArm"], [&"LeftUpperArm", &"LeftLowerArm"], [&"LeftLowerArm", &"LeftHand"],
	[&"RightShoulder", &"RightUpperArm"], [&"RightUpperArm", &"RightLowerArm"], [&"RightLowerArm", &"RightHand"],
]

## Left/right counterparts, used to detect a swapped or one-sided mapping.
const SIDE_PAIRS := [
	[&"LeftUpperLeg", &"RightUpperLeg"], [&"LeftLowerLeg", &"RightLowerLeg"], [&"LeftFoot", &"RightFoot"],
	[&"LeftUpperArm", &"RightUpperArm"], [&"LeftLowerArm", &"RightLowerArm"], [&"LeftHand", &"RightHand"],
]

const SPINE_CHAIN := [&"Spine", &"Chest", &"UpperChest"]
const FINGER_ROLES_LEFT := [
	&"LeftThumbMetacarpal", &"LeftThumbProximal", &"LeftThumbDistal",
	&"LeftIndexProximal", &"LeftIndexIntermediate", &"LeftIndexDistal",
	&"LeftMiddleProximal", &"LeftMiddleIntermediate", &"LeftMiddleDistal",
	&"LeftRingProximal", &"LeftRingIntermediate", &"LeftRingDistal",
	&"LeftLittleProximal", &"LeftLittleIntermediate", &"LeftLittleDistal",
]

static func finger_roles(side: String) -> Array[StringName]:
	var roles: Array[StringName] = []
	for role: StringName in FINGER_ROLES_LEFT:
		roles.append(StringName(String(role).replace("Left", side)))
	return roles
