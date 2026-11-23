class_name TraversalPoseModifier
extends SkeletonModifier3D
## Poses the BODY for an environmental traversal from TraversalSolver's contacts: the pelvis (placed against the rung plane), the trunk's lean is requested by the rig (CharacterRig.set_traversal_progress,
## through the crouch modifier's measured forward axis, the same `aim_lean_degrees` the rifle and the carry use) and the two LEGS (a two-bone IK to the foot targets, influence = the
## traversal's weight). Runs after Locomotion and CoverCrouch and before WeaponPose, so the arms, the rifle and the hands still come last: while a ladder is climbed
## WeaponPose puts the hands on the rungs (the carry-contact mechanism) and the rifle is slung. Does nothing when no traversal is active, so ordinary locomotion,
## cover and weapon handling are untouched.
##
## OWNS while active: the hips' position, the trunk lean request, the leg IK. NEVER the arms, hands, rifle, root yaw or the tactical position.

## What to show this frame: published by CharacterRig whenever the traversal or stair pose changes (see TraversalPoseInput). The modifier reads nothing else of the rig.
var input := TraversalPoseInput.new()
var skeleton: Skeleton3D
## The character root whose frame the ladder pose is expressed in (read in THIS pass, so a root that moved this frame is honoured).
var character_frame: Node3D
var leg_ik: TwoBoneIK3D
var foot_targets: Array[Marker3D] = []
var knee_poles: Array[Marker3D] = []
var _hips := -1
## Last values written, for diagnostics and tests.
var weight := 0.0
var passes := 0
## The planned legs' overlap with the ladder this pass (metres, <= 0 clear), per side: what the knee planner could not avoid.
var knee_overlap: Array[float] = [0.0, 0.0]
## Each knee's outward turn (degrees): it starts the next search and changes at a limited rate, so a knee glides to a new stance instead of popping.
var knee_turn: Array[float] = [LadderKneePlanner.PREFERRED_TURN, LadderKneePlanner.PREFERRED_TURN]
const KNEE_TURN_RATE := 360.0


func setup(target: Skeleton3D, hips_bone: StringName, frame: Node3D) -> bool:
	skeleton = target
	character_frame = frame
	_hips = target.find_bone(hips_bone)
	return _hips >= 0


## The leg IK and its target and pole markers, which the rig creates after the modifier (they belong to the IK solver that runs just after this stage).
func bind_legs(ik: TwoBoneIK3D, feet: Array[Marker3D], poles: Array[Marker3D]) -> void:
	leg_ik = ik
	foot_targets = feet
	knee_poles = poles


func _process_modification_with_delta(delta: float) -> void:
	if skeleton == null or not is_instance_valid(skeleton) or character_frame == null:
		return
	match input.mode:
		TraversalPoseInput.Mode.NONE:
			weight = 0.0
			knee_turn = [LadderKneePlanner.PREFERRED_TURN, LadderKneePlanner.PREFERRED_TURN]
			if is_instance_valid(leg_ik) and leg_ik.active:
				leg_ik.active = false
		TraversalPoseInput.Mode.STAIRS:
			_apply_stairs()
		TraversalPoseInput.Mode.LADDER:
			_apply_ladder(delta)


