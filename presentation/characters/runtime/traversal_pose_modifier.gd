class_name TraversalPoseModifier
extends SkeletonModifier3D
## Poses the BODY for an environmental traversal from TraversalSolver's contacts: the pelvis (placed against the rung plane), the trunk's lean is requested by the rig (CharacterRig.set_traversal_progress,
## through the crouch modifier's measured forward axis, the same `aim_lean_degrees` the rifle and the carry use) and the two LEGS (a two-bone IK to the foot targets, influence = the
## traversal's weight). Runs after Locomotion and CoverCrouch and before WeaponPose, so the arms, the rifle and the hands still come last: while a ladder is climbed
## WeaponPose puts the hands on the rungs (the carry-contact mechanism) and the rifle is slung. Does nothing when no traversal is active, so ordinary locomotion,
## cover and weapon handling are untouched.
##
## OWNS while active: the hips' position, the trunk lean request, the leg IK. NEVER the arms, hands, rifle, root yaw or the tactical position.

var rig: Node
var skeleton: Skeleton3D
var _hips := -1
## Last values written, for diagnostics and tests.
var weight := 0.0
var pose := {}
var passes := 0


func setup(owner_rig: Node, target: Skeleton3D, hips_bone: StringName) -> bool:
	rig = owner_rig
	skeleton = target
	_hips = target.find_bone(hips_bone)
	return _hips >= 0


func _process_modification() -> void:
	if rig == null or skeleton == null or not is_instance_valid(skeleton):
		return
	var leg_ik: TwoBoneIK3D = rig.get("leg_ik")
	var state: Dictionary = rig.get("traversal")
	if state.is_empty():
		weight = 0.0
		pose = {}
		var stairs: Dictionary = rig.get("stair_pose")
		if not stairs.is_empty():
			_apply_stairs(stairs, leg_ik)
		elif is_instance_valid(leg_ik) and leg_ik.active:
			leg_ik.active = false
		return
	passes += 1
	# The pose was solved when the progress was set (CharacterRig.set_traversal_progress), together with the trunk lean and the rifle's sling blend, so those are in
	# place before any modifier of this pass runs; this only applies it to the bones.
	pose = rig.get("traversal_pose")
	if pose.is_empty():
		return
	weight = float(pose.weight)
	var root: Node3D = rig.get("character_root")
	# The pelvis: toward the target place by the weight (the animation's own hips are the weight-0 pose).
	var hips_world: Vector3 = root.to_global(pose.hips)
	var hips_in_skeleton := skeleton.global_transform.affine_inverse() * hips_world
	var current := skeleton.get_bone_pose_position(_hips)
	skeleton.set_bone_pose_position(_hips, current.lerp(hips_in_skeleton, weight))
	# The legs: feet on rungs, knees out toward the ladder.
	if is_instance_valid(leg_ik):
		var feet: Array = rig.get("foot_targets")
		var poles: Array = rig.get("knee_poles")
		for side in 2:
			var foot: Vector3 = pose.feet[side]
			(feet[side] as Node3D).global_position = root.to_global(foot)
			(poles[side] as Node3D).global_position = root.to_global(foot + Vector3(foot.x * 0.5, 0.45, 0.55))
		leg_ik.influence = weight
		leg_ik.active = weight > 0.001


## Stair walking: the feet go to the planner's footholds through the leg IK and the pelvis takes the height the legs allow (StairFootPlanner.pelvis), both by the stair weight.
## The root already rides the stair surface (the tactical route), so only the pelvis HEIGHT is replaced; its sideways and fore-aft motion stay the gait's.
func _apply_stairs(stairs: Dictionary, leg_ik: TwoBoneIK3D) -> void:
	var stair_weight: float = stairs.weight
	weight = stair_weight
	var profile: StairProfile = rig.get("stair_profile")
	var root: Node3D = rig.get("character_root")
	var solved: Dictionary = stairs.pelvis
	var current := skeleton.get_bone_pose_position(_hips)
	var current_world: Vector3 = skeleton.global_transform * current
	var hips_world := Vector3(current_world.x, float(solved.height), current_world.z)
	var target := skeleton.global_transform.affine_inverse() * hips_world
	skeleton.set_bone_pose_position(_hips, current.lerp(target, stair_weight))
	if not is_instance_valid(leg_ik):
		return
	var feet: Array = rig.get("foot_targets")
	var poles: Array = rig.get("knee_poles")
	var forward := root.global_basis.orthonormalized().z
	for side in 2:
		var ankle: Vector3 = (stairs.feet[side] as Dictionary).position
		if not bool((stairs.feet[side] as Dictionary).planted):
			ankle = StairFootPlanner.limit_ankle(profile, hips_world, ankle)
		(feet[side] as Node3D).global_position = ankle
		(poles[side] as Node3D).global_position = ankle + forward * 0.55 + Vector3.UP * 0.45
	leg_ik.influence = stair_weight
	leg_ik.active = stair_weight > 0.001
