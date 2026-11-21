extends SceneTree
## Ladder pose on the production rig (the MIRA workbench scene): hands and feet reach their rung contacts, joints stay inside human limits, the rifle is slung while
## the hands are on the ladder and back in the hand afterwards, the traversal layers sit in the modifier order and leave nothing behind when it ends.
var failures := 0
var checks := 0
var snap := {}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _grab(rig) -> void:
	var sk: Skeleton3D = rig.rig.skeleton
	for n in ["Hips", "LeftHand", "RightHand", "LeftFoot", "RightFoot", "LeftLeg", "RightLeg", "LeftForeArm", "RightForeArm", "LeftArm", "RightArm", "LeftUpLeg", "RightUpLeg"]:
		snap[n] = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_" + n)).origin

func _run() -> void:
	var rig = load("res://tools/animation_workbench/pose_workbench.tscn").instantiate()
	root.add_child(rig)
	for i in 30: await process_frame
	rig.rig.skeleton.skeleton_updated.connect(func() -> void: _grab(rig))
	var names: Array = rig.rig.skeleton.get_children().filter(func(c: Node) -> bool: return c is SkeletonModifier3D).map(func(c: Node) -> String: return str(c.name))
	check(names == ["Locomotion", "CoverCrouch", "Traversal", "TraversalLegIK", "WeaponPose", "WeaponArmIK", "HandGrip"], "The traversal layers sit after Locomotion and CoverCrouch and before WeaponPose: %s" % [names])
	check(rig.rig.ladder == null and not rig.rig.leg_ik.active, "Idle: no traversal, the leg IK is off")
	check(not rig.rig.is_weapon_stowed(), "Idle: the rifle is in the hand")

	rig.rig.begin_traversal(&"ladder", 4.0, 1)
	var worst_hand := 0.0
	var worst_foot := 0.0
	var min_knee := 999.0
	var min_elbow := 999.0
	var h := 1.0
	while h <= 2.6:
		rig.rig.set_traversal_progress(h)
		for i in 2: await process_frame
		worst_hand = maxf(worst_hand, maxf(snap.LeftHand.distance_to(rig.rig.support_ik_target.global_position), snap.RightHand.distance_to(rig.rig.right_hand_target.global_position)))
		worst_foot = maxf(worst_foot, maxf(snap.LeftFoot.distance_to(rig.rig.foot_targets[0].global_position), snap.RightFoot.distance_to(rig.rig.foot_targets[1].global_position)))
		for side in ["Left", "Right"]:
			min_knee = minf(min_knee, rad_to_deg((snap[side + "UpLeg"] - snap[side + "Leg"]).angle_to(snap[side + "Foot"] - snap[side + "Leg"])))
			min_elbow = minf(min_elbow, rad_to_deg((snap[side + "Arm"] - snap[side + "ForeArm"]).angle_to(snap[side + "Hand"] - snap[side + "ForeArm"])))
		h += 0.05
	print("  mid-ladder sweep: worst hand miss %.3f m, worst foot miss %.3f m, tightest knee %.0f deg, tightest elbow %.0f deg" % [worst_hand, worst_foot, min_knee, min_elbow])
	check(worst_hand < 0.03 and worst_foot < 0.03, "Mid-ladder every hand and foot is on its rung contact (hand %.3f m, foot %.3f m)" % [worst_hand, worst_foot])
	check(min_knee > 35.0 and min_elbow > 35.0, "Knees and elbows stay inside human flexion (knee %.0f, elbow %.0f deg)" % [min_knee, min_elbow])
	check(rig.rig.is_weapon_stowed() and rig.rig.leg_ik.active and rig.rig.crouch_modifier.aim_lean_degrees > 5.0, "On the ladder the rifle is slung, the legs are on IK and the trunk leans in (stowed %s, leg ik %s, lean %.1f)" % [rig.rig.is_weapon_stowed(), rig.rig.leg_ik.active, rig.rig.crouch_modifier.aim_lean_degrees])
	var rl: Transform3D = rig.rig.character_root.global_transform.affine_inverse()
	var hips_local: Vector3 = rl * snap.Hips
	check(hips_local.z < -0.2 and absf(hips_local.y - rig.rig.traversal_profile.hips_height) < 0.03, "The pelvis hangs back from the rung plane at the ladder height (z %.2f, y %.2f)" % [hips_local.z, hips_local.y])
	# The rifle rides on the chest, not in a hand, so the hands are free for the rungs (no hand holds both).
	var weapon_to_chest: float = rig.rig.weapon.global_position.distance_to(snap.RightHand)
	check(weapon_to_chest > 0.15, "The rifle is not in the gripping hand (%.2f m away)" % weapon_to_chest)

	# Mounting at the bottom: the pose is released at the floor and arrives over the mount length.
	rig.rig.set_traversal_progress(0.0)
	for i in 3: await process_frame
	check(rig.rig.ladder.pose.weight == 0.0 and not rig.rig.is_weapon_stowed() and not rig.rig.leg_ik.active, "At the floor the pose is released and the rifle is back in the hand")
	rig.rig.set_traversal_progress(0.25)
	for i in 3: await process_frame
	check(rig.rig.ladder.pose.weight > 0.1 and rig.rig.ladder.pose.weight < 0.9 and rig.rig.is_weapon_stowed(), "Mounting: partly on the ladder, the rifle already travelling to the sling")

	# Interruption: ending the traversal anywhere leaves nothing behind.
	rig.rig.set_traversal_progress(2.0)
	for i in 3: await process_frame
	rig.rig.end_traversal()
	for i in 3: await process_frame
	check(rig.rig.ladder == null and not rig.rig.leg_ik.active, "Interrupted mid-ladder: no traversal state, the leg IK is off")
	check(rig.rig.crouch_modifier.aim_lean_degrees == 0.0 and not rig.rig.is_weapon_stowed() and is_equal_approx(float(rig.rig.grip_modifier.contact_weight[0]) + float(rig.rig.grip_modifier.contact_weight[1]), 0.0), "...no trunk lean, no ladder grip, the rifle back in the hand")
	var after: Vector3 = rl * snap.Hips
	check(absf(after.y - 0.93) < 0.04 and absf(after.z) < 0.05, "...and the pelvis is back at its ordinary place (y %.2f z %.2f)" % [after.y, after.z])
	await create_timer(0.3).timeout
	check(rig.rig.traversal_modifier.weight == 0.0, "The body layer reports no weight once the traversal has ended")

	print("Traversal rig: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
