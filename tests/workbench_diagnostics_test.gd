extends SceneTree
## Task 12: the shared, read-only animation diagnostics (presentation/diagnostics/): RigInspection, PoseStageReport, PresentationMonitor, ContactErrorDiagnostics, MotionTrail, BoneHighlight.
## They are exercised on the non-tactical ExplorationCharacterHost, on BOTH humanoids, armed and unarmed. Each diagnostic has a negative control: a broken profile mapping, a reordered or disabled stage, an IK stage switched off,
## an unreachable ladder contact, and a measurement taken at the wrong moment must all be visible to the tool that is supposed to see them. They must also be read-only (the pose is identical with every diagnostic on) and
## leave nothing behind when switched off.
const SCENES := {
	"mira": "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn",
	"small": "res://art/characters/small_mira_0/runtime/small_mira_0_exploration_visual.tscn",
}
var failures := 0
var checks := 0
var _final := {}   # host -> {"hands": [wrist L, R], "feet": [ankle L, R]} read at skeleton_updated (the final pose)
var _unreachable := {}   # key -> [reachable samples, unreachable samples, worst reachable error]

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

func _spawn(stage: Node3D, key: String, armed: bool, slot: int) -> ExplorationCharacterHost:
	var host: ExplorationCharacterHost = (load(SCENES[key]) as PackedScene).instantiate()
	if not armed:
		host.rig.weapon_scene = null
	stage.add_child(host)
	host.position.x = slot * 3.0
	var rig: CharacterRig = host.rig
	rig.skeleton.skeleton_updated.connect(func() -> void:
		var sk := rig.skeleton
		var origin := sk.global_transform
		var at := func(bone: StringName) -> Vector3: return origin * sk.get_bone_global_pose(sk.find_bone(bone)).origin
		_final[host] = {"shoulders": [at.call(rig.bones.left_arm[0]), at.call(rig.bones.right_arm[0])], "elbows": [at.call(rig.bones.left_arm[1]), at.call(rig.bones.right_arm[1])],
			"hands": [origin * sk.get_bone_global_pose(sk.find_bone(rig.bones.left_arm[2])).origin, origin * sk.get_bone_global_pose(sk.find_bone(rig.bones.right_arm[2])).origin],
			"feet": [origin * sk.get_bone_global_pose(sk.find_bone(rig.bones.left_leg[2])).origin, origin * sk.get_bone_global_pose(sk.find_bone(rig.bones.right_leg[2])).origin]})
	return host

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var slot := 0
	for key in SCENES:
		for armed in [true, false]:
			var host := _spawn(stage, key, armed, slot)
			slot += 1
			await _frames(30)
			var label := "%s %s" % [key, "armed" if armed else "unarmed"]
			_inspection_checks(host.rig, label, key, armed)
			await _stage_checks(host.rig, label, armed)
			await _monitor_checks(host.rig, label)
			await _contact_checks(host, label, key, armed)
			await _read_only_and_cleanup_checks(host, label)
			host.queue_free()
			await _frames(2)
	# Small MIRA's arm cannot reach part of the ladder (issue 55): the diagnostic must show it, and MIRA, which reaches more of it, must show fewer.
	check(_unreachable.has("small armed") and int(_unreachable["small armed"][1]) > int(_unreachable["mira armed"][1]), "Small MIRA's ladder has more unreachable hand contacts than MIRA's (%s vs %s)" % [_unreachable.get("small armed"), _unreachable.get("mira armed")])
	await _trail_checks(stage)
	print("workbench_diagnostics_test: %d checks, %d failures" % [checks, failures])
	for entry in _unreachable:
		print("  %s: reachable %d, unreachable %d, worst reachable miss %.3f m" % [entry, _unreachable[entry][0], _unreachable[entry][1], _unreachable[entry][2]])
	quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------------------------------------ RigInspection

