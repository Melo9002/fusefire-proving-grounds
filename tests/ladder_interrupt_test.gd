extends SceneTree
## Regression for issue 67: ending a ladder traversal mid-climb (a defeat, a cancelled order, the Workbench's "interrupt the climb") dropped the body from the climbing pose to the animation in ONE frame
## (pelvis and both thighs about 44 cm). CharacterRig.end_traversal now eases the climbing pose out over `traversal_release_seconds`. Negative control: 0 is the old instant release and must show the jump.
var failures := 0
var checks := 0
var hips: Array[Vector3] = []
var feet: Array[Vector3] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _grab(bench) -> void:
	var sk: Skeleton3D = bench.rig.skeleton
	hips.append(sk.get_bone_global_pose(sk.find_bone("mixamorig_Hips")).origin)
	feet.append(sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftFoot")).origin)

## The largest one-frame step of the pelvis and of a foot after a climb 1.5 m up the ladder is ended, with the pose eased out over `release` seconds.
func _interrupt(bench, release: float) -> Vector2:
	bench.rig.traversal_release_seconds = release
	bench.start_ladder_demo(3.0, 1, 0.0)
	bench.set_ladder_height(1.5)
	for i in 40: await process_frame
	var last_climbing := hips.size() - 1   # the step INTO the first sample after the end is the one that matters
	bench.end_ladder_demo()
	for i in 40: await process_frame
	var worst := Vector2.ZERO
	for index in range(maxi(last_climbing, 0) + 1, hips.size()):
		worst.x = maxf(worst.x, hips[index].distance_to(hips[index - 1]))
		worst.y = maxf(worst.y, feet[index].distance_to(feet[index - 1]))
	return worst

func _run() -> void:
	var bench = load("res://tools/animation_workbench/pose_workbench.tscn").instantiate()
	root.add_child(bench)
	for i in 30: await process_frame
	bench.rig.skeleton.skeleton_updated.connect(func() -> void: _grab(bench))
	var eased: Vector2 = await _interrupt(bench, 0.25)
	var instant: Vector2 = await _interrupt(bench, 0.0)
	print("  interrupting a climb, largest one-frame step (pelvis / foot): eased %.3f / %.3f m, instant (old behaviour) %.3f / %.3f m" % [eased.x, eased.y, instant.x, instant.y])
	check(instant.x > 0.15, "Negative control: the instant release does drop the pelvis (%.3f m in one frame), so this test can see the defect" % instant.x)
	check(eased.x < 0.08, "With the release eased the pelvis moves less than 8 cm in any frame (%.3f m)" % eased.x)
	check(eased.x < instant.x * 0.5, "and at least halves the worst step (%.3f against %.3f m)" % [eased.x, instant.x])
	check(bench.rig.traversal_modifier.input.mode == TraversalPoseInput.Mode.NONE, "once eased, the traversal input is cleared")
	check(not bench.rig.leg_ik.active, "and the leg IK is off")
	print("Ladder interrupt: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
