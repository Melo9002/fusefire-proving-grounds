extends SceneTree
## ADDA measurement integrity: the instruments are checked against deliberate faults (negative controls) and against the normal case. A control injects a fault in the TEST (a moved bar, a dropped listener, a
## disabled modifier, a displaced target); nothing here changes production code or data, and every control is undone before the next.
##   1 stale pose        a sample that is not from the skeleton's current update is reported STALE with a reason, never returned as a number
##   2 outside the signal a sample taken outside skeleton_updated is reported STALE (that pose is the base pose, measured below to differ from the final one)
##   3 rung in a leg     a ladder bar moved through the legs is seen by the sampled-vertex measurement, and the clean ladder is not
##   4 foot misaligned   a foot plan displaced from the ankle shows as a TARGET_ERROR in millimetres, and the normal climb shows millimetres
##   5 unreachable hand  a contact target beyond the arm is REACH_FEASIBILITY false (and a reachable one true)
##   6 unsupported / missing  no sample, no surface and no diagnostic say UNAVAILABLE, never zero
##   7 kinds never stand for each other (a vertex count does not establish a mesh intersection)
const SCENE := "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn"
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
	var host: ExplorationCharacterHost = (load(SCENE) as PackedScene).instantiate()
	host.rig.weapon_scene = null
	root.add_child(host)
	await _frames(25)
	var rig := host.rig
	var skeleton := rig.skeleton
	var listeners_before := skeleton.skeleton_updated.get_connections().size()
	await _stale_and_outside(host)
	await _rung_in_leg(host)
	await _foot_and_hand(host)
	_envelope_rules(rig)
	check(skeleton.skeleton_updated.get_connections().size() == listeners_before, "every control released its witness: the skeleton carries the listeners it started with (%d, was %d)" % [skeleton.skeleton_updated.get_connections().size(), listeners_before])
	print("adda_measurement_integrity_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

## 1 and 2: stale, and outside the signal.
func _stale_and_outside(host: ExplorationCharacterHost) -> void:
	var rig := host.rig
	var geometry := LadderGeometry.for_rise(4.0)
	rig.begin_traversal(&"ladder", 4.0, 1)
	host.position.y = 1.5
	rig.set_traversal_progress(1.5)
	var clearance := LadderClearance.new(rig)
	var before := clearance.vertex_evidence(geometry, 1.5)
	check(before.status == Measurement.Status.UNAVAILABLE and before.value == null, "no sample yet is UNAVAILABLE with no value (not zero): %s" % before.text())
	await _frames(3)
	var normal := clearance.vertex_evidence(geometry, 1.5)
	check(normal.status == Measurement.Status.FRESH and normal.usable() and normal.pose == Measurement.Pose.FINAL, "normal case: a sample from this update is FRESH and from the final pose: %s" % normal.text())
	check(normal.character.contains("mira") or normal.character.length() > 5, "the measurement carries a character identity (%s) and a frame (%d)" % [normal.character, normal.frame])
	var d := normal.to_dict()
	check(d.has("establishes") and d.has("does_not_establish") and d.kind == "VERTEX_OVERLAP", "the exported record says what the measurement establishes and does not")
	# 1) STALE: stop sampling (the fault), let the pose move on.
	var witness := PoseWitness.acquire(rig.skeleton)   # held first, so releasing the tool does not end the witness
	clearance.release()
	rig.set_traversal_progress(1.9)
	host.position.y = 1.9
	await _frames(3)
	check(witness.updates > clearance.stamp.update, "control 1 set-up: the skeleton updated again (%d after %d)" % [witness.updates, clearance.stamp.update])
	var stale := LadderClearance.new(rig)   # a second tool that has not sampled yet
	stale.stamp = clearance.stamp            # carrying the old tool's last stamp
	stale.joints = clearance.joints
	stale.release()
	var old := stale.vertex_evidence(geometry, 1.9)
	check(old.status == Measurement.Status.STALE and old.value == null and old.reason.contains("update"), "control 1: a sample from an earlier update is STALE with a reason and no number: %s" % old.text())
	# 2) Outside the signal: sample() called from the test, not from final_pose.
	var late := LadderClearance.new(rig)
	await _frames(2)
	late.release()   # stop its own sampling, keep the last (fresh) stamp
	late.sample()    # now sample from here, outside the signal
	var outside := late.vertex_evidence(geometry, 1.9)
	check(outside.status == Measurement.Status.STALE and outside.reason.contains("outside skeleton_updated"), "control 2: a sample taken outside skeleton_updated is STALE and says why: %s" % outside.text())
	# The reason it matters, measured: the pose read outside the signal differs from the final one while the body is moving.
	var probe := _Probe.new()
	var bone := skeleton_wrist(rig)
	var final_read := Vector3.ZERO
	var outside_read := Vector3.ZERO
	var count := 0
	var worst := 0.0
	var probe_callable := probe.on_update.bind(rig.skeleton, bone)
	rig.skeleton.skeleton_updated.connect(probe_callable)
	for i in 12:
		host.position.y = 1.9 + 0.03 * i
		rig.set_traversal_progress(1.9 + 0.03 * i)
		await process_frame
		var outside_pose: Vector3 = rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(bone).origin
		worst = maxf(worst, outside_pose.distance_to(probe.final_pose))
	print("  base-vs-final wrist difference while climbing: worst %.3f m" % worst)
	check(worst > 0.02, "why the contract exists: a bone read outside skeleton_updated differs from the final pose by %.3f m while climbing (more than 2 cm)" % worst)
	rig.skeleton.skeleton_updated.disconnect(probe_callable)
	witness.release()
	rig.end_traversal()
	host.position.y = 0.0
	await _frames(2)

func skeleton_wrist(rig: CharacterRig) -> int:
	return rig.skeleton.find_bone(rig.bones.right_arm[2])

class _Probe extends RefCounted:
	var final_pose := Vector3.ZERO
	func on_update(skeleton: Skeleton3D, bone: int) -> void:
		final_pose = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin

## 3: a bar through the legs.
func _rung_in_leg(host: ExplorationCharacterHost) -> void:
	var rig := host.rig
	var geometry := LadderGeometry.for_rise(4.0)
	rig.begin_traversal(&"ladder", 4.0, 1)
	var clearance := LadderClearance.new(rig)
	host.position.y = 2.0
	rig.set_traversal_progress(2.0)
	await _frames(3)
	var clean := clearance.vertex_evidence(geometry, 2.0)
	geometry.plane_ahead -= 0.10   # the fault: the whole rung plane 10 cm toward the body, through the legs
	var through := clearance.vertex_evidence(geometry, 2.0)
	geometry.plane_ahead += 0.10
	check(clean.usable() and through.usable() and int(through.value) > int(clean.value) + 20, "control 3: a rung through the legs reads %s vertices inside bars against %s on the clean ladder" % [str(through.value), str(clean.value)])
	check(not through.establishes(Measurement.Kind.MESH_INTERSECTION) and through.establishes(Measurement.Kind.VERTEX_OVERLAP), "7: that count establishes a vertex overlap and NOT a mesh intersection")
	var intersection := clearance.intersection_evidence()
	check(intersection.status == Measurement.Status.UNSUPPORTED and not intersection.usable() and intersection.kind == Measurement.Kind.MESH_INTERSECTION, "a full mesh intersection is asked for and answered UNSUPPORTED (a vertex count never stands in for it)")
	clearance.release()
	rig.end_traversal()
	host.position.y = 0.0
	await _frames(2)

## 4 and 5: a displaced foot plan, an unreachable hand target.
func _foot_and_hand(host: ExplorationCharacterHost) -> void:
	var rig := host.rig
	var contacts := ContactErrorDiagnostics.attach(rig)
	check(contacts.evidence()[0].status == Measurement.Status.UNAVAILABLE, "6: a diagnostic that has taken no sample reports UNAVAILABLE")
	contacts.set_enabled(true)
	rig.begin_traversal(&"ladder", 4.0, 1)
	var worst_foot := 0.0
	var h := 1.0
	var fresh := 0
	var total := 0
	while h < 2.5:
		host.position.y = h
		rig.set_traversal_progress(h)
		await _frames(2)
		for m in contacts.evidence():
			total += 1
			fresh += 1 if m.status == Measurement.Status.FRESH else 0
			if m.kind == Measurement.Kind.TARGET_ERROR and m.name.contains("foot") and m.usable():
				worst_foot = maxf(worst_foot, float(m.value))
		h += 0.1
	check(fresh == total, "normal case: every contact measurement taken inside the signal is FRESH (%d of %d)" % [fresh, total])
	check(worst_foot < 15.0, "normal case: the planted foot error on the climb is %.1f mm (the plan is followed within 15 mm)" % worst_foot)
	# 4) The fault: the foot plan the diagnostic compares with is displaced 6 cm for the duration of one sample (set and restored inside the same update; the rig's own plan and what the modifiers
	# consumed are untouched), as if the planner and the leg disagreed.
	var displace := func() -> void:
		var pose: LadderPose = rig.ladder.pose
		var saved: Vector3 = pose.feet[0]
		pose.feet[0] = saved + Vector3(0.06, 0.0, 0.0)
		contacts._on_skeleton_updated()
		pose.feet[0] = saved
	contacts.witness.final_pose.connect(displace)
	await _frames(3)
	var broken := 0.0
	for m in contacts.evidence():
		if m.kind == Measurement.Kind.TARGET_ERROR and m.name.contains("foot") and m.usable():
			broken = maxf(broken, float(m.value))
	contacts.witness.final_pose.disconnect(displace)
	check(broken > 40.0 and broken > worst_foot + 30.0, "control 4: a foot plan displaced 6 cm reads %.0f mm of foot error against %.1f mm normally" % [broken, worst_foot])
	await _frames(3)
	# 5) The hand target 2 m beyond the shoulder for one sample (set and restored inside the update): REACH_FEASIBILITY must be false; the normal ladder hand was feasible.
	var target: Node3D = rig.right_hand_target
	var normal_reach := _reach(contacts, "right")
	check(normal_reach != null and normal_reach.usable() and normal_reach.value == true, "normal case: the right hand's target is within the arm on the ladder")
	var far_hand := func() -> void:
		var saved := target.global_position
		target.global_position = rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(rig.bones.right_arm[0])).origin + Vector3(0.0, 0.0, 2.0)
		contacts._on_skeleton_updated()
		target.global_position = saved
	contacts.witness.final_pose.connect(far_hand)
	await _frames(3)
	var far_reach := _reach(contacts, "right")
	contacts.witness.final_pose.disconnect(far_hand)
	check(far_reach != null and far_reach.usable() and far_reach.value == false, "control 5: a target 2 m from the shoulder is reported infeasible")
	rig.end_traversal()
	host.position.y = 0.0
	await _frames(3)
	contacts.set_enabled(false)
	check(contacts.evidence()[0].status == Measurement.Status.UNAVAILABLE, "6: a switched-off diagnostic reports UNAVAILABLE, not its last numbers")
	contacts.queue_free()
	await _frames(2)