func _inspection_checks(rig: CharacterRig, label: String, key: String, armed: bool) -> void:
	var info := RigInspection.report(rig)
	check(info.usable and info.identity.armed == armed, "%s: the report says the rig is usable and %s" % [label, "armed" if armed else "unarmed"])
	check(info.identity.profile != "" and info.identity.skeleton_bones > 20, "%s: identity names the profile and the skeleton" % label)
	check(info.roles.missing_required.is_empty() and (info.roles.rows as Array).size() >= 15, "%s: every required role resolves to a bone" % label)
	var rows := {}
	for row: Dictionary in info.roles.rows:
		rows[row.role] = row
	check(rows["LeftHand"].required and rows["LeftHand"].bone == String(rig.bones.left_arm[2]) and not rows["Chest"].required, "%s: the roles table agrees with RigBones and separates required from optional" % label)
	var caps := {}
	for row: Dictionary in info.capabilities:
		caps[row.name] = row
	check(caps.has("ladder_contacts") and caps["ladder_contacts"].status == "SUPPORTED" and caps.has("weapon_ready_pose"), "%s: the capabilities say what the body supports" % label)
	check(info.measurements.leg_length != null and float(info.measurements.leg_length) > 0.3, "%s: the body proportions are measured (leg %s)" % [label, info.measurements.leg_length])
	check(info.equipment.state == ("HELD" if armed else "NONE"), "%s: the equipment state is %s" % [label, "HELD" if armed else "NONE"])
	check(RigInspection.text(info).length() > 60, "%s: the report formats as text" % label)
	# Negative controls. (1) A profile whose left hand names a bone the skeleton lacks is explained, not silently accepted. (2) The same profile, unbroken, is compatible.
	var good := RigInspection.check_profile(rig.rig_profile, rig.skeleton)
	check(good.ok, "%s: the real profile is compatible with its own skeleton" % label)
	var broken: Resource = rig.rig_profile.duplicate(true)
	broken.skeleton_map.set_skeleton_bone_name(&"LeftHand", &"NoSuchBone_probe")
	var bad := RigInspection.check_profile(broken, rig.skeleton)
	check(not bad.ok and not (bad.errors as Array).is_empty() and "LeftHand" in String(bad.text), "%s: a profile mapping LeftHand to a missing bone is reported incompatible and names the role (%s)" % [label, bad.errors.slice(0, 1)])
	var no_map: Resource = rig.rig_profile.duplicate(true)
	no_map.skeleton_map = null
	check(not RigInspection.check_profile(no_map, rig.skeleton).ok, "%s: a profile with no bone map is reported incompatible" % label)
	# (3) A stage the rig degraded is listed in the report.
	rig.bones.degraded.append("probe stage: role LeftFoot missing")
	check("probe stage: role LeftFoot missing" in RigInspection.report(rig).degraded, "%s: a degraded stage is reported" % label)
	rig.bones.degraded.pop_back()

# ------------------------------------------------------------------------------------------------ PoseStageReport

