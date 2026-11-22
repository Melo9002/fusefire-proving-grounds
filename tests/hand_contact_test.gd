extends SceneTree
## Task 11: hand contacts have one typed claim (HandContact) and one writer (CharacterRig.claim_hand_contact), and no contact outlives its producer.
## Covers, on BOTH humanoids and armed and unarmed: the writer's left/right indexing and world-to-skeleton conversion, a hand nobody claims is released (the defect: a ladder's last hand weight stayed on the grip
## after the hands let go and replaced the rifle's orientation), the ladder's hands reach their rungs in the FINAL pose, interruption and repeated entry leave nothing behind, and an unarmed character goes back to the hang.
const SCENES := {
	"mira": "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn",
	"small": "res://art/characters/small_mira_0/runtime/small_mira_0_exploration_visual.tscn",
}
var failures := 0
var checks := 0
var _hands := {}   # host -> [left, right] wrist positions in the FINAL pose (sampled at skeleton_updated)
var _shoulders := {}   # likewise the shoulders

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _spawn(stage: Node3D, key: String, armed: bool) -> ExplorationCharacterHost:
	var host: ExplorationCharacterHost = (load(SCENES[key]) as PackedScene).instantiate()
	if not armed:
		host.rig.weapon_scene = null
	stage.add_child(host)
	var skeleton: Skeleton3D = host.rig.skeleton
	skeleton.skeleton_updated.connect(func() -> void:
		var left := skeleton.find_bone(host.rig.bones.left_arm[2])
		var right := skeleton.find_bone(host.rig.bones.right_arm[2])
		_hands[host] = [skeleton.global_transform * skeleton.get_bone_global_pose(left).origin, skeleton.global_transform * skeleton.get_bone_global_pose(right).origin]
		var sl := skeleton.find_bone(host.rig.bones.left_arm[0])
		var sr := skeleton.find_bone(host.rig.bones.right_arm[0])
		_shoulders[host] = [skeleton.global_transform * skeleton.get_bone_global_pose(sl).origin, skeleton.global_transform * skeleton.get_bone_global_pose(sr).origin])
	return host

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var x := 0.0
	for key in SCENES:
		for armed in [true, false]:
			var host := _spawn(stage, key, armed)
			host.position.x = x
			x += 3.0
			await _frames(30)
			var label := "%s %s" % [key, "armed" if armed else "unarmed"]
			_writer_checks(host.rig, label)
			await _release_checks(host.rig, label, armed)
			await _ladder_checks(host, label, armed)
			host.queue_free()
	print("hand_contact_test: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

## The one writer: a claim moves ITS hand's wrist target and fills ITS slot, in skeleton space, and touches nothing of the other hand.
func _writer_checks(rig: CharacterRig, label: String) -> void:
	var grip: HandGripModifier = rig.grip_modifier
	var to_skeleton := rig.skeleton.global_basis.orthonormalized().inverse()
	var fingers := Vector3(0.0, 1.0, 0.0)
	var palm := Vector3(0.0, 0.0, 1.0)
	grip.contact_weight = [0.0, 0.0]
	grip.contact_forward = [Vector3.FORWARD, Vector3.FORWARD]
	var other: Vector3 = rig.support_ik_target.global_position
	var point := Vector3(0.7, 1.1, 0.4)
	rig.claim_hand_contact(HandContact.make(HandContact.Hand.RIGHT, point, fingers, palm, 0.7, 0.4))
	check(rig.right_hand_target.global_position.is_equal_approx(point) and rig.support_ik_target.global_position == other, "%s: a RIGHT claim moves the right wrist target and only it" % label)
	check(is_equal_approx(grip.contact_weight[1], 0.7) and grip.contact_weight[0] == 0.0 and (grip.contact_forward[1] as Vector3).is_equal_approx(to_skeleton * fingers) and (grip.contact_normal[1] as Vector3).is_equal_approx(to_skeleton * palm) and is_equal_approx(grip.curl[1], 0.4), "%s: ...fills the right slot (index 1) in skeleton space; the left slot is untouched" % label)
	var right_before: Vector3 = rig.right_hand_target.global_position
	rig.claim_hand_contact(HandContact.make(HandContact.Hand.LEFT, point + Vector3.UP, fingers, palm, 0.3))
	check(rig.support_ik_target.global_position.is_equal_approx(point + Vector3.UP) and rig.right_hand_target.global_position == right_before and is_equal_approx(grip.contact_weight[0], 0.3) and is_equal_approx(grip.contact_weight[1], 0.7), "%s: a LEFT claim moves the left wrist target and fills slot 0; NO_CURL leaves the closure alone" % label)
	# The conversion is real only when the skeleton is turned: the same world directions arrive rotated into ITS frame.
	var turned := rig.skeleton.rotation
	rig.skeleton.rotation.y += deg_to_rad(90.0)
	var to_turned := rig.skeleton.global_basis.orthonormalized().inverse()
	rig.claim_hand_contact(HandContact.make(HandContact.Hand.LEFT, point, fingers + Vector3.RIGHT, palm, 1.0))
	check((grip.contact_forward[0] as Vector3).is_equal_approx(to_turned * (fingers + Vector3.RIGHT)) and not (grip.contact_forward[0] as Vector3).is_equal_approx(fingers + Vector3.RIGHT), "%s: the world direction is converted into the (turned) skeleton's frame, here and nowhere else" % label)
	rig.skeleton.rotation = turned
	rig.release_hand_contacts()
	check(grip.contact_weight == [0.0, 0.0], "%s: release_hand_contacts lets go of both" % label)

## A hand nobody claims in a pass is released by the next pass (an armed hand goes back to the rifle; an unarmed one is re-claimed by the hang, never left on a stale contact).
func _release_checks(rig: CharacterRig, label: String, armed: bool) -> void:
	var grip: HandGripModifier = rig.grip_modifier
	rig.claim_hand_contact(HandContact.make(HandContact.Hand.RIGHT, rig.right_hand_target.global_position, Vector3.UP, Vector3.BACK, 0.9))
	rig.claim_hand_contact(HandContact.make(HandContact.Hand.LEFT, rig.support_ik_target.global_position, Vector3.UP, Vector3.BACK, 0.9))
	await _frames(3)
	if armed:
		check(grip.contact_weight == [0.0, 0.0] and grip.orient_weight == 1.0, "%s: a contact nobody claims again is released and the weapon's grip owns the hands" % label)
	else:
		check(grip.contact_weight == [CharacterRig.HANGING_HAND_WEIGHT, CharacterRig.HANGING_HAND_WEIGHT] and (grip.contact_forward[1] as Vector3).y < -0.5, "%s: the relaxed hang is claimed every pass and replaces any stale contact" % label)

func _ladder_checks(host: ExplorationCharacterHost, label: String, armed: bool) -> void:
	var rig: CharacterRig = host.rig
	var grip: HandGripModifier = rig.grip_modifier
	rig.begin_traversal(&"ladder", 4.0, 1)
	var worst := 0.0
	var reachable := 0
	var out_of_reach := 0
	var stale := 0.0
	var released_steps := 0
	var reached := true
	var h := 1.0
	while h <= 4.3:
		rig.set_traversal_progress(h)
		await _frames(2)
		var pose: LadderPose = rig.ladder.pose
		for side in 2:
			if pose.hand_weight[side] > 0.9:
				# In the FINAL pose the wrist is on its target (side 0 is the ladder's left, 1 its right), whenever the arm can reach it. A rung farther than the arm is long is an UNREACHABLE contact: the arm
				# stretches toward it and stops short (a known limit of the ladder's rung windows on a short-armed body, see docs/claude/contact-audit-2026-11-22.md); it is counted, not hidden.
				var target: Vector3 = (rig.support_ik_target if side == 0 else rig.right_hand_target).global_position
				if target.distance_to(_shoulders[host][side]) <= rig._arm_length(1 - side) * 0.97:
					reachable += 1
					worst = maxf(worst, (_hands[host][side] as Vector3).distance_to(target))
				else:
					out_of_reach += 1
		if not rig.traversal_contacts_active():
			released_steps += 1
			var expected := 0.0 if armed else CharacterRig.HANGING_HAND_WEIGHT   # the unarmed hand hangs
			stale = maxf(stale, maxf(absf(grip.contact_weight[0] - expected), absf(grip.contact_weight[1] - expected)))
			if armed:
				reached = reached and grip.orient_weight == 1.0
		h += 0.05
	check(reachable > 20 and worst < 0.03, "%s: on the ladder a wrist reaches every rung contact its arm can reach, in the final pose (%d reachable samples, worst miss %.3f m; %d samples out of reach)" % [label, reachable, worst, out_of_reach])
	print("  %s: ladder wrists: worst reachable miss %.3f m, %d reachable / %d out-of-reach samples" % [label, worst, reachable, out_of_reach])
	check(released_steps > 10 and stale == 0.0, "%s: once the hands let go (%d steps) no ladder contact weight is left on the grip (stale %.4f)" % [label, released_steps, stale])
	if armed:
		check(reached, "%s: ...and the rifle's orientation owns the hands again" % label)
	# Interruption mid-climb, repeatedly: nothing is left, and the ordinary pose owns the hands.
	for round in 3:
		rig.end_traversal()
		rig.begin_traversal(&"ladder", 4.0, 1)
		rig.set_traversal_progress(2.0)
		await _frames(2)
		check(grip.contact_weight[0] > 0.9 and grip.contact_weight[1] > 0.9, "%s: entry %d claims both hands" % [label, round])
		rig.end_traversal()
		await _frames(2)
		if armed:
			check(grip.contact_weight == [0.0, 0.0] and not rig.is_weapon_stowed(), "%s: interruption %d leaves no contact and the rifle back in the hand" % [label, round])
		else:
			check(grip.contact_weight == [CharacterRig.HANGING_HAND_WEIGHT, CharacterRig.HANGING_HAND_WEIGHT], "%s: interruption %d returns the unarmed hands to the hang" % [label, round])
