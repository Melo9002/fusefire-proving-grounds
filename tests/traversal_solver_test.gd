extends SceneTree
## Environmental traversal solver (pure): deterministic contacts, ladder rung alternation and continuity, mount/dismount weights, descent, vault hand contact.
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
	check(TraversalSolver.rung_count_for(profile, length) == 12, "The authored 4 m ladder has 12 rungs (%d)" % TraversalSolver.rung_count_for(profile, length))
	check(is_equal_approx(TraversalSolver.rung_height(profile, 11), 3.83), "The top rung is at 3.83 m (%.2f)" % TraversalSolver.rung_height(profile, 11))

	# ---- Determinism: no state, no clock. Any order of evaluation gives identical poses.
	var heights: Array[float] = []
	for i in range(0, 401):
		heights.append(i * 0.01)
	var forward := {}
	for h in heights:
		forward[h] = TraversalSolver.ladder_pose(profile, h, length, 1).hash()
	var shuffled := heights.duplicate()
	shuffled.reverse()
	var same := true
	for h in shuffled:
		if TraversalSolver.ladder_pose(profile, h, length, 1).hash() != forward[h]:
			same = false
	check(same, "The ladder pose is a pure function of height: reverse-order evaluation matches")

	# ---- Climb sweep, 1 cm steps: continuity, contacts on rungs, alternation.
	var previous: Dictionary = {}
	var worst_jump := 0.0
	var contact_errors := 0
	var contacts_checked := 0
	var parity_ok := true
	var hand_changes := [0, 0]
	var foot_changes := [0, 0]
	var last_rungs := [[-2, -2], [-2, -2]]
	for h in heights:
		var pose := TraversalSolver.ladder_pose(profile, h, length, 1)
		for key in ["hands", "feet"]:
			if not previous.is_empty():
				for side in 2:
					worst_jump = maxf(worst_jump, (pose[key][side] as Vector3).distance_to(previous[key][side]))
		for side in 2:
			if pose.hand_swing[side] == 0.0 and pose.hand_rung[side] >= 0 and pose.hand_deck[side] == 0.0:
				contacts_checked += 1
				var expected := TraversalSolver.rung_height(profile, pose.hand_rung[side]) - h
				if absf((pose.hands[side] as Vector3).y - expected) > 0.002:
					contact_errors += 1
			if pose.foot_swing[side] == 0.0 and pose.foot_rung[side] >= 0:
				contacts_checked += 1
				var expected_foot := TraversalSolver.rung_height(profile, pose.foot_rung[side]) - h + profile.ankle_above_rung
				if absf((pose.feet[side] as Vector3).y - expected_foot) > 0.002:
					contact_errors += 1
			if pose.hand_rung[side] != last_rungs[0][side]:
				hand_changes[side] += 1
				last_rungs[0][side] = pose.hand_rung[side]
			if pose.foot_rung[side] != last_rungs[1][side]:
				foot_changes[side] += 1
				last_rungs[1][side] = pose.foot_rung[side]
		if pose.hand_rung[0] >= 0 and pose.hand_rung[1] >= 0 and pose.hand_rung[0] == pose.hand_rung[1]:
			parity_ok = false
		if pose.foot_rung[0] >= 0 and pose.foot_rung[1] >= 0 and pose.foot_rung[0] == pose.foot_rung[1]:
			parity_ok = false
		if pose.hand_rung[0] >= 0 and pose.foot_rung[1] >= 0 and (pose.hand_rung[0] % 2) != (pose.foot_rung[1] % 2):
			parity_ok = false   # the left hand and the right foot share a rung parity (contralateral climb)
		previous = pose
	print("  ladder climb: worst limb target step %.3f m per cm, %d contacts checked, rung changes hands %s feet %s" % [worst_jump, contacts_checked, hand_changes, foot_changes])
	check(worst_jump < 0.06, "No limb target teleports between 1 cm steps (worst %.3f m; the swing is a travel, not a jump)" % worst_jump)
	check(contact_errors == 0 and contacts_checked > 100, "A planted hand or foot is exactly on its rung (%d errors in %d)" % [contact_errors, contacts_checked])
	check(parity_ok, "The two hands (and the two feet) are never on the same rung, and the climb is contralateral")
	check(hand_changes[0] >= 5 and foot_changes[0] >= 5 and absi(hand_changes[0] - hand_changes[1]) <= 2, "Each limb changes rung about once per two rungs of climb (hands %s, feet %s)" % [hand_changes, foot_changes])

	# ---- Mount and dismount.
	var bottom := TraversalSolver.ladder_pose(profile, 0.0, length, 1)
	var middle := TraversalSolver.ladder_pose(profile, 2.0, length, 1)
	var top := TraversalSolver.ladder_pose(profile, length, length, 1)
	check(bottom.weight == 0.0 and middle.weight == 1.0 and top.weight == 0.0, "The pose is released at the floor, full mid-ladder and released again at the top (%.2f %.2f %.2f)" % [bottom.weight, middle.weight, top.weight])
	var near_top := TraversalSolver.ladder_pose(profile, length - 0.2, length, 1)
	check(near_top.hand_rung[0] == -1 and near_top.hand_rung[1] == -1 and near_top.hand_deck[0] > 0.99, "Near the top the hands have taken the deck edge")
	var hands_y: float = (near_top.hands[0] as Vector3).y
	check(hands_y > 0.0 and hands_y < 0.3 and (near_top.hands[0] as Vector3).z > profile.ladder_plane_ahead + 0.05, "...just above the deck level and past the rung plane (%.2f m)" % hands_y)

	# ---- Descent: same weights mirrored, limbs picked up at the other end of the window; also deterministic.
	var down_mid := TraversalSolver.ladder_pose(profile, 2.0, length, -1)
	check(down_mid.weight == 1.0 and down_mid.head_pitch_degrees < 0.0 and middle.head_pitch_degrees > 0.0, "Descending the head looks down, climbing up")
	var differs := 0
	for h in heights:
		var up_pose := TraversalSolver.ladder_pose(profile, h, length, 1)
		var down_pose := TraversalSolver.ladder_pose(profile, h, length, -1)
		if up_pose.hand_swing != down_pose.hand_swing:
			differs += 1
		for side in 2:
			if up_pose.hand_swing[side] == 0.0 and down_pose.hand_swing[side] == 0.0:
				if up_pose.hand_rung[side] != down_pose.hand_rung[side]:
					differs += 100
	check(differs > 0 and differs < 1500, "Descent is not the ascent reversed in place: swings happen at different heights, planted rungs disagree only at swap points (%d)" % differs)
	previous = {}
	var worst_down := 0.0
	for i in range(heights.size() - 1, -1, -1):
		var pose := TraversalSolver.ladder_pose(profile, heights[i], length, -1)
		if not previous.is_empty():
			for key in ["hands", "feet"]:
				for side in 2:
					worst_down = maxf(worst_down, (pose[key][side] as Vector3).distance_to(previous[key][side]))
		previous = pose
	check(worst_down < 0.06, "The descent is continuous too (worst %.3f m per cm)" % worst_down)

	# ---- Body: the pelvis hangs behind the rung plane (the body clears the rungs) and the hands reach forward to it.
	check((middle.hips as Vector3).z < 0.0 and (middle.hands[0] as Vector3).z > (middle.hips as Vector3).z + 0.2, "The pelvis is behind the rungs and the hands are on them")
	check(absf((middle.hands[0] as Vector3).x) < 0.3 and (middle.hands[0] as Vector3).x > 0.0 and (middle.hands[1] as Vector3).x < 0.0, "Left hand on the left, right on the right")

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