func _stage_checks(rig: CharacterRig, label: String, armed: bool) -> void:
	var rows := PoseStageReport.stages(rig)
	check(PoseStageReport.order_problems(rig).is_empty() and rows.size() == PoseOwnership.STAGE_ORDER.size(), "%s: the skeleton's modifier order agrees with PoseOwnership.STAGE_ORDER" % label)
	var in_order := true
	for index in rows.size():
		in_order = in_order and rows[index].stage == String(PoseOwnership.STAGE_ORDER[index]) and rows[index].position == index and not (rows[index].writes as Array).is_empty()
	check(in_order, "%s: every declared stage is present, in execution order, with its declared writes" % label)
	check(PoseStageReport.text(rig).contains("HandGrip") and PoseStageReport.text(rig).contains("not a measured bone change"), "%s: the text lists the stages and says declarations are not measurements" % label)
	# Why is this bone moving: the wrist is the hand grip's; the hips are shared by three stages with a declared rule; the head is only the clip's.
	var wrist := PoseStageReport.explain_bone(rig, String(rig.bones.right_arm[2]))
	var stages: Array = wrist.declared_writers.map(func(w: Dictionary) -> String: return w.stage)
	check(wrist.role == "wrist" and stages == ["HandGrip"], "%s: the wrist is declared written by HandGrip only (%s)" % [label, stages])
	var hips := PoseStageReport.explain_bone(rig, String(rig.bones.hips))
	var hip_stages: Array = hips.declared_writers.map(func(w: Dictionary) -> String: return w.stage)
	check(hip_stages.has("CoverCrouch") and hip_stages.has("Traversal") and hip_stages.has("Locomotion") and not (hips.overlaps as Array).is_empty(), "%s: the hips are shared by Locomotion, CoverCrouch and Traversal and carry an overlap rule (%s)" % [label, hip_stages])
	check(PoseStageReport.explain_bone(rig, String(rig.bones.head)).clip_only, "%s: the head is moved by no stage (only the clip)" % label)
	check(PoseStageReport.bones_of_stage(rig, &"HandGrip").has(String(rig.bones.right_arm[2])), "%s: a stage's bones include its declared role's bones" % label)
	# Runtime: nothing is traversing yet, then a ladder engages the Traversal stage.
	check(not PoseStageReport.runtime_of(rig, &"Traversal").engaged and not PoseStageReport.runtime_of(rig, &"CoverCrouch").engaged, "%s: with no traversal and no crouch those stages are not engaged" % label)
	rig.begin_traversal(&"ladder", 4.0, 1)
	rig.set_traversal_progress(2.0)
	await _frames(4)
	check(PoseStageReport.runtime_of(rig, &"Traversal").engaged and PoseStageReport.runtime_of(rig, &"TraversalLegIK").engaged, "%s: on a ladder the Traversal stage is engaged (live weight)" % label)
	rig.end_traversal()
	await _frames(3)
	check(not PoseStageReport.runtime_of(rig, &"Traversal").engaged, "%s: after the ladder it is not" % label)
	# Negative controls: a reordered skeleton and a disabled stage must show.
	var skeleton := rig.skeleton
	var locomotion := skeleton.get_node("Locomotion")
	var original_index := locomotion.get_index()
	skeleton.move_child(locomotion, skeleton.get_child_count() - 1)
	var problems := PoseStageReport.order_problems(rig)
	check(not problems.is_empty() and String(problems[0]).contains("PoseOwnership declares"), "%s: moving Locomotion to the end is reported (%s)" % [label, problems.slice(0, 1)])
	skeleton.move_child(locomotion, original_index)
	check(PoseStageReport.order_problems(rig).is_empty(), "%s: restoring the order clears the report" % label)
	var arm_stage := skeleton.get_node("WeaponArmIK") as SkeletonModifier3D
	arm_stage.active = false
	var off := PoseStageReport.runtime_of(rig, &"WeaponArmIK")
	check(not off.active and not off.engaged and String(off.detail).contains("inactive"), "%s: a disabled WeaponArmIK stage is shown inactive" % label)
	arm_stage.active = true
	check(PoseStageReport.runtime_of(rig, &"Nonexistent").detail == "absent", "%s: a stage the skeleton lacks is reported absent" % label)

# ------------------------------------------------------------------------------------------------ PresentationMonitor

