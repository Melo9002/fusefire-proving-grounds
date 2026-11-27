extends SceneTree
## The loaded ladder presentation (animation assignment), in the real Workbench in paused fixed steps, for every carrier/passenger pairing and both directions, measured from the FINAL pose (see
## tests/support/loaded_ladder_measure.gd for exactly what that does and does not establish: contact-target errors, continuity and clearance of limb SEGMENTS; not mesh penetration, not physical support).
## Sections: the matrix; negative controls (a bad fit, the tactical fallback, the coupled-identity bug); interruptions and teardown; determinism and frame rate.
const Measure := preload("res://tests/support/loaded_ladder_measure.gd")
const IDS: Array[StringName] = [&"mira_0", &"small_mira_0"]

## Thresholds, set from the measured behaviour (docs/claude/carry-ladder-report) with margin. Distances in centimetres or metres as named.
const SUPPORT_HAND_MEAN_CM := 2.0
const SUPPORT_HAND_MAX_CM := 4.0
const FREE_HAND_MEAN_CM := 2.0
const FREE_HAND_MAX_CM := 12.0
const FEET_MAX_CM := 5.0
const ATTACHMENT_STEP_CM := 4.0
const GROUND_CLEARANCE_M := 0.10
const DECK_CLEARANCE_M := 0.05
## A limb segment is given a 5 cm radius here, deliberately generous; a toe tip grazing a rail at that radius reads as a few millimetres negative.
const LADDER_CLEARANCE_M := -0.02

var failures := 0
var checks := 0
var _results := {}
var _previous_relative := Vector3.INF
var _worst_relative := 0.0


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


## Runs `count` simulation steps on a kept bench (it is paused: only a step advances the presentation).
func _step(bench: Node3D, count: int) -> void:
	bench.step_seconds = 1.0 / 30.0
	for i in count:
		bench.step_sim()
		await process_frame


