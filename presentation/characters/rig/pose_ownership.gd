class_name PoseOwnership
extends RefCounted
## Who writes which part of the body, in which order, and which overlaps are INTENDED (Task 04 composition model, Task 07 package 4). Plain data plus a pure validator; it schedules nothing.
## The skeleton's modifier child order is the schedule; this table describes it so that a new or changed stage cannot silently fight an existing one.
##
## Overlap kinds (see docs/claude/animation-ownership-contracts-2026-11-20.md section 8):
##  * ADD                additive: any number of stages may add to the same bone; no declaration needed.
##  * REPLACE_COMPONENT  replaces one rotational component (flexion) and keeps the rest of the bone's pose (the audit F-04 pattern); the components are different, so it coexists with ADD.
##  * OVERRIDE           writes the whole bone (or its position) absolutely or by a weight. Two OVERRIDE writers of the same bone need a declared ordered override below.
##  * TARGET             sets an IK target or pole (domain &"ik_target"); a LATER native IK solver stage writes the bones (an OVERRIDE of the same role). The solver stage is the bone writer; validate() requires it.
##  * POST               reads the final pose and moves non-bone nodes; never writes bones (listed for completeness, not a bone write).
## The runtime check in tests/pose_ownership_test.gd records which bones each stage really changes and fails on any bone a stage has not declared.

enum Op { ADD, REPLACE_COMPONENT, OVERRIDE, TARGET, POST }

## The skeleton's modifier child order (names are the node names CharacterRig gives them).
const STAGE_ORDER: Array[StringName] = [&"Locomotion", &"CoverCrouch", &"Traversal", &"TraversalLegIK", &"WeaponPose", &"WeaponArmIK", &"HandGrip"]

## Body roles (side-agnostic except the support clavicle, which is the one the weapon pose and posture both reach with). See role_of().
## A write: stage, role, domain (&"rotation" or &"position"), component (&"whole" or a named part), op.
const WRITES: Array[Dictionary] = [
	{"stage": &"Locomotion", "role": &"hips", "domain": &"rotation", "component": &"twist_bank", "op": Op.ADD},
	{"stage": &"Locomotion", "role": &"spine", "domain": &"rotation", "component": &"twist_pitch", "op": Op.ADD},
	{"stage": &"Locomotion", "role": &"thigh", "domain": &"rotation", "component": &"step_lift", "op": Op.ADD},
	{"stage": &"Locomotion", "role": &"shin", "domain": &"rotation", "component": &"step_lift", "op": Op.ADD},
	{"stage": &"CoverCrouch", "role": &"hips", "domain": &"position", "component": &"whole", "op": Op.OVERRIDE},
	{"stage": &"CoverCrouch", "role": &"thigh", "domain": &"rotation", "component": &"whole", "op": Op.OVERRIDE},
	{"stage": &"CoverCrouch", "role": &"shin", "domain": &"rotation", "component": &"whole", "op": Op.OVERRIDE},
	{"stage": &"CoverCrouch", "role": &"foot", "domain": &"rotation", "component": &"whole", "op": Op.OVERRIDE},
	{"stage": &"CoverCrouch", "role": &"spine", "domain": &"rotation", "component": &"flexion", "op": Op.REPLACE_COMPONENT},
	{"stage": &"CoverCrouch", "role": &"support_clavicle", "domain": &"rotation", "component": &"whole", "op": Op.OVERRIDE},
	{"stage": &"Traversal", "role": &"hips", "domain": &"position", "component": &"whole", "op": Op.OVERRIDE},
	{"stage": &"Traversal", "role": &"thigh", "domain": &"ik_target", "component": &"whole", "op": Op.TARGET},
	{"stage": &"Traversal", "role": &"shin", "domain": &"ik_target", "component": &"whole", "op": Op.TARGET},
	{"stage": &"TraversalLegIK", "role": &"thigh", "domain": &"rotation", "component": &"whole", "op": Op.OVERRIDE},
	{"stage": &"TraversalLegIK", "role": &"shin", "domain": &"rotation", "component": &"whole", "op": Op.OVERRIDE},
	{"stage": &"WeaponPose", "role": &"upper_arm", "domain": &"ik_target", "component": &"whole", "op": Op.TARGET},
	{"stage": &"WeaponPose", "role": &"forearm", "domain": &"ik_target", "component": &"whole", "op": Op.TARGET},
	{"stage": &"WeaponPose", "role": &"support_clavicle", "domain": &"rotation", "component": &"whole", "op": Op.OVERRIDE},
	{"stage": &"WeaponArmIK", "role": &"upper_arm", "domain": &"rotation", "component": &"whole", "op": Op.OVERRIDE},
	{"stage": &"WeaponArmIK", "role": &"forearm", "domain": &"rotation", "component": &"whole", "op": Op.OVERRIDE},
	{"stage": &"HandGrip", "role": &"wrist", "domain": &"rotation", "component": &"whole", "op": Op.OVERRIDE},
	{"stage": &"HandGrip", "role": &"fingers", "domain": &"rotation", "component": &"whole", "op": Op.OVERRIDE},
]