func _monitor_checks(rig: CharacterRig, label: String) -> void:
	var controller := rig.animation_controller
	var before: int = controller.state_changed.get_connections().size()
	var monitor := PresentationMonitor.attach(rig)
	await _frames(2)
	check(monitor != null and monitor.is_listening() and controller.state_changed.get_connections().size() == before + 1, "%s: the monitor listens to the controller (one connection)" % label)
	controller.play(&"aim")
	await _frames(2)
	check(monitor.snapshot.state == controller.current_state and monitor.previous_state != &"" and monitor.history_text().contains("-> aim"), "%s: the snapshot's state and the transition history agree with the controller" % label)
	check(is_equal_approx(float(monitor.snapshot.speed), rig.presenter.speed) and monitor.snapshot.readiness == WeaponReadiness.Level.keys()[rig.presenter.intent().readiness], "%s: speed and readiness in the snapshot are the presenter's own" % label)
	# A hold: its start, its rank and its end come from the presenter's own report; a gesture's outcome from its handle.
	var handle := rig.presenter.begin_hold(5.0, Callable(), PresentationTypes.HOLD_INTERACTION)
	monitor.watch(handle, "probe hold")
	monitor.refresh()
	var report := rig.presenter.hold_report()
	check(monitor.snapshot.hold.active and monitor.snapshot.hold.rank == report.rank and report.rank == PresentationTypes.HOLD_INTERACTION and monitor.history_text().contains("hold started (interaction)"), "%s: a running hold is reported with its rank" % label)
	rig.presenter.begin_hold(1.0, Callable(), PresentationTypes.HOLD_REACTION)   # supersedes it
	monitor.refresh()
	check(handle.is_done() and handle.outcome == PresentationTypes.Outcome.INTERRUPTED and monitor.history_text().contains("probe hold: INTERRUPTED"), "%s: the superseded hold's outcome (INTERRUPTED) is in the history" % label)
	var refused := rig.presenter.begin_hold(1.0, Callable(), PresentationTypes.HOLD_GESTURE)
	monitor.watch(refused, "probe refused")
	check(monitor.history_text().contains("probe refused: SKIPPED"), "%s: a refused request shows SKIPPED" % label)
	rig.presenter.cancel_hold()
	monitor.refresh()
	check(not monitor.snapshot.hold.active and monitor.history_text().contains("hold ended"), "%s: the hold's end is in the history" % label)
	# The history is bounded.
	for i in 150:
		controller.play(&"rifle_idle" if i % 2 == 0 else &"aim")
	check(monitor.history.size() <= PresentationMonitor.MAX_HISTORY, "%s: the history stays bounded (%d)" % [label, monitor.history.size()])
	# Read-only: observing changed no presenter state; switching off removes the listener.
	var time_before := rig.presenter.time
	monitor.refresh()
	check(rig.presenter.time == time_before, "%s: refreshing the monitor does not advance the presenter's clock" % label)
	monitor.shutdown()
	check(not monitor.is_listening(), "%s: a monitor that was shut down reports that it no longer listens" % label)
	await _frames(2)
	check(controller.state_changed.get_connections().size() == before and not is_instance_valid(monitor), "%s: shutting the monitor down removes its listener and its node" % label)
	controller.play(&"rifle_idle")
	await _frames(2)

# ------------------------------------------------------------------------------------------------ ContactErrorDiagnostics

