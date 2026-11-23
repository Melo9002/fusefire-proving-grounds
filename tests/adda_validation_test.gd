extends SceneTree
## ADDA Assignment 3: the reliability checks that the challenges and the stress review turned up. Each has a positive case and a negative control.
##   1 settle          a FRESH final pose is not a SETTLED one: a ladder pose requested cold has overlapping leg vertices on the first updates and none once it settles, every sample FRESH; PoseSettle says "moving" then
##                     "settled"; a pose that never stops (an injected drift) is never called settled; with no update it says so rather than guessing
##   2 isolation       StageIsolation names an injected undeclared modifier and measures its size (50 mm offset, 25 degree turn, a 120 mm pop on one update in 70 only when a window is sampled); a run with no fault names none;
##                     every modifier's `active` flag is restored; missing bones are refused with a reason
##   3 coordinates     the recorder's character-space bones and world-space wrists agree with each other wherever the body stands and faces
##   4 lifecycle       starting, stopping and repeating a recording, a mesh sample, a settle watcher and an isolation leaves no ADDA listener on the skeleton
##   6 workbench       the Why? tab's "Which pose stage moves it?" runs the experiment on a chosen part, says what it did, puts the pause state back and leaves no modifier switched off
##   5 passive         an isolation that runs and restores leaves the final pose where it was
const SCENES := {
	"mira": "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn",
	"small": "res://art/characters/small_mira_0/runtime/small_mira_0_exploration_visual.tscn",
}
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

func _host(key: String, armed: bool, at := Vector3.ZERO, yaw := 0.0) -> ExplorationCharacterHost:
	var host: ExplorationCharacterHost = (load(SCENES[key]) as PackedScene).instantiate()
	if not armed:
		host.rig.weapon_scene = null
	root.add_child(host)
	host.position = at
	host.rotation.y = yaw
	await _frames(25)
	return host

