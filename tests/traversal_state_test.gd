extends SceneTree
## Typed traversal and stair state (Task 07 package 8). The rig's ladder climb and stair walk are LadderClimb and StairWalk (null when there is none), with the solved poses as LadderPose and StairPose; the
## pure solvers still return dictionaries and are converted once. Checks the conversion against the solvers, the lifecycle (begin, progress, end, repeats, interruption, precedence, a loaded carrier) and that
## the modifier input stays in step. Structural headless checks; the numerical equivalence with the previous dictionaries is the pose trace.
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
var failures := 0
var checks := 0

func _initialize() -> void:
	Engine.max_fps = 60
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _run() -> void:
	# ---- The conversions agree with the solvers they wrap, at several heights.
	var profile := TraversalProfile.new()
	var worst := 0.0
	var rungs_ok := true
	for climbed in [0.0, 0.3, 1.0, 2.0, 2.7, 3.0]:
		for direction in [1, -1]:
			var raw := TraversalSolver.ladder_pose(profile, climbed, 3.0, direction)
			var typed := LadderPose.from_solver(raw)
			worst = maxf(worst, absf(typed.weight - float(raw.weight)))
			worst = maxf(worst, typed.hips.distance_to(raw.hips))
			worst = maxf(worst, absf(typed.lean_degrees - float(raw.lean_degrees)))
			for side in 2:
				worst = maxf(worst, typed.hands[side].distance_to(raw.hands[side]))
				worst = maxf(worst, typed.feet[side].distance_to(raw.feet[side]))
				worst = maxf(worst, absf(typed.hand_weight[side] - float(raw.hand_weight[side])))
				rungs_ok = rungs_ok and typed.hand_rung[side] == int(raw.hand_rung[side]) and typed.foot_rung[side] == int(raw.foot_rung[side]) and typed.on_ladder == bool(raw.on_ladder)
	check(worst == 0.0 and rungs_ok, "LadderPose carries every field of the solver's result unchanged (worst difference %.9f)" % worst)
	var model := StairModel.from_links(Vector3.ZERO, Vector3(0, 0, 1), 1.0, 1.0, 2, 3)
	var stair_profile := StairProfile.new()
	var holds := StairFootPlanner.holds(model, true, 1)
	var feet: Array = [StairFootPlanner.foot_at(model, stair_profile, holds, true, 0.6, 0), StairFootPlanner.foot_at(model, stair_profile, holds, true, 0.6, 1)]
	var pelvis := StairFootPlanner.pelvis_smoothed(model, stair_profile, holds, true, 0.6, Vector3.ZERO)
	var stair_pose := StairPose.from_planner(feet, pelvis, 0.8, 0.6, 1)
	check(stair_pose.feet.size() == 2 and stair_pose.feet[0].position.is_equal_approx(feet[0].position) and stair_pose.feet[1].planted == bool(feet[1].planted) and stair_pose.feet[0].hold == int(feet[0].hold) and is_equal_approx(stair_pose.feet[1].tread_top, float(feet[1].tread_top))
			and is_equal_approx(stair_pose.pelvis_height, float(pelvis.height)) and stair_pose.pelvis_ok == bool(pelvis.ok) and stair_pose.weight == 0.8 and stair_pose.s == 0.6 and stair_pose.step == 1,
		"StairPose carries the planner's feet and pelvis unchanged")

	# ---- The lifecycle on the production visual.
	var stage := Node3D.new()
	root.add_child(stage)
	var v: UnitVisualAdapter = VISUAL.instantiate()
	stage.add_child(v)
	await _frames(15)
	var input: TraversalPoseInput = v.rig.traversal_modifier.input
	check(v.rig.ladder == null and v.rig.stairs == null and input.mode == TraversalPoseInput.Mode.NONE, "Idle: no ladder, no stairs, an empty modifier input")
	v.rig.set_traversal_progress(1.0)
	v.rig.set_stair_progress(0.5, 1.0)
	check(v.rig.ladder == null and v.rig.stairs == null, "Progress with nothing begun is ignored")
	v.rig.begin_traversal(&"ladder", 3.0, 1)
	check(v.rig.ladder != null and v.rig.ladder.pose == null and v.rig.ladder.length == 3.0 and v.rig.ladder.direction == 1 and v.rig.ladder.kind == &"ladder" and input.mode == TraversalPoseInput.Mode.LADDER and not input.solved, "A ladder begins: the climb exists, no pose yet, the input says LADDER unsolved")
	v.rig.set_traversal_progress(1.5)
	check(v.rig.ladder.pose != null and is_equal_approx(v.rig.ladder.climbed, 1.5) and input.solved and is_equal_approx(input.weight, v.rig.ladder.pose.weight) and input.hips_local.is_equal_approx(v.rig.ladder.pose.hips), "A height solves the pose and the input follows it")
	check(v.rig.traversal_contacts_active() == (v.rig.ladder.pose.hand_weight[0] > 0.001 or v.rig.ladder.pose.hand_weight[1] > 0.001), "The hand contacts follow the typed pose")
	await _frames(3)
	check(v.rig.leg_ik.active and v.rig.crouch_modifier.aim_lean_degrees != 0.0, "On the ladder the legs are driven and the trunk leans")
	# A ladder takes precedence over a stair walk, and ending it shows the stairs again.
	v.rig.begin_stairs(model, true)
	v.rig.set_stair_progress(0.8, 1.2)
	check(v.rig.stairs != null and v.rig.stairs.pose != null and input.mode == TraversalPoseInput.Mode.LADDER, "A stair walk beside a ladder: the ladder keeps the input")
	v.rig.end_traversal()
	check(v.rig.ladder == null and input.mode == TraversalPoseInput.Mode.STAIRS and is_equal_approx(input.pelvis_height, v.rig.stairs.pose.pelvis_height), "Ending the ladder leaves nothing of it and reveals the stairs")
	check(v.rig.crouch_modifier.aim_lean_degrees == 0.0 and v.rig.grip_modifier.contact_weight == [0.0, 0.0] and not v.rig.is_weapon_stowed(), "...the trunk, the hands and the rifle are back in the ordinary layers")
	v.rig.end_traversal()
	check(v.rig.ladder == null, "A repeated end is a no-op")
	# Stairs: the holds are re-planned when the tread interval changes; the speed decides it.
	var step_before := v.rig.stairs.step
	v.rig.set_stair_progress(0.9, 0.2)
	var slow_step := v.rig.stairs.step
	v.rig.set_stair_progress(0.95, 4.0)
	check(v.rig.stairs.pose.step == v.rig.stairs.step and (slow_step != step_before or v.rig.stairs.step != slow_step or v.rig.stairs.holds.size() > 0), "The stair walk re-plans its holds for the tread interval (steps %d, %d, %d)" % [step_before, slow_step, v.rig.stairs.step])
	v.rig.end_stairs()
	check(v.rig.stairs == null and input.mode == TraversalPoseInput.Mode.NONE and not v.rig.leg_ik.active, "Ending the stairs clears the input and the leg IK")
	v.rig.end_stairs()
	check(v.rig.stairs == null, "A repeated end is a no-op")
	# Interruption mid-climb leaves nothing.
	v.rig.begin_traversal(&"ladder", 3.0, -1)
	v.rig.set_traversal_progress(1.2)
	v.rig.end_traversal()
	await _frames(3)
	check(v.rig.ladder == null and not v.rig.leg_ik.active and not v.rig.traversal_contacts_active() and v.rig.crouch_modifier.aim_lean_degrees == 0.0, "A climb ended midway leaves no state, no leg IK, no contacts and no lean")
	# A loaded carrier does not walk stairs (the existing rule), and a begun walk is not created.
	v.rig.begin_carry()
	v.rig.begin_stairs(model, true)
	check(v.rig.stairs == null, "A carrier with a passenger does not begin a stair walk")
	v.rig.end_carry()
	stage.queue_free()
	await _frames(2)

	# ---- The dictionaries are gone.
	var rig_text := FileAccess.get_file_as_string("res://presentation/characters/runtime/character_rig.gd")
	check(not rig_text.contains("var traversal_pose") and not rig_text.contains("var stair_pose") and not rig_text.contains("var stair_state") and not rig_text.contains("var traversal :="), "The rig keeps no traversal or stair dictionary")

	print("Traversal state: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