func _contact_checks(host: ExplorationCharacterHost, label: String, key: String, armed: bool) -> void:
	var rig: CharacterRig = host.rig
	var skeleton := rig.skeleton
	var listeners_before: int = skeleton.skeleton_updated.get_connections().size()
	var diagnostics := ContactErrorDiagnostics.attach(rig)
	check(diagnostics != null and diagnostics.latest.is_empty() and diagnostics.is_clean(), "%s: contact diagnostics start off and clean" % label)
	diagnostics.set_enabled(true)
	check(skeleton.skeleton_updated.get_connections().size() == listeners_before + 1 and diagnostics.latest.is_empty(), "%s: enabling listens to skeleton_updated and takes no sample outside it" % label)
	await _frames(3)
	check(not diagnostics.latest.is_empty() and diagnostics.latest.timing == "post-update", "%s: the first sample arrives with a skeleton update" % label)
	# 1) At rest: armed hands are the weapon grip's; unarmed hands hang by a contact claim. Either way they sit on their targets.
	var rest: Dictionary = diagnostics.latest
	var rest_owner := "weapon grip" if armed else "contact claim"
	check(rest.hands.size() == 2 and rest.hands[0].owner == rest_owner and rest.hands[1].owner == rest_owner, "%s: at rest both hands are owned by the %s (%s / %s)" % [label, rest_owner, rest.hands[0].owner, rest.hands[1].owner])
	for hand: Dictionary in rest.hands:
		check(float(hand.error) < 0.06 and not hand.unreachable, "%s: a %s hand at rest is within %.1f mm of its target and reachable" % [label, hand.name, float(hand.error) * 1000.0])
	# 2) The measurement is the FINAL pose: it equals an independent read at skeleton_updated, and a read from anywhere else in the frame is a different pose.
	await _frames(2)
	var mine: Dictionary = _final[host]
	var latest: Dictionary = diagnostics.latest
	check((latest.hands[0].wrist as Vector3).distance_to(mine.hands[0]) < 0.0001 and (latest.hands[1].wrist as Vector3).distance_to(mine.hands[1]) < 0.0001, "%s: the wrists measured equal the final pose read independently at skeleton_updated" % label)
	# 3) A ladder: the diagnostic and an independent recomputation agree on reachability, reachable wrists are on their targets, and the unreachable ones are counted.
	rig.begin_traversal(&"ladder", 4.0, 1)
	var reachable := 0
	var out_of_reach := 0
	var worst := 0.0
	var mismatch := 0
	var stale_gap := 0.0
	var h := 0.8
	while h <= 4.2:
		rig.set_traversal_progress(h)
		await _frames(2)
		var pose: LadderPose = rig.ladder.pose
		var now: Dictionary = diagnostics.latest
		var independent: Dictionary = _final[host]
		for side in 2:
			if pose.hand_weight[side] <= 0.9:
				continue
			var hand: Dictionary = now.hands[side]
			var target: Vector3 = (rig.support_ik_target if side == 0 else rig.right_hand_target).global_position
			var shoulder: Vector3 = independent.shoulders[side]
			var wrist: Vector3 = independent.hands[side]
			var elbow: Vector3 = independent.elbows[side]
			var expect_unreachable := shoulder.distance_to(target) > (shoulder.distance_to(elbow) + elbow.distance_to(wrist)) * ContactErrorDiagnostics.REACH_LIMIT_FRACTION
			if bool(hand.unreachable) != expect_unreachable:
				mismatch += 1
			if hand.unreachable:
				out_of_reach += 1
				if float(hand.reach_margin) >= 0.0:
					mismatch += 100000   # an unreachable contact must have a negative margin
			else:
				reachable += 1
				worst = maxf(worst, float(hand.error))
			if hand.owner != "contact claim":
				mismatch += 1000
		h += 0.1
	_unreachable[label] = [reachable, out_of_reach, worst]
	check(reachable > 15 and worst < 0.03 and mismatch == 0, "%s: on the ladder every reachable contact is within 3 cm (worst %.3f m), the unreachable ones are flagged exactly (%d samples) and the contacts are claims (mismatch %d)" % [label, worst, out_of_reach, mismatch])
	# A measurement taken from the frame callback instead of skeleton_updated is a different (pre-modifier) pose: that is why `measure` is only called from the callback.
	var gaps := 0.0
	for i in 20:
		await process_frame
		var elsewhere := diagnostics.measure()
		gaps = maxf(gaps, (elsewhere.hands[1].wrist as Vector3).distance_to(diagnostics.latest.hands[1].wrist))
	check(gaps > 0.01, "%s: a sample taken outside skeleton_updated differs from the final pose by up to %.3f m (the reason it is never used)" % [label, gaps])
	rig.end_traversal()
	await _frames(3)
	# 4) Negative control: with the arm IK stage off the hands do not follow their targets, and the error says so. (Armed only: the unarmed hang is not an IK target.)
	if armed:
		var good_error: float = diagnostics.latest.hands[1].error
		var arm_stage := skeleton.get_node("WeaponArmIK") as SkeletonModifier3D
		arm_stage.active = false
		rig.arm_ik.active = false
		await _frames(3)
		var broken_error: float = diagnostics.latest.hands[1].error
		check(broken_error > good_error + 0.05, "%s: with the arm IK stage off the target-to-wrist error rises from %.1f to %.1f mm" % [label, good_error * 1000.0, broken_error * 1000.0])
		arm_stage.active = true
		rig.arm_ik.active = true
		await _frames(3)
		check(float(diagnostics.latest.hands[1].error) < good_error + 0.02, "%s: and recovers when the stage is back" % label)
	# 5) Layers: each is individually selectable, and the formatted readout is stable.
	diagnostics.set_layer("errors", false)
	check(not diagnostics.layers.errors and ContactErrorDiagnostics.format_readout(diagnostics.latest).contains("target->wrist"), "%s: a layer can be switched off without touching the measurement" % label)
	diagnostics.set_layer("errors", true)
	diagnostics.start_recording()
	await _frames(5)
	check(diagnostics.stop_recording().frames >= 4 and not diagnostics.recording, "%s: recording keeps the frames and summarises them" % label)
	# 6) Switching off removes the overlay, the listener and the stored state.
	diagnostics.set_enabled(false)
	await _frames(2)
	check(diagnostics.is_clean() and skeleton.skeleton_updated.get_connections().size() == listeners_before, "%s: disabled, the overlay and the skeleton listener are gone" % label)
	diagnostics.queue_free()

# ------------------------------------------------------------------------------------------------ read-only, clean-up