## Intended overlaps: several stages write the same role and domain non-additively, with the later stage taking precedence as stated. Anything not listed here and not purely additive is a conflict.
const OVERLAPS: Array[Dictionary] = [
	{"role": &"hips", "domain": &"position", "stages": [&"CoverCrouch", &"Traversal"],
		"rule": "Traversal lerps the pelvis toward its target by the traversal weight; weight 0 leaves the posture's hips exactly. A ladder or stairs are not combined with a crouch today (an assumption this table records)."},
	{"role": &"thigh", "domain": &"rotation", "stages": [&"Locomotion", &"CoverCrouch", &"TraversalLegIK"],
		"rule": "Locomotion only ADDS a step lift; CoverCrouch replaces the leg bones while crouched or kneeling; the leg IK takes them by its influence while a traversal is active. Crouch and traversal do not coexist today."},
	{"role": &"shin", "domain": &"rotation", "stages": [&"Locomotion", &"CoverCrouch", &"TraversalLegIK"],
		"rule": "As for the thigh."},
	{"role": &"support_clavicle", "domain": &"rotation", "stages": [&"CoverCrouch", &"WeaponPose"],
		"rule": "CoverCrouch sets the base protraction; WeaponPose is later and may only ADD to that base (never below it), up to the rig's limit; with nothing to add it restores the base."},
]

## The ownership role a bone plays in this rig (&"" for a bone no stage is expected to write): the bone's anatomical role (RigBones) mapped to the vocabulary of the table. Side-agnostic except the support
## (left) clavicle. The names of the bones are the rig profile's; nothing here knows one.
static func role_of(bones: RigBones, bone_name: String) -> StringName:
	var anatomical := bones.role_of_bone(StringName(bone_name))
	match String(anatomical):
		"Hips": return &"hips"
		"Spine", "Chest", "UpperChest": return &"spine"
		"LeftUpperLeg", "RightUpperLeg": return &"thigh"
		"LeftLowerLeg", "RightLowerLeg": return &"shin"
		"LeftFoot", "RightFoot": return &"foot"
		"LeftToes", "RightToes": return &"toes"
		"LeftShoulder": return &"support_clavicle"
		"RightShoulder": return &"clavicle"
		"LeftLowerArm", "RightLowerArm": return &"forearm"
		"LeftUpperArm", "RightUpperArm": return &"upper_arm"
		"LeftHand", "RightHand": return &"wrist"
		"Neck", "Head": return &"head"
	if String(anatomical).contains("Thumb") or String(anatomical).contains("Index") or String(anatomical).contains("Middle") or String(anatomical).contains("Ring") or String(anatomical).contains("Little"):
		return &"fingers"
	return &""