func _run() -> void:
	await _matrix()
	await _controls()
	await _interruptions()
	await _determinism()
	print("loaded_ladder_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)


## The thresholds a pairing has to meet. Returns the list of what failed (empty when it passes).
func _violations(entry: Dictionary) -> Array[String]:
	var bad: Array[String] = []
	if not bool(entry.identity_ok): bad.append("identity")
	if bool(entry.moved_during_transfer): bad.append("the body moved before the transfer finished")
	if float(entry.transfer_seconds) < 0.85 or float(entry.transfer_seconds) > 1.05: bad.append("transfer %.2f s" % entry.transfer_seconds)
	if float(entry.support_hand_mean_cm) > SUPPORT_HAND_MEAN_CM or float(entry.support_hand_max_cm) > SUPPORT_HAND_MAX_CM: bad.append("support hand %.1f/%.1f cm" % [entry.support_hand_mean_cm, entry.support_hand_max_cm])
	if float(entry.free_hand_mean_cm) > FREE_HAND_MEAN_CM or float(entry.free_hand_max_cm) > FREE_HAND_MAX_CM: bad.append("free hand %.1f/%.1f cm" % [entry.free_hand_mean_cm, entry.free_hand_max_cm])
	if float(entry.feet_max_cm) > FEET_MAX_CM: bad.append("feet %.1f cm" % entry.feet_max_cm)
	if float(entry.relative_step_max_cm) > ATTACHMENT_STEP_CM: bad.append("attachment step %.1f cm" % entry.relative_step_max_cm)
	if float(entry.lowest_m) < GROUND_CLEARANCE_M: bad.append("ground clearance %.2f m" % entry.lowest_m)
	if float(entry.deck_clearance_min_m) < DECK_CLEARANCE_M: bad.append("deck clearance %.2f m" % entry.deck_clearance_min_m)
	if float(entry.ladder_clearance_min_m) < LADDER_CLEARANCE_M: bad.append("ladder clearance %.3f m (%s)" % [entry.ladder_clearance_min_m, entry.ladder_clearance_bone])
	if not bool(entry.restored): bad.append("the ordinary carry was not restored")
	return bad


func _matrix() -> void:
	for carrier in IDS:
		var unloaded: Dictionary = await Measure.new().run(self, carrier, &"none", 1)
		_results["unloaded_%s" % carrier] = unloaded
		for passenger in IDS:
			for direction in [1, -1]:
				var label := "%s carries %s, %s" % [carrier, passenger, "up" if direction > 0 else "down"]
				var entry: Dictionary = await Measure.new().run(self, carrier, passenger, direction)
				_results[label] = entry
				var bad := _violations(entry)
				check(bad.is_empty(), "%s: %s" % [label, "; ".join(bad)])
				check(float(entry.feet_max_cm) <= float(unloaded.feet_max_cm) + 2.5, "%s: the carrier's feet are as true to the rungs as unloaded (%.1f against %.1f cm)" % [label, entry.feet_max_cm, unloaded.feet_max_cm])
				print("  %s: transfer %.2fs, support %.1f/%.1f cm, free %.1f/%.1f cm, feet %.1f cm, attachment step %.1f cm (the carrier's own chest step %.1f cm, unloaded %.1f), ground %.2f deck %.2f m, ladder clearance %.3f m" % [
					label, entry.transfer_seconds, entry.support_hand_mean_cm, entry.support_hand_max_cm, entry.free_hand_mean_cm, entry.free_hand_max_cm, entry.feet_max_cm, entry.relative_step_max_cm,
					entry.chest_step_max_cm, unloaded.chest_step_max_cm, entry.lowest_m, entry.deck_clearance_min_m, entry.ladder_clearance_min_m])


func _controls() -> void:
	# A bad fit is caught: the same pairing with the fit switched off (the climbing carry as authored for a body of the carrier's own size) must break a threshold, or the thresholds prove nothing.
	var unfitted := func(rig: CharacterRig) -> void:
		PassengerFit._cache["ladder|small_mira_0|mira_0"] = {"changed": false, "pose": {}, "slide": Vector3.ZERO, "fractions": {&"wrist": 0.85, &"thigh": 0.9}, "lowest": 0.0, "reach": 0.0, "cost": 0.0}
	var control: Dictionary = await Measure.new().run(self, &"small_mira_0", &"mira_0", 1, {"tune": unfitted})
	var bad := _violations(control)
	check(not bad.is_empty(), "Negative control: without the fit, Small MIRA carrying a regular MIRA breaks a threshold (%s)" % "; ".join(bad))
	var fitted_entry: Dictionary = _results["small_mira_0 carries mira_0, up"]
	check(float(control.support_hand_mean_cm) > float(fitted_entry.support_hand_mean_cm) + 1.0 or float(control.lowest_m) < float(fitted_entry.lowest_m) - 0.05, "Negative control: the fit is what improves the supporting hand or the clearance (%.1f cm and %.2f m unfitted, %.1f cm and %.2f m fitted)" % [control.support_hand_mean_cm, control.lowest_m, fitted_entry.support_hand_mean_cm, fitted_entry.lowest_m])

	# The tactical path (no opt-in) keeps its loaded fallback exactly: no loaded presentation, the carry keeps both hands, the weapon stays slung.
	var measure := Measure.new()
	await measure.run(self, &"mira_0", &"mira_0", 1, {"keep": true, "stop_early": func(_rig, _bench, time: float) -> bool: return time > 0.1})
	var bench: Node3D = measure.bench()
	var rig: CharacterRig = bench.rig
	bench.end_ladder_demo()
	await _step(bench, 60)
	check(rig.loaded_ladder == null and rig.ladder == null, "A climb that did not opt in leaves no loaded presentation")
	rig.begin_traversal(&"ladder", 3.0, 1)
	rig.set_traversal_progress(1.0)
	await _step(bench, 20)
	check(rig.loaded_ladder == null and rig.ladder != null and rig.loaded_ladder_ready(), "Without the opt-in a carrier on a ladder has no loaded transfer (the tactical fallback)")
	check(rig.carry_contact_report.size() == 2 and not (rig.carry_contact_report[0] as Dictionary).is_empty() and not (rig.carry_contact_report[1] as Dictionary).is_empty(), "and both hands keep their carry contacts, as before")
	check(rig.carry_passenger.ladder_blend == 0.0 and rig.carry_passenger.landing_tuck == 0.0, "and the passenger stays across the shoulders")
	rig.end_traversal()
	bench.queue_free()
	await _frames(2)

	# A same-size passenger is still the authored carry (no fit), and the carrier's own kind is what a rig carries when nobody says otherwise.
	var plain := Measure.new()
	await plain.run(self, &"mira_0", &"mira_0", 1, {"keep": true, "stop_early": func(_rig, _bench, time: float) -> bool: return time > 0.1})
	check(plain.bench().rig.carry_fit.get("fitted", true) == false, "A body carrying its own kind keeps the authored ordinary carry (no fit)")
	plain.bench().queue_free()
	await _frames(2)

	# The coupled-identity bug is detectable: a passenger built from the carrier's own description is the carrier's size.
	var scale_of := func(carrier: StringName, definition_of: StringName, coupled: bool) -> float:
		WorkbenchSession.character = carrier
		WorkbenchSession.passenger = &""
		WorkbenchSession.start_tab = -1
		var probe: Node3D = (load("res://tools/animation_workbench/pose_workbench.tscn") as PackedScene).instantiate()
		root.add_child(probe)
		await _frames(10)
		var probe_rig: CharacterRig = probe.rig
		probe_rig.passenger_definition = PassengerDefinition.from_rig(probe_rig) if coupled else PassengerDefinition.for_character(definition_of)
		probe_rig.begin_carry()
		await _frames(3)
		var model_scale: float = probe_rig.carry_passenger.find_child("PassengerModel", true, false).scale.x
		probe.queue_free()
		await process_frame
		return model_scale
	var coupled_scale: float = await scale_of.call(&"small_mira_0", &"mira_0", true)
	var chosen_scale: float = await scale_of.call(&"small_mira_0", &"mira_0", false)
	check(coupled_scale < chosen_scale - 0.1, "Negative control: a passenger derived from its carrier is the carrier's size (%.2f), the chosen one keeps its own (%.2f)" % [coupled_scale, chosen_scale])


## A started climb, stopped part of the way, then cut short in each way a host can.
func _interruptions() -> void:
	var halfway := func(_rig, bench: Node3D, _time: float) -> bool: return float(bench.ladder_demo.get("climbed", 0.0)) > 1.4
	# The ladder ends mid-climb: the passenger settles back to the ordinary carry and both hands return to it.
	var a := Measure.new()
	await a.run(self, &"small_mira_0", &"mira_0", 1, {"keep": true, "stop_early": halfway})
	var rig: CharacterRig = a.bench().rig
	check(rig.loaded_ladder != null and rig.loaded_ladder.blend > 0.999, "Setup: stopped halfway up in the climbing carry")
	a.bench().end_ladder_demo()
	await _step(a.bench(), 120)
	check(rig.loaded_ladder == null and rig.carry_passenger.ladder_blend == 0.0 and rig.carry_passenger.landing_tuck == 0.0, "A climb ended halfway up gives the passenger back its ordinary carry")
	check(rig.carry_contact_report.size() == 2 and not (rig.carry_contact_report[0] as Dictionary).is_empty() and not (rig.carry_contact_report[1] as Dictionary).is_empty(), "and both hands are on the passenger again")
	a.bench().queue_free()
	await _frames(2)

	# The carry itself ends mid-climb: nothing is left behind.
	var b := Measure.new()
	await b.run(self, &"small_mira_0", &"small_mira_0", 1, {"keep": true, "stop_early": halfway})
	rig = b.bench().rig
	rig.end_carry()
	await _step(b.bench(), 10)
	var orphans := rig.character_root.get_children().filter(func(node: Node) -> bool: return node.get_script() != null and str(node.get_script().resource_path).ends_with("rescue_passenger.gd"))
	check(not is_instance_valid(rig.carry_passenger) and rig.loaded_ladder == null and orphans.is_empty(), "Ending the carry mid-climb frees the passenger and the loaded state (no orphan under the carrier)")
	check(rig.grip_modifier.contact_weight == [0.0, 0.0] or not rig.carry_contacts_active(), "and no hand contact is left claimed")
	b.bench().queue_free()
	await _frames(2)

	# The casualty is changed mid-climb: a clean reset, then the next carry is the new body.
	var c := Measure.new()
	await c.run(self, &"mira_0", &"small_mira_0", 1, {"keep": true, "stop_early": halfway})
	var bench: Node3D = c.bench()
	rig = bench.rig
	bench.set_passenger(&"mira_0")
	await _step(bench, 10)
	check(rig.ladder == null and not is_instance_valid(rig.carry_passenger) and rig.loaded_ladder == null, "Changing the casualty mid-climb is a clean reset: no ladder, no passenger, no loaded state")
	rig.begin_carry()
	await _step(bench, 10)
	check(is_instance_valid(rig.carry_passenger) and rig.carry_passenger.definition.character_id == &"mira_0" and rig.loaded_ladder == null, "and the next carry is the chosen body, on the ordinary carry")
	bench.set_passenger(&"")
	bench.queue_free()
	await _frames(2)

	# Direction reversal while the passenger is still coming back: it resumes the climbing carry without a jump.
	var d := Measure.new()
	await d.run(self, &"mira_0", &"mira_0", 1, {"keep": true, "stop_early": func(r, bench2: Node3D, _time: float) -> bool: return r.loaded_ladder != null and r.loaded_ladder.target < 0.5 and r.loaded_ladder.blend < 0.7})
	bench = d.bench()
	rig = bench.rig
	check(rig.loaded_ladder != null and rig.loaded_ladder.blend < 0.7 and rig.loaded_ladder.blend > 0.05, "Setup: the passenger is part-way back to the ordinary carry (%.2f)" % rig.loaded_ladder.blend)
	var chest := rig.skeleton.find_bone(rig.torso_bone_name)
	_previous_relative = Vector3.INF
	_worst_relative = 0.0
	var track := func() -> void:
		if not is_instance_valid(rig.carry_passenger):
			return
		var relative: Vector3 = (rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(chest)).affine_inverse() * rig.carry_passenger.global_position
		if _previous_relative.is_finite():
			_worst_relative = maxf(_worst_relative, relative.distance_to(_previous_relative))
		_previous_relative = relative
	rig.skeleton.skeleton_updated.connect(track)
	bench.start_ladder_demo(3.0, -1, 0.75, -1.0, "rails")
	bench.set_sim_paused(true)
	bench.step_seconds = 1.0 / 30.0
	var ready_at := -1
	for step in 90:
		bench.step_sim()
		await process_frame
		if ready_at < 0 and rig.loaded_ladder_ready() and rig.loaded_ladder != null and rig.loaded_ladder.blend > 0.999:
			ready_at = step
	var worst := _worst_relative
	rig.skeleton.skeleton_updated.disconnect(track)
	check(rig.loaded_ladder != null and rig.loaded_ladder.target > 0.5 and ready_at > 0, "Reversing resumes the transfer into the climbing carry, and the climb waits for it")
	check(worst * 100.0 <= ATTACHMENT_STEP_CM, "and the passenger does not jump (%.1f cm the most in one step)" % (worst * 100.0))
	bench.queue_free()
	await _frames(2)


## The same run twice is the same run; a different frame step gives the same transfer and the same end.
func _determinism() -> void:
	var first: Dictionary = await Measure.new().run(self, &"mira_0", &"small_mira_0", 1)
	var second: Dictionary = await Measure.new().run(self, &"mira_0", &"small_mira_0", 1)
	var same := true
	for key in ["free_hand_mean_cm", "support_hand_mean_cm", "feet_max_cm", "relative_step_max_cm", "lowest_m", "deck_clearance_min_m", "ladder_clearance_min_m", "transfer_seconds"]:
		same = same and first[key] == second[key]
	check(same, "The same climb twice gives the same measurements")
	var fine: Dictionary = await Measure.new().run(self, &"mira_0", &"small_mira_0", 1, {"step": 1.0 / 60.0})
	var coarse: Dictionary = await Measure.new().run(self, &"mira_0", &"small_mira_0", 1, {"step": 1.0 / 20.0})
	check(absf(float(fine.transfer_seconds) - float(coarse.transfer_seconds)) <= 0.06, "The transfer takes the same time at 60 and at 20 steps a second (%.2f and %.2f s)" % [fine.transfer_seconds, coarse.transfer_seconds])
	check(bool(fine.restored) and bool(coarse.restored) and bool(fine.identity_ok) and bool(coarse.identity_ok), "and both runs end with the ordinary carry restored")
	check(float(fine.support_hand_max_cm) <= SUPPORT_HAND_MAX_CM and float(coarse.support_hand_max_cm) <= SUPPORT_HAND_MAX_CM, "and the supporting hand stays on its contact at either rate")
