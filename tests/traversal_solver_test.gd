extends SceneTree
## Environmental traversal solver (pure): the ladder is the shared LadderGeometry, the body is a LadderBody (measured limbs), and the pose is deterministic, continuous, reachable and on the rungs for BOTH
## humanoids; mount/dismount weights, descent and the vault hand contact. The ladder contract changed in issue #55 (anatomy-derived windows, 0.25 m pitch, a wrist that holds the rung from below and behind):
## the invariants (pure, continuous, contacts exactly on the rung, left and right where they belong, released at the ends) are the same ones the earlier version asserted.
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var profile := TraversalProfile.new()
	var length := 4.0
	var geometry := LadderGeometry.for_rise(length)
	check(geometry.rung_count() == 15 and is_equal_approx(geometry.rung_height(14), 3.75), "The authored 4 m ladder has 15 rungs, the top at 3.75 m (%d, %.2f)" % [geometry.rung_count(), geometry.rung_height(14)])
	check(LadderGeometry.for_rise(3.0).rung_count() == 11 and is_equal_approx(LadderGeometry.for_rise(3.0).spacing(), geometry.spacing()), "A 3 m ladder has 11 rungs at the SAME pitch (not a stretched 4 m ladder)")
	var bodies := {"mira": LadderTestBodies.mira(), "small": LadderTestBodies.small_mira()}
	for key in bodies:
		_ladder_checks(key, profile, geometry, bodies[key])
	# Both bodies climb the same rungs: whatever a planted limb holds is a rung of the one geometry.
	var rungs_agree := true
	for key in bodies:
		for h in range(0, 401, 7):
			var pose := TraversalSolver.ladder_pose(profile, geometry, bodies[key], h * 0.01, 1)
			for side in 2:
				if pose.foot_rung[side] >= 0 and pose.foot_swing[side] == 0.0:
					var plan := TraversalSolver.plan_ladder(profile, geometry, bodies[key])
					rungs_agree = rungs_agree and absf((pose.feet[side] as Vector3).y - (geometry.rung_height(pose.foot_rung[side]) - h * 0.01 + float(plan.ankle_above))) < 0.002
	check(rungs_agree, "Both bodies' planted feet are on rungs of the one shared ladder")
	var mira_plan := TraversalSolver.plan_ladder(profile, geometry, bodies.mira)
	var small_plan := TraversalSolver.plan_ladder(profile, geometry, bodies.small)
	check((small_plan.hips as Vector3).y < (mira_plan.hips as Vector3).y - 0.1 and float(small_plan.shoulder_height) < float(mira_plan.shoulder_height) - 0.2, "The plan follows the body: Small MIRA's pelvis and shoulders hang lower than MIRA's (%.2f vs %.2f m shoulders)" % [small_plan.shoulder_height, mira_plan.shoulder_height])

	# ---- Unreachable contacts are reported, never presented as a success: an arm too short for the rungs says so.
	var stubby := LadderTestBodies.small_mira()
	stubby.upper_arm = 0.03
	stubby.forearm = 0.03
	var reported := 0
	var asked := 0
	for h in range(80, 321, 5):
		var pose := TraversalSolver.ladder_pose(profile, geometry, stubby, h * 0.01, 1)
		for side in 2:
			if pose.hand_deck[side] < 0.5:
				asked += 1
				if not pose.hand_reachable[side]:
					reported += 1
	check(asked > 20 and reported > asked * 0.9, "A body whose arms cannot span the rungs has its hand contacts reported unreachable (%d of %d)" % [reported, asked])
	var legless := LadderTestBodies.mira()
	# Legs that cannot span even the stance (0.30 m of hip-to-ankle offset): the plan reports it. (0.12 m legs span it, and the plan then places the feet window to suit the hips: not an unreachable contact.)
	legless.thigh = 0.04
	legless.shin = 0.04
	var feet_reported := 0
	var feet_asked := 0
	for h in range(80, 321, 5):
		var pose := TraversalSolver.ladder_pose(profile, geometry, legless, h * 0.01, 1)
		for side in 2:
			feet_asked += 1
			if not pose.foot_reachable[side]:
				feet_reported += 1
	check(feet_reported > feet_asked * 0.8, "...and so are foot contacts for legs too short for the rungs (%d of %d)" % [feet_reported, feet_asked])

	# ---- Vault: hands reach the obstacle top and stay on it while the body crosses; free at the start and the end.
	var start := TraversalSolver.vault_pose(profile, 0.0, 0.9, 1.0, 0.3, Vector3.ZERO)
	var over := TraversalSolver.vault_pose(profile, 1.5, 0.9, 1.0, 0.3, Vector3(0, 1.1, 0.5))
	var landed := TraversalSolver.vault_pose(profile, 3.0, 0.9, 1.0, 0.3, Vector3(0, 0.0, 1.0))
	check(start.weight == 0.0 and over.weight > 0.9 and landed.weight == 0.0, "The vault pose is released before and after (%.2f %.2f %.2f)" % [start.weight, over.weight, landed.weight])
	check(over.hands[0] != null and over.hands[1] != null and (over.hands[0] as Vector3).y < 0.0, "Crossing, both hands are on the obstacle top, below the root that is above it")
	check(start.hands[0] == null and landed.hands[0] == null, "No hand support before the reach or after the landing")
	var same_vault := TraversalSolver.vault_pose(profile, 1.5, 0.9, 1.0, 0.3, Vector3(0, 1.1, 0.5))
	check(same_vault.hash() == over.hash(), "The vault pose is deterministic")

	print("Traversal solver: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)


func _ladder_checks(key: String, profile: TraversalProfile, geometry: LadderGeometry, body: LadderBody) -> void:
	var length := geometry.rise
	var plan := TraversalSolver.plan_ladder(profile, geometry, body)
	var hand_below := TraversalSolver.GRIP_BELOW * body.ratio
	# ---- Determinism: no state, no clock. Any order of evaluation gives identical poses.
	var heights: Array[float] = []
	for i in range(0, 401):
		heights.append(i * 0.01)
	var forward := {}
	for h in heights:
		forward[h] = TraversalSolver.ladder_pose(profile, geometry, body, h, 1).hash()
	var shuffled := heights.duplicate()
	shuffled.reverse()
	var same := true
	for h in shuffled:
		if TraversalSolver.ladder_pose(profile, geometry, body, h, 1).hash() != forward[h]:
			same = false
	check(same, "%s: the ladder pose is a pure function of height: reverse-order evaluation matches" % key)

	# ---- Climb sweep, 1 cm steps: continuity, contacts on rungs, the step each limb takes.
	var previous: Dictionary = {}
	var worst_jump := 0.0
	var contact_errors := 0
	var contacts_checked := 0
	var hands_reachable := 0
	var hands_planted := 0
	var rung_change_sizes := {}
	var last_rungs := [[-2, -2], [-2, -2]]
	var hand_changes := [0, 0]
	var foot_changes := [0, 0]
	var spread_ok := true
	for h in heights:
		var pose := TraversalSolver.ladder_pose(profile, geometry, body, h, 1)
		for k in ["hands", "feet"]:
			if not previous.is_empty():
				for side in 2:
					worst_jump = maxf(worst_jump, (pose[k][side] as Vector3).distance_to(previous[k][side]))
		for side in 2:
			if pose.hand_swing[side] == 0.0 and pose.hand_rung[side] >= 0 and pose.hand_deck[side] == 0.0:
				contacts_checked += 1
				var expected := geometry.rung_height(pose.hand_rung[side]) - h - hand_below
				if absf((pose.hands[side] as Vector3).y - expected) > 0.002:
					contact_errors += 1
				if pose.weight == 1.0:
					hands_planted += 1
					if pose.hand_reachable[side]:
						hands_reachable += 1
			if pose.foot_swing[side] == 0.0 and pose.foot_rung[side] >= 0:
				contacts_checked += 1
				var expected_foot := geometry.rung_height(pose.foot_rung[side]) - h + float(plan.ankle_above)
				if absf((pose.feet[side] as Vector3).y - expected_foot) > 0.002:
					contact_errors += 1
			for limb in 2:
				var rung: int = pose.hand_rung[side] if limb == 0 else pose.foot_rung[side]
				if rung != last_rungs[limb][side]:
					if last_rungs[limb][side] >= 0 and rung >= 0:
						var jump := absi(rung - int(last_rungs[limb][side]))
						rung_change_sizes[jump] = int(rung_change_sizes.get(jump, 0)) + 1
					if limb == 0:
						hand_changes[side] += 1
					else:
						foot_changes[side] += 1
					last_rungs[limb][side] = rung
		# The two hands (and the two feet) are never more than a step and a rung apart: a climber does not straddle the ladder.
		if pose.hand_rung[0] >= 0 and pose.hand_rung[1] >= 0:
			spread_ok = spread_ok and absi(pose.hand_rung[0] - pose.hand_rung[1]) <= int(plan.hand_step) + 1
		if pose.foot_rung[0] >= 0 and pose.foot_rung[1] >= 0:
			spread_ok = spread_ok and absi(pose.foot_rung[0] - pose.foot_rung[1]) <= int(plan.foot_step) + 1
		previous = pose
	print("  %s ladder climb: hand step %d, foot step %d, worst limb target step %.3f m per cm, %d contacts checked, rung changes hands %s feet %s" % [key, plan.hand_step, plan.foot_step, worst_jump, contacts_checked, hand_changes, foot_changes])
	check(worst_jump < 0.06, "%s: no limb target teleports between 1 cm steps (worst %.3f m; the swing is a travel, not a jump)" % [key, worst_jump])
	check(contact_errors == 0 and contacts_checked > 100, "%s: a planted hand or foot is exactly where its rung puts it (%d errors in %d)" % [key, contact_errors, contacts_checked])
	check(spread_ok, "%s: the two hands and the two feet stay within a step and a rung of each other" % key)
	check(hand_changes[0] >= 5 and foot_changes[0] >= 5 and absi(hand_changes[0] - hand_changes[1]) <= 2 and absi(foot_changes[0] - foot_changes[1]) <= 2, "%s: each limb changes rung steadily as the climb goes on (hands %s, feet %s)" % [key, hand_changes, foot_changes])
	var steps_ok := true
	for jump in rung_change_sizes:
		steps_ok = steps_ok and int(jump) <= maxi(int(plan.hand_step), int(plan.foot_step))
	check(steps_ok, "%s: a limb never skips more rungs than its step (%s)" % [key, rung_change_sizes])
	check(hands_planted > 100 and float(hands_reachable) / float(hands_planted) >= 0.95, "%s: at least 95%% of planted hand contacts are within the arm's reach by the plan (%d of %d)" % [key, hands_reachable, hands_planted])

	# ---- Mount and dismount.
	var bottom := TraversalSolver.ladder_pose(profile, geometry, body, 0.0, 1)
	var middle := TraversalSolver.ladder_pose(profile, geometry, body, 2.0, 1)
	var top := TraversalSolver.ladder_pose(profile, geometry, body, length, 1)
	check(bottom.weight == 0.0 and middle.weight == 1.0 and top.weight == 0.0, "%s: the pose is released at the floor, full mid-ladder and released again at the top (%.2f %.2f %.2f)" % [key, bottom.weight, middle.weight, top.weight])
	var near_top := TraversalSolver.ladder_pose(profile, geometry, body, length - 0.2, 1)
	check(near_top.hand_rung[0] == -1 and near_top.hand_rung[1] == -1 and near_top.hand_deck[0] > 0.99, "%s: near the top the hands have taken the deck edge" % key)
	var hands_y: float = (near_top.hands[0] as Vector3).y
	check(hands_y > 0.0 and hands_y < 0.3, "%s: ...just above the deck level (%.2f m)" % [key, hands_y])

	# ---- Descent: same weights mirrored, limbs picked up at the other end of the window; also deterministic.
	var down_mid := TraversalSolver.ladder_pose(profile, geometry, body, 2.0, -1)
	check(down_mid.weight == 1.0 and down_mid.head_pitch_degrees < 0.0 and middle.head_pitch_degrees > 0.0, "%s: descending the head looks down, climbing up" % key)
	var differs := 0
	for h in heights:
		var up_pose := TraversalSolver.ladder_pose(profile, geometry, body, h, 1)
		var down_pose := TraversalSolver.ladder_pose(profile, geometry, body, h, -1)
		if up_pose.hand_swing != down_pose.hand_swing:
			differs += 1
	check(differs > 0, "%s: descent is not the ascent reversed in place: swings happen at different heights (%d)" % [key, differs])
	previous = {}
	var worst_down := 0.0
	for i in range(heights.size() - 1, -1, -1):
		var pose := TraversalSolver.ladder_pose(profile, geometry, body, heights[i], -1)
		if not previous.is_empty():
			for k in ["hands", "feet"]:
				for side in 2:
					worst_down = maxf(worst_down, (pose[k][side] as Vector3).distance_to(previous[k][side]))
		previous = pose
	check(worst_down < 0.06, "%s: the descent is continuous too (worst %.3f m per cm)" % [key, worst_down])

	# ---- Body: the pelvis hangs behind the rung plane (the body clears the rungs) and the hands reach forward to it, left on the left, right on the right.
	check((middle.hips as Vector3).z < geometry.plane_ahead - 0.1 and (middle.hands[0] as Vector3).z > (middle.hips as Vector3).z + 0.15, "%s: the pelvis is behind the rungs and the hands are on them" % key)
	check((middle.hands[0] as Vector3).x > 0.0 and (middle.hands[1] as Vector3).x < 0.0 and (middle.feet[0] as Vector3).x > 0.0 and (middle.feet[1] as Vector3).x < 0.0 and absf((middle.hands[0] as Vector3).x) < geometry.clear_width() * 0.5, "%s: left hand and foot on the left, right on the right, inside the rails" % key)