func _read_only_and_cleanup_checks(host: ExplorationCharacterHost, label: String) -> void:
	var rig: CharacterRig = host.rig
	var skeleton := rig.skeleton
	rig.begin_traversal(&"ladder", 4.0, 1)
	rig.set_traversal_progress(2.0)
	await _frames(8)
	var off: Dictionary = _final[host].duplicate(true)
	var listeners_before: int = skeleton.skeleton_updated.get_connections().size()
	var suite := WorkbenchDiagnostics.new(rig)
	suite.ensure_monitor()
	suite.set_contacts(true)
	suite.set_trail(true)
	suite.highlight_bones([String(rig.bones.left_arm[2])] as Array[String])
	await _frames(8)
	var on: Dictionary = _final[host]
	var worst := 0.0
	for group in ["hands", "feet"]:
		for side in 2:
			worst = maxf(worst, (on[group][side] as Vector3).distance_to(off[group][side]))
	check(worst < 0.0005, "%s: with every diagnostic on the final pose is unchanged (worst %.6f m): they are read-only" % [label, worst])
	check(suite.contacts_on() and suite.trail_on() and is_instance_valid(suite.highlight) and suite.highlight.is_active(), "%s: the suite switched everything on" % label)
	suite.shutdown()
	await _frames(3)
	check(suite.is_clean() and skeleton.skeleton_updated.get_connections().size() == listeners_before, "%s: shutdown leaves no diagnostic node, overlay or listener (%d vs %d connections)" % [label, skeleton.skeleton_updated.get_connections().size(), listeners_before])
	rig.end_traversal()
	await _frames(3)

func _trail_checks(stage: Node3D) -> void:
	var host: ExplorationCharacterHost = (load(SCENES["mira"]) as PackedScene).instantiate()
	stage.add_child(host)
	await _frames(10)
	var trail := MotionTrail.attach(host.rig)
	trail.set_enabled(true)
	for i in 30:
		host.rig.character_root.position.x += 0.05
		await process_frame
	var summary := trail.summary()
	check(summary.points >= 25 and summary.peak_speed > 0.5, "the trail records the root's motion (%d points, peak %.1f m/s)" % [summary.points, summary.peak_speed])
	# A host with its own clock may pause automatic recording, then supply a single frame manually.
	trail.set_sampling_paused(true)
	var count_before := trail.points.size()
	var time_before: float = float(trail.points.back().t)
	await _frames(4)
	check(trail.points.size() == count_before, "a paused diagnostic trail does not sample unrelated rendered frames")
	trail.record_step(1.0 / 60.0)
	check(trail.points.size() == count_before + 1 and absf(float(trail.points.back().t) - time_before - 1.0 / 60.0) < 0.0001, "a manual step records one sample at its supplied simulation delta")
	trail.set_sampling_paused(false)
	await _frames(3)
	check(trail.points.size() > count_before + 1, "automatic sampling resumes when unpaused")
	# Off and on again: a root that moved while the trail was off must not show as a speed spike (the first sample has no step).
	trail.set_enabled(false)
	host.rig.character_root.position.x += 5.0
	await _frames(3)
	trail.set_enabled(true)
	await _frames(3)
	var worst_after := 0.0
	for index in range(summary.points + 1, trail.points.size()):
		worst_after = maxf(worst_after, float(trail.points[index].speed))
	trail.set_sampling_paused(true)
	host.rig.character_root.position.x += 5.0   # moved while paused, outside any step
	trail.set_sampling_paused(false)
	await _frames(3)
	for index in range(trail.points.size() - 2, trail.points.size()):
		worst_after = maxf(worst_after, float(trail.points[index].speed))
	check(worst_after < 1.0, "re-enabling or resuming never shows a speed spike for motion the trail did not watch (worst %.1f m/s)" % worst_after)
	trail.clear()
	check(trail.points.is_empty(), "clearing the trail empties it")
	trail.set_enabled(false)
	await _frames(2)
	check(not trail.enabled, "switching the trail off stops it")
	var lines_left := false
	for child in trail.get_children():
		lines_left = lines_left or child is MeshInstance3D
	check(not lines_left, "the trail's drawn lines are freed when it is switched off")
	host.queue_free()
