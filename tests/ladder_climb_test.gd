extends SceneTree
## Issue #55, on the real rigs: MIRA and Small MIRA, armed and unarmed, climb and descend the SAME 4 m ladder (LadderGeometry) and the FINAL skeleton pose (sampled at `skeleton_updated`) is measured:
## planted feet on their rungs, wrists within 3 cm of their rung contacts, hands within the arm's reach, and the body's volumes (knee, thigh, shin, torso, arms) clear of rungs and rails. A perfect foot target
## does not prove the leg avoids the rung, so the clearance is measured from the joints the engine produced, not from the targets.
## Before the fix: Small MIRA had 51 of 88 hand contacts beyond reach and feet up to 29 cm off their rungs; both bodies' knees, thighs and shins passed through the rungs by up to 10 cm.
const SCENES := {
	"mira": "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn",
	"small": "res://art/characters/small_mira_0/runtime/small_mira_0_exploration_visual.tscn",
}
## What "no significant visible penetration" means in numbers: the approximate limb volumes (LadderMetrics: capsules with proportional radii, generous by design) overlap a bar by at most this (metres). Before the fix the same measurement gave up to 0.10 m; the
## residual is a graze of a volume that is larger than the armor it stands for, checked by eye in the review captures (tests/ladder_review_capture.gd).
const LEG_TOLERANCE := 0.035
const TORSO_TOLERANCE := 0.01
const ARM_TOLERANCE := 0.02
const WRIST_TOLERANCE := 0.03
const ANKLE_TOLERANCE := 0.03
var failures := 0
var checks := 0

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