func _reach(contacts: ContactErrorDiagnostics, side: String) -> Measurement:
	for m in contacts.evidence():
		if m.kind == Measurement.Kind.REACH_FEASIBILITY and m.name.to_lower().begins_with(side):
			return m
	return null

## 6 and 7 without a scene: an UNSUPPORTED/UNAVAILABLE envelope never carries a number, kinds are distinct.
func _envelope_rules(rig: CharacterRig) -> void:
	var gone := Measurement.missing(Measurement.Kind.MESH_INTERSECTION, "triangle intersection", Measurement.Status.UNSUPPORTED, "not measured by ADDA yet")
	check(not gone.usable() and gone.value == null and gone.to_dict().status == "UNSUPPORTED", "6: UNSUPPORTED carries no value")
	var kinds_distinct := true
	for a in Measurement.Kind.values():
		var m := Measurement.make(a, "x", 1, "u")
		m.status = Measurement.Status.FRESH
		for b in Measurement.Kind.values():
			if m.establishes(b) != (a == b):
				kinds_distinct = false
	check(kinds_distinct, "7: a measurement of one kind establishes only that kind (all %d x %d pairs)" % [Measurement.Kind.size(), Measurement.Kind.size()])
	check(Measurement.identity_of(rig).length() > 0, "identity text for the rig is produced")