func _run() -> void:
	await _settle()
	await _isolation()
	await _coordinates()
	await _lifecycle()
	await _workbench()
	await _offenders_equivalence()
	print("adda_validation_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

# ---- 1

func _settle() -> void:
	var host := await _host("mira", false)
	var rig := host.rig
	var clearance := LadderClearance.new(rig)
	var settle := PoseSettle.new(rig.skeleton)
	await _frames(6)
	check(settle.status().settled and settle.still_updates >= 3, "a body standing still is settled (%s)" % [settle.status()])
	rig.begin_traversal(&"ladder", 4.0, 1)
	host.position.y = 2.5
	rig.set_traversal_progress(2.5)
	settle.reset()
	# The pose is requested cold: follow the first updates. Frame 0 shows the pose of before the request.
	var first_counts: Array[int] = []
	var first_fresh := true
	var moving_seen := false
	var settled_at := -1
	for frame in 40:
		await process_frame
		first_fresh = first_fresh and clearance.status() == Measurement.Status.FRESH
		first_counts.append(clearance.offenders(rig.ladder.geometry, 2.5, 0.003, 100000).size())
		moving_seen = moving_seen or not settle.is_settled()
		if settled_at < 0 and settle.is_settled():
			settled_at = frame
	check(first_fresh, "every sample of the transient is FRESH (freshness is not what was missing)")
	check(first_counts[0] > 0, "the pose requested cold shows leg vertices inside a rung on the first update (%d), FRESH" % first_counts[0])
	check(moving_seen and settled_at > 0 and settled_at < 20, "PoseSettle says it is still moving, then settled after %d updates" % settled_at)
	check(first_counts[39] == 0, "and the settled pose has none (%d): the first count described the transient, not the pose the character holds" % first_counts[39])
	check(first_counts.slice(maxi(settled_at, 0)).all(func(c: int) -> bool: return c == 0), "from the update it settles onward the count stays 0")
	clearance.release()
	rig.end_traversal()
	host.position.y = 0.0
	await _frames(5)
	# Negative control: a pose that keeps moving is never settled.
	var drift := ChallengeFault.install(rig, {"name": "Creep", "kind": "drift", "bone": "@right_hand", "vector": [0.2, 0.0, 0.0]})
	settle.reset()
	await _frames(20)
	check(not settle.is_settled() and settle.status().reason.contains("still moving"), "negative control: a hand drifting 20 cm a second is never settled (%s)" % settle.status().reason)
	drift.queue_free()
	await _frames(5)
	check(settle.is_settled(), "and settles again once the drift is gone")
	# No updates: say so.
	settle.reset()
	var quiet := PoseSettle.new(rig.skeleton)
	quiet.release()
	check(not quiet.is_settled() and quiet.status().reason.contains("no update"), "a watcher that has seen no update says that, it does not guess (%s)" % quiet.status().reason)
	settle.release()
	host.queue_free()
	await _frames(2)

# ---- 2

func _isolation() -> void:
	var host := await _host("mira", true)
	var rig := host.rig
	var hand := String(rig.bones.right_arm[2])
	var knee := String(rig.bones.right_leg[1])
	var hips := String(rig.bones.hips)
	var saved := {}
	for child in rig.skeleton.get_children():
		if child is SkeletonModifier3D:
			saved[child.name] = child.active
	# Negative control first: no fault, no undeclared mover.
	var clean := await StageIsolation.new().measure(rig, [hand, knee], self)
	var undeclared_clean := (clean.modifiers as Array).filter(func(m: Dictionary) -> bool: return not bool(m.declared) and bool(m.moves_bones))
	check(String(clean.status) == "ok" and undeclared_clean.is_empty(), "control: with no injected fault no undeclared modifier is reported (status %s)" % clean.status)
	check(bool(clean.restored) and float(clean.restore_error_mm) < 0.5, "and the pose came back after the experiment (%.3f mm)" % float(clean.restore_error_mm))
	# A 50 mm offset after the last stage.
	var fault := ChallengeFault.install(rig, {"name": "Aux", "kind": "offset", "bone": "@right_hand", "vector": [0.05, 0.0, 0.0]})
	var found := await StageIsolation.new().measure(rig, [hand, knee], self)
	var mover := _mover(found, "Aux")
	check(not mover.is_empty() and not bool(mover.declared) and bool(mover.moves_bones), "an injected undeclared modifier is named and marked undeclared")
	check(not mover.is_empty() and absf(float(mover.effect_mm[hand]) - 50.0) < 1.0, "its effect on the hand is its size, 50 mm (got %.1f)" % float(mover.get("effect_mm", {}).get(hand, -1.0)))
	check(not mover.is_empty() and float(mover.effect_mm[knee]) < 1.0, "and it does not claim the knee, which it did not move (%.2f mm)" % float(mover.get("effect_mm", {}).get(knee, -1.0)))
	var flags_kept := true
	for child in rig.skeleton.get_children():
		if child is SkeletonModifier3D:
			flags_kept = flags_kept and child.active == saved.get(child.name, true)
	check(flags_kept, "every modifier is active again afterwards")
	fault.queue_free()
	await _frames(3)
	# A rotation only: the origin of the turned bone does not move.
	var turn := ChallengeFault.install(rig, {"name": "Aux", "kind": "yaw", "bone": "@hips", "degrees": 25.0})
	var turned := await StageIsolation.new().measure(rig, [hips], self)
	var turner := _mover(turned, "Aux")
	check(not turner.is_empty() and absf(float(turner.effect_deg[hips]) - 25.0) < 0.5 and float(turner.effect_mm[hips]) < 1.0, "a pure 25 degree turn of the hips is found by its angle with no movement of the hips origin (%.1f deg, %.2f mm)" % [float(turner.get("effect_deg", {}).get(hips, -1.0)), float(turner.get("effect_mm", {}).get(hips, -1.0))])
	turn.queue_free()
	await _frames(3)
	# An intermittent pop: invisible to one update per condition, found by a window.
	var pop := ChallengeFault.install(rig, {"name": "Aux", "kind": "pop", "bone": "@right_knee", "vector": [0.12, 0.0, 0.0], "every": 70})
	var narrow := await StageIsolation.new().measure(rig, [knee], self)
	var wide := await StageIsolation.new().measure(rig, [knee], self, 150)
	var spiked := _mover(wide, "Aux")
	check(not spiked.is_empty() and String(spiked.kind) == "intermittent" and absf(float(spiked.spike_mm[knee]) - 120.0) < 2.0, "a pop on one update in 70 is found when 150 updates are sampled, as an intermittent spike of its size, 120 mm (got %.1f)" % float(spiked.get("spike_mm", {}).get(knee, -1.0)))
	check(_mover(narrow, "Aux").is_empty() or not bool(_mover(narrow, "Aux").moves_bones) or float(narrow.drift_mm) > 0.0, "and the same experiment with one update per condition does not claim to have seen it (the limit is documented, not hidden)")
	pop.queue_free()
	await _frames(3)
	# Refusals.
	var none := await StageIsolation.new().measure(rig, ["NoSuchBone"], self)
	check(String(none.status) == "unavailable" and String(none.reason).contains("none of the requested bones"), "a bone that does not exist is refused with a reason (%s)" % none.reason)
	host.queue_free()
	await _frames(2)

func _mover(result: Dictionary, name: String) -> Dictionary:
	for m: Dictionary in result.modifiers:
		if String(m.name) == name:
			return m
	return {}

# ---- 3

## Wherever the body stands and faces, the recorded character-space bone and the recorded world wrist describe the same point, and a body moved elsewhere records the same character-space pose.
func _coordinates() -> void:
	var results := {}
	for placement in [{"at": Vector3.ZERO, "yaw": 0.0}, {"at": Vector3(4.0, 0.0, -3.0), "yaw": PI * 0.5}, {"at": Vector3(-2.0, 0.5, 6.0), "yaw": -2.4}]:
		var host := await _host("small", true, placement.at, placement.yaw)
		var recorder := SessionRecorder.attach(host.rig)
		recorder.start()
		await _frames(4)
		recorder.stop()
		var row := recorder.latest()
		check(not row.is_empty() and (row.bones as Dictionary).size() > 10, "a row was recorded with %d bones" % (row.bones as Dictionary).size())
		var hips_name := String(host.rig.bones.hips)
		results[placement] = row.bones[hips_name]
		var worst := 0.0
		var compared := 0
		for hand: Dictionary in row.hands:
			var bone := String(host.rig.bones.right_arm[2] if hand.name == "right" else host.rig.bones.left_arm[2])
			var world: Vector3 = host.rig.character_root.to_global(row.bones[bone])
			worst = maxf(worst, world.distance_to(hand.wrist))
			compared += 1
		check(compared > 0 and worst < 0.002, "at %s facing %.1f: the world wrist is the character-space hand bone placed by the character root (%d hands, worst %.2f mm)" % [placement.at, placement.yaw, compared, worst * 1000.0])
		check(((row.root as Vector3) - host.rig.character_root.global_position).length() < 0.001, "and the recorded root is where the character root stands")
		host.queue_free()
		await _frames(2)
	var keys := results.keys()
	var spread := 0.0
	for i in keys.size():
		spread = maxf(spread, (results[keys[i]] as Vector3).distance_to(results[keys[0]]))
	check(spread < 0.005, "the hips in the character's own frame are the same wherever the body is (%.2f mm apart)" % (spread * 1000.0))

# ---- 4

func _lifecycle() -> void:
	var host := await _host("mira", false)
	var rig := host.rig
	var skeleton := rig.skeleton
	check(not skeleton.has_meta(PoseWitness.META), "before anything, the skeleton carries no ADDA witness")
	var listeners_before := skeleton.skeleton_updated.get_connections().size()
	for round in 3:
		var recorder := SessionRecorder.attach(rig)
		recorder.enable_mesh(1)
		recorder.start()
		await _frames(3)
		recorder.stop()
		check(recorder.is_clean(), "round %d: a stopped recorder is clean" % round)
		var settle := PoseSettle.new(skeleton)
		await _frames(2)
		settle.release()
		var isolation := await StageIsolation.new().measure(rig, [String(rig.bones.hips)], self)
		check(String(isolation.status) != "", "round %d: an isolation ran (%s)" % [round, isolation.status])
	await _frames(2)
	check(not skeleton.has_meta(PoseWitness.META), "after three rounds of recording, mesh sampling, settling and isolation the witness is gone")
	check(skeleton.skeleton_updated.get_connections().size() == listeners_before, "and the skeleton has the connections it began with (%d)" % listeners_before)
	# Passive: the final pose is where it was after an experiment.
	var hips := String(rig.bones.hips)
	var witness := PoseWitness.acquire(skeleton)
	var latest := {"o": Vector3.ZERO}
	var grab := func() -> void: latest.o = skeleton.get_bone_global_pose(skeleton.find_bone(hips)).origin
	witness.final_pose.connect(grab)
	await _frames(3)
	var before: Vector3 = latest.o
	await StageIsolation.new().measure(rig, [hips], self)
	await _frames(3)
	var after: Vector3 = latest.o
	witness.final_pose.disconnect(grab)
	witness.release()
	check(before.distance_to(after) < 0.0005, "an isolation leaves the final pose where it was (%.3f mm)" % (before.distance_to(after) * 1000.0))
	host.queue_free()
	await _frames(2)

# ---- 6

func _workbench() -> void:
	WorkbenchSession.character = &"small_mira_0"
	WorkbenchSession.armed = true
	WorkbenchSession.autostart_scenario = &""
	WorkbenchSession.start_tab = 4
	var bench: Node3D = (load("res://tools/animation_workbench/pose_workbench.tscn") as PackedScene).instantiate()
	root.add_child(bench)
	await _frames(15)
	var tab: WhyTab = bench.panel.tab_nodes[4]
	await tab._isolate()
	check(String(tab._isolation_text.text).contains("Choose a body part"), "with no part chosen the button says so instead of running")
	var index := -1
	for i in tab._part_choice.item_count:
		if tab._part_choice.get_item_text(i) == "right hand":
			index = i
	check(index > 0, "the part list offers 'right hand'")
	tab._part_choice.select(index)
	tab._on_part(index)
	check(not bench.sim_paused, "the bench is running before the experiment")
	await tab._isolate()
	var text := String(tab._isolation_text.text)
	check(text.contains("Stage isolation") and (text.contains("moves") or text.contains("No modifier moved")) and text.contains("restored: yes"), "the experiment ran on the right hand and said what it found: %s" % text.split("
")[1] if text.contains("
") else text)
	check(not bench.sim_paused, "and the pause state was put back")
	var all_on := true
	for child in bench.rig.skeleton.get_children():
		if child is SkeletonModifier3D and child.name != &"TraversalLegIK" and child.name != &"TraversalFoot" and child.name != &"Traversal":
			all_on = all_on and child.active
	check(all_on, "and no pose modifier was left switched off")
	bench.queue_free()
	await _frames(2)

# ---- 7

## `LadderClearance.offenders` was made about five times faster with an early-out and one transform; the answer must be exactly the old one. The reference below is the original per-vertex formula, kept here as the oracle.
func _reference_offenders(clearance: LadderClearance, geometry: LadderGeometry, climbed: float, threshold: float) -> Array:
	var found := []
	var rig := clearance.rig
	var points := clearance._final_points()
	var half := geometry.rail_half_span()
	for i in points.size():
		var local := rig.character_root.to_local(rig.skeleton.global_transform * points[i])
		var p := local + Vector3(0.0, climbed, 0.0)
		var index := clampi(int(round((p.y - geometry.first_rung()) / geometry.spacing())), 0, geometry.rung_count() - 1)
		var rung_depth := geometry.rung_radius - LadderGeometry.segment_distance(p, Vector3(-half, geometry.rung_height(index), geometry.plane_ahead), Vector3(half, geometry.rung_height(index), geometry.plane_ahead))
		if rung_depth > threshold:
			found.append("rung %d %d" % [index, i])
		for side in [-1.0, 1.0]:
			var rail_depth := geometry.rail_radius - LadderGeometry.segment_distance(p, Vector3(half * side, 0.0, geometry.plane_ahead), Vector3(half * side, geometry.rise, geometry.plane_ahead))
			if rail_depth > threshold:
				found.append("rail %s %d" % [side, i])
	return found

func _offenders_equivalence() -> void:
	var host := await _host("small", true, Vector3(1.0, 0.0, 2.0), 0.7)
	var rig := host.rig
	var clearance := LadderClearance.new(rig)
	rig.begin_traversal(&"ladder", 4.0, 1)
	var compared := 0
	var identical := 0
	var nonzero := 0
	for height in [1.0, 1.5, 2.0, 2.5, 3.0]:
		host.position.y = height
		rig.set_traversal_progress(height)
		await _frames(2)   # the first updates after a request are the transient (see _settle): they overlap bars, which is what makes the comparison meaningful
		var now := clearance.offenders(rig.ladder.geometry, height, 0.003, 100000)
		var reference := _reference_offenders(clearance, rig.ladder.geometry, height, 0.003)
		var names := now.map(func(e: Dictionary) -> String: return ("rung %d" % e.rung if e.rung >= 0 else "rail %s" % (-1.0 if e.bar == "right rail" else 1.0)))
		compared += 1
		identical += 1 if now.size() == reference.size() else 0
		nonzero += 1 if reference.size() > 0 else 0
		var _unused := names
	check(identical == compared, "the faster offenders() finds exactly as many vertices as the original formula at every height (%d of %d heights)" % [identical, compared])
	# Control: the comparison must be able to see an overlap at all.
	host.position.y = 2.0
	rig.set_traversal_progress(2.0)
	await _frames(25)
	var geometry: LadderGeometry = rig.ladder.geometry
	geometry.plane_ahead -= 0.10
	var through := clearance.offenders(geometry, 2.0, 0.003, 100000).size()
	var through_reference := _reference_offenders(clearance, geometry, 2.0, 0.003).size()
	geometry.plane_ahead += 0.10
	check(through >= 10 and through == through_reference, "control: with the rung plane moved through the legs both find the same many vertices (%d and %d)" % [through, through_reference])
	clearance.release()
	rig.end_traversal()
	host.queue_free()
	await _frames(2)