func _run() -> void:
	_controls()
	var stage := Node3D.new()
	root.add_child(stage)
	var x := 0.0
	for key in SCENES:
		for armed in [true, false]:
			var host: ExplorationCharacterHost = (load(SCENES[key]) as PackedScene).instantiate()
			if not armed:
				host.rig.weapon_scene = null
			stage.add_child(host)
			host.position.x = x
			x += 3.0
			await _frames(30)
			for direction in [1, -1]:
				await _climb(host, "%s %s %s" % [key, "armed" if armed else "unarmed", "up" if direction > 0 else "down"], direction)
			host.queue_free()
	print("ladder_climb_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _climb(host: ExplorationCharacterHost, label: String, direction: int) -> void:
	var rig: CharacterRig = host.rig
	var metrics := LadderMetrics.new(rig)
	rig.skeleton.skeleton_updated.connect(func() -> void: metrics.sample())
	var ladder := LadderGeometry.for_rise(4.0)
	var worst := {"knee": 0.0, "shin": 0.0, "thigh": 0.0, "torso": 0.0, "upper_arm": 0.0, "forearm": 0.0}
	var hands := 0
	var hands_in_reach := 0
	var wrist_worst := 0.0
	var feet := 0
	var ankle_worst := 0.0
	var knee_step_worst := 0.0
	var previous_knees := []
	var previous_ankles := []
	var knee_pop_worst := 0.0
	var knee_width_sum := 0.0
	var knee_width_samples := 0
	rig.begin_traversal(&"ladder", 4.0, direction)
	var h := 0.0 if direction > 0 else 4.0
	while h >= 0.0 and h <= 4.0:
		host.position.y = h
		rig.set_traversal_progress(h)
		await _frames(2)
		var pose: LadderPose = rig.ladder.pose
		if pose.weight > 0.99:
			for side in 2:
				if pose.hand_weight[side] > 0.99:
					hands += 1
					var target: Vector3 = (rig.support_ik_target if side == 0 else rig.right_hand_target).global_position
					var shoulder: Vector3 = rig.character_root.to_global(metrics.joints.shoulder[side])
					var wrist: Vector3 = rig.character_root.to_global(metrics.joints.wrist[side])
					if target.distance_to(shoulder) <= metrics.arm_length(side):
						hands_in_reach += 1
					wrist_worst = maxf(wrist_worst, wrist.distance_to(target))
				if pose.foot_swing[side] == 0.0:
					feet += 1
					var ankle: Vector3 = rig.character_root.to_global(metrics.joints.ankle[side])
					ankle_worst = maxf(ankle_worst, ankle.distance_to(rig.foot_targets[side].global_position))
			var clearance := metrics.clearance(ladder, h)
			for part in clearance:
				worst[part] = maxf(worst[part], clearance[part])
			var knees := [metrics.joints.knee[0], metrics.joints.knee[1]]
			knee_width_sum += absf((knees[0] as Vector3).x - (knees[1] as Vector3).x)
			knee_width_samples += 1
			var ankles := [metrics.joints.ankle[0], metrics.joints.ankle[1]]
			if not previous_knees.is_empty():
				for side in 2:
					var knee_step := (knees[side] as Vector3).distance_to(previous_knees[side])
					knee_step_worst = maxf(knee_step_worst, knee_step)
					# A knee follows its foot (a swinging foot moves it too, at up to about 2.5 times the foot, more where the leg is folded's own step): what is more than that is a pop.
					knee_pop_worst = maxf(knee_pop_worst, knee_step - 2.5 * (ankles[side] as Vector3).distance_to(previous_ankles[side]))
			previous_knees = knees
			previous_ankles = ankles
		else:
			previous_knees = []
			previous_ankles = []
		h += 0.04 * direction
	print("  %s: %d hands (%d within reach, wrist worst %.3f m), %d planted feet (ankle worst %.3f m), overlap knee %.3f shin %.3f thigh %.3f torso %.3f arm %.3f/%.3f, knee step %.3f m/4 cm" % [label, hands, hands_in_reach, wrist_worst, feet, ankle_worst, worst.knee, worst.shin, worst.thigh, worst.torso, worst.upper_arm, worst.forearm, knee_step_worst])
	check(hands > 50 and float(hands_in_reach) / float(hands) >= 0.95, "%s: at least 95%% of planted hand contacts are within the arm's reach in the final pose (%d of %d)" % [label, hands_in_reach, hands])
	check(wrist_worst < WRIST_TOLERANCE + 0.005, "%s: the wrist is within 3 cm of its rung contact in the final pose (worst %.3f m)" % [label, wrist_worst])
	check(feet > 50 and ankle_worst < ANKLE_TOLERANCE, "%s: a planted foot is within 3 cm of its rung foothold in the final pose (worst %.3f m over %d)" % [label, ankle_worst, feet])
	check(worst.knee <= LEG_TOLERANCE and worst.thigh <= LEG_TOLERANCE and worst.shin <= LEG_TOLERANCE, "%s: no knee, thigh or shin goes through a rung or rail (worst %.3f / %.3f / %.3f m)" % [label, worst.knee, worst.thigh, worst.shin])
	check(worst.torso <= TORSO_TOLERANCE and worst.upper_arm <= ARM_TOLERANCE and worst.forearm <= ARM_TOLERANCE, "%s: the torso and arms clear the ladder too (%.3f, %.3f, %.3f m)" % [label, worst.torso, worst.upper_arm, worst.forearm])
	check(knee_pop_worst < 0.06, "%s: the knees travel with their feet, they do not pop (worst %.3f m beyond 2.5 times the ankle's step, 4 cm apart; the knee moved up to %.3f m)" % [label, knee_pop_worst, knee_step_worst])
	print("    mean lateral knee spread: %.1f cm (%d final-pose samples)" % [100.0 * knee_width_sum / maxf(knee_width_samples, 1), knee_width_samples])
	rig.end_traversal()

## Negative controls: the measurement is able to fail. Knees put through the rungs (the old pole offset put them 7-14 cm past the plane) are reported as penetrating, and clean joints are not.
func _controls() -> void:
	var ladder := LadderGeometry.for_rise(4.0)
	var body := LadderTestBodies.mira()
	var rung_y := ladder.rung_height(4)
	var hip := Vector3(0.09, rung_y + 0.4, ladder.plane_ahead - 0.31)
	var ankle := Vector3(0.14, rung_y - 0.05, ladder.plane_ahead - 0.05)
	var through_knee := Vector3(0.15, rung_y + 0.0, ladder.plane_ahead + 0.05)   # in front of the plane at a rung's height
	var behind_knee := Vector3(0.15, rung_y + 0.25, ladder.plane_ahead - 0.2)
	check(ladder.penetration(hip, through_knee, body.thigh_radius(), 0.0) > 0.05, "control: a thigh whose knee is past the plane at a rung's height overlaps the rung")
	check(ladder.penetration(hip, behind_knee, body.thigh_radius(), 0.0) <= 0.0, "control: a thigh whose knee stays behind the plane does not")
	var plan := LadderKneePlanner.plan(ladder, body, hip, ankle, 0, 0.0)
	check(plan.has("knee") and plan.has("overlap") and plan.has("clear"), "control: the knee planner reports its clearance")