static func stages_writing(role: StringName, domain: StringName) -> Array[StringName]:
	var stages: Array[StringName] = []
	for write in WRITES:
		if write.role == role and write.domain == domain and write.op != Op.POST and write.op != Op.TARGET and not stages.has(write.stage):
			stages.append(write.stage)
	return stages

## The roles a stage is declared to write (bone writes only).
static func roles_written(stage: StringName) -> Array[StringName]:
	var roles: Array[StringName] = []
	for write in WRITES:
		if write.stage == stage and write.op != Op.POST and write.op != Op.TARGET and not roles.has(write.role):
			roles.append(write.role)
	return roles

static func _conflicts(a: Dictionary, b: Dictionary) -> bool:
	if a.role != b.role or a.domain != b.domain or a.stage == b.stage:
		return false
	if a.op == Op.ADD and b.op == Op.ADD:
		return false
	# A replaced component and a different, additive one coexist (the F-04 pattern); otherwise the same component, or a whole-bone write, collides.
	if a.component != &"whole" and b.component != &"whole" and a.component != b.component:
		return false
	return true

## Pure validation of the table against the modifier order. Returns human-readable problems; empty means consistent.
static func validate(actual_order: Array[StringName] = STAGE_ORDER) -> Array[String]:
	var problems: Array[String] = []
	if actual_order != STAGE_ORDER:
		problems.append("The skeleton's modifier order %s differs from the declared order %s" % [actual_order, STAGE_ORDER])
	for stage in STAGE_ORDER:
		var declares := false
		for write in WRITES:
			declares = declares or write.stage == stage
		if not declares:
			problems.append("Stage %s declares no writes" % stage)
	# A TARGET is only meaningful if a LATER stage solves it: some later stage must write that role's rotation.
	for write in WRITES:
		if write.op == Op.TARGET:
			var solved := false
			for other in WRITES:
				if other.role == write.role and other.domain == &"rotation" and other.op == Op.OVERRIDE and STAGE_ORDER.find(other.stage) > STAGE_ORDER.find(write.stage):
					solved = true
			if not solved:
				problems.append("Stage %s sets an IK target for %s but no later stage solves it" % [write.stage, write.role])
	for write in WRITES:
		if not STAGE_ORDER.has(write.stage):
			problems.append("A write names an unknown stage %s" % write.stage)
	# Every non-additive collision must be a declared ordered override that names its stages in modifier order.
	var needed := {}
	for i in WRITES.size():
		for j in range(i + 1, WRITES.size()):
			if _conflicts(WRITES[i], WRITES[j]):
				needed["%s/%s" % [WRITES[i].role, WRITES[i].domain]] = [WRITES[i].role, WRITES[i].domain]
	for key in needed:
		var found := false
		for overlap in OVERLAPS:
			if overlap.role == needed[key][0] and overlap.domain == needed[key][1]:
				found = true
		if not found:
			problems.append("Undeclared pose-write conflict on %s: %s" % [key, stages_writing(needed[key][0], needed[key][1])])
	for overlap in OVERLAPS:
		var writers := stages_writing(overlap.role, overlap.domain)
		var previous := -1
		for stage in overlap.stages:
			var index := STAGE_ORDER.find(stage)
			if index < 0 or not writers.has(stage):
				problems.append("Declared overlap %s/%s names %s, which does not write it" % [overlap.role, overlap.domain, stage])
			if index <= previous:
				problems.append("Declared overlap %s/%s lists its stages out of modifier order" % [overlap.role, overlap.domain])
			previous = index
		if needed.has("%s/%s" % [overlap.role, overlap.domain]) == false:
			problems.append("Stale overlap declaration %s/%s: no stages collide there any more" % [overlap.role, overlap.domain])
		for stage in writers:
			if not overlap.stages.has(stage):
				problems.append("Declared overlap %s/%s omits writer %s" % [overlap.role, overlap.domain, stage])
	return problems