func _apply_ladder(delta: float) -> void:
	passes += 1
	# The pose was solved when the progress was set (CharacterRig.set_traversal_progress), together with the trunk lean and the rifle's sling blend, so those are in
	# place before any modifier of this pass runs; this only applies it to the bones.
	if not input.solved:
		return
	weight = input.weight
	# The pelvis: toward the target place by the weight (the animation's own hips are the weight-0 pose).
	var hips_world := character_frame.to_global(input.hips_local)
	var hips_in_skeleton := skeleton.global_transform.affine_inverse() * hips_world
	var current := skeleton.get_bone_pose_position(_hips)
	skeleton.set_bone_pose_position(_hips, current.lerp(hips_in_skeleton, weight))
	# The legs: feet on rungs, knees out toward the ladder.
	if is_instance_valid(leg_ik):
		for side in 2:
			var foot := input.feet_local[side]
			foot_targets[side].global_position = character_frame.to_global(foot)
			# The knee goes where the leg's own length and the rungs allow (LadderKneePlanner), not a fixed offset from the foot: that put every knee through the ladder.
			var hip := input.ladder_body.hip_joint(input.hips_local, side)
			var plan := LadderKneePlanner.plan(input.ladder_geometry, input.ladder_body, hip, foot, side, input.floor_level, knee_turn[side])
			if input.deck_planted[side]:
				# With a deck foothold the knee can hinge forward again if
				# that direction clears the remaining rung and rail volumes.
				var forward_turn := move_toward(knee_turn[side], 0.0, KNEE_TURN_RATE * maxf(delta, 0.0))
				var forward_plan := LadderKneePlanner.at_turn(input.ladder_geometry, input.ladder_body, hip, foot, side, input.floor_level, forward_turn)
				if float(forward_plan.overlap) < -LadderKneePlanner.MARGIN:
					plan = forward_plan
			# Let a knee come back in only when it has spare clearance.
			# A tightly folded knee still keeps its existing path around the bars.
			if is_equal_approx(float(plan.turn), knee_turn[side]) and knee_turn[side] > 10.0 and float(plan.overlap) < -0.025:
				var narrower := move_toward(knee_turn[side], 10.0, KNEE_TURN_RATE * maxf(delta, 0.0))
				var inward := LadderKneePlanner.at_turn(input.ladder_geometry, input.ladder_body, hip, foot, side, input.floor_level, narrower)
				if float(inward.overlap) < -0.025:
					plan = inward
			knee_turn[side] = move_toward(knee_turn[side], plan.turn, KNEE_TURN_RATE * delta)
			plan = LadderKneePlanner.at_turn(input.ladder_geometry, input.ladder_body, hip, foot, side, input.floor_level, knee_turn[side])
			knee_overlap[side] = float(plan.overlap)
			knee_poles[side].global_position = character_frame.to_global(plan.pole)
		leg_ik.influence = weight
		leg_ik.active = weight > 0.001


## Stair walking: the feet go to the planner's footholds through the leg IK and the pelvis takes the height the legs allow (StairFootPlanner.pelvis), both by the stair weight.
## The root already rides the stair surface (the tactical route), so the pelvis HEIGHT is replaced and, with the stance motion on, it shifts sideways over the supporting foot; its fore-aft motion stays the gait's.
func _apply_stairs() -> void:
	weight = input.weight
	var current := skeleton.get_bone_pose_position(_hips)
	var current_world: Vector3 = skeleton.global_transform * current
	var forward := character_frame.global_basis.orthonormalized().z
	var hips_xz := Vector3(current_world.x + input.pelvis_offset.x, 0.0, current_world.z + input.pelvis_offset.z)
	var height := input.pelvis_height
	if input.stair_profile != null and not is_nan(input.smooth_floor):
		# The pelvis height was planned for the root; the hips are where the gait left them, so the legs' limits are applied there.
		var feet: Array = []
		for side in 2:
			feet.append({"position": input.ankles_world[side], "planted": input.planted[side]})
		var solved := StairFootPlanner.pelvis(input.stair_profile, hips_xz, feet, input.smooth_floor, forward)
		height = float(solved.height)
		if bool(solved.ok):
			height = maxf(float(solved.low), height - input.stair_crouch)
	var hips_world := Vector3(hips_xz.x, height, hips_xz.z)
	var target := skeleton.global_transform.affine_inverse() * hips_world
	skeleton.set_bone_pose_position(_hips, current.lerp(target, weight))
	if not is_instance_valid(leg_ik):
		return
	for side in 2:
		var ankle := input.ankles_world[side]
		if not input.planted[side]:
			ankle = StairFootPlanner.limit_ankle(input.stair_profile, StairFootPlanner.hip_joint(input.stair_profile, hips_world, forward, side), ankle)
		foot_targets[side].global_position = ankle
		knee_poles[side].global_position = ankle + forward * 0.55 + Vector3.UP * 0.45
	leg_ik.influence = weight
	leg_ik.active = weight > 0.001
