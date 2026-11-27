extends SceneTree
## Measures the loaded ladder for every carrier/passenger pairing in both directions, in paused fixed steps, from the FINAL pose (sampled inside `skeleton_updated`, where every modifier is included).
## Read-only evidence for the loaded ladder presentation. What is and is not measured:
##   - contact TARGETS and WRISTS/ANKLES: the distance from a limb's end bone to the point the presentation asked it to reach (an IK-target error, not a proof that nothing intersects);
##   - the passenger: the largest one-step movement of its attachment (the abdomen bone) and of every bone (continuity), its lowest bone above the floor, and the smallest gap between any of its bones and the ladder's rung plane;
##   - NOT measured here: mesh penetration (bone points only), physical support, the carrier's own mesh against the passenger's.
##
##   godot_console --headless --path . --script res://tools/quality/loaded_ladder_probe.gd -- [json=user://loaded_ladder.json] [carriers=a,b] [passengers=a,b|none] [armed=false] [directions=1,-1]
## `passengers=none` is the UNLOADED baseline: the same climb with nobody carried, for the contact errors the loaded climb should be compared against.

const SCENE := "res://tools/animation_workbench/pose_workbench.tscn"
const STEP := 1.0 / 30.0
const LIMB_RADIUS := 0.05

var _rows: Array[Dictionary] = []
var _bench: Node3D
var _time := 0.0
var _sample := {}
var _args := {}


func _initialize() -> void:
	_run.call_deferred()


func _arguments() -> Dictionary:
	var result := {"json": "", "carriers": "", "passengers": "", "armed": "false", "directions": "1,-1", "ax": "", "ay": "", "az": "", "roll": "", "pitch": "", "yaw": "", "lean": "", "ux": "", "fx": "", "fz": ""}
	for argument in OS.get_cmdline_user_args():
		var parts := String(argument).split("=", true, 1)
		if parts.size() == 2:
			result[parts[0]] = parts[1]
	return result


func _run() -> void:
	var args := _arguments()
	var characters := PassengerDefinition.known_characters()
	if characters.is_empty():
		characters.assign([&"mira_0", &"small_mira_0"])
	var carriers: Array = characters if String(args.carriers).is_empty() else String(args.carriers).split(",")
	var passengers: Array = characters if String(args.passengers).is_empty() else String(args.passengers).split(",")
	_args = args
	var report: Array[Dictionary] = []
	for carrier in carriers:
		for passenger in passengers:
			for direction in String(args.directions).split(","):
				report.append(await _measure(StringName(carrier), StringName(passenger), int(direction), args.armed == "true"))
	for entry in report:
		print("LADDER %-13s carries %-13s %-4s | free hand %.1f cm (max %.1f) support hand %.1f cm (max %.1f) | feet max %.1f cm | carrier chest step max %.1f cm, passenger step max %.1f cm (relative to the chest %.1f cm at %.1f s), bone step max %.1f cm | above ground/deck: %.2f / %.2f m | limb-to-ladder clearance min %.3f m (%s at %.1f s, x/y/z-from-plane %s) | step peak at %.2f s | transfer %.1f s, restored %s" % [
			entry.carrier, entry.passenger, "up" if entry.direction > 0 else "down", entry.free_hand_mean_cm, entry.free_hand_max_cm, entry.support_hand_mean_cm, entry.support_hand_max_cm,
			entry.feet_max_cm, entry.chest_step_max_cm, entry.passenger_step_max_cm, entry.relative_step_max_cm, entry.relative_step_at_s, entry.bone_step_max_cm, entry.lowest_m, entry.deck_clearance_min_m, entry.ladder_clearance_min_m, entry.plane_gap_bone, entry.plane_gap_at_s, entry.plane_gap_point, entry.step_peak_at_s, entry.transfer_seconds, entry.restored])
	if not String(args.json).is_empty():
		var file := FileAccess.open(String(args.json), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	quit()


func _measure(carrier: StringName, passenger: StringName, direction: int, armed: bool) -> Dictionary:
	WorkbenchSession.character = carrier
	WorkbenchSession.armed = armed
	WorkbenchSession.autostart_scenario = &""
	WorkbenchSession.start_tab = -1
	_bench = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_bench)
	for i in 10:
		await process_frame
	var rig: CharacterRig = _bench.rig
	_tune(rig.loaded_climb_profile)
	PassengerFit.clear_cache()
	var loaded := passenger != &"none"
	if loaded:
		rig.passenger_definition = PassengerDefinition.for_character(passenger)
		rig.begin_carry()
		rig.animation_controller.play(&"carry_idle")
	for i in 30:
		await process_frame
	_rows.clear()
	_time = 0.0
	_sample = {}
	var previous_points: Array[Vector3] = []
	var previous_anchor := Vector3.INF
	var previous_chest := Vector3.INF
	var previous_relative := Vector3.INF
	var worst := {"free": [], "support": [], "feet": 0.0, "step": 0.0, "bone_step": 0.0, "lowest": INF, "gap": INF, "deck": INF, "step_peak": 0.0, "step_at": 0.0, "gap_bone": "", "gap_at": 0.0, "gap_point": Vector3.ZERO, "chest_step": 0.0, "relative_step": 0.0, "relative_at": 0.0}
	var final_capture := func() -> void:
		_sample = _capture(rig)
	rig.skeleton.skeleton_updated.connect(final_capture)
	_bench.step_seconds = STEP
	_bench.start_ladder_demo(3.0, direction, 0.85 if direction > 0 else 0.75, -1.0, "rails")
	_bench.set_sim_paused(true)
	var transfer_seconds := -1.0
	var guard := 0
	var restored_at := -1.0
	while guard < 1200:
		guard += 1
		_bench.step_sim()
		await process_frame
		_time += STEP
		var sample := _sample
		if sample.is_empty():
			continue
		if transfer_seconds < 0.0 and (not loaded or (rig.loaded_ladder != null and rig.loaded_ladder.blend >= 0.999)):
			transfer_seconds = _time if loaded else 0.0
		var ladder_on := rig.ladder != null
		sample["step"] = 0.0
		if previous_chest.is_finite():
			worst.chest_step = maxf(float(worst.chest_step), (sample.chest as Vector3).distance_to(previous_chest))
		if loaded and previous_relative.is_finite():
			var relative_step := (sample.relative as Vector3).distance_to(previous_relative)
			if relative_step > float(worst.relative_step):
				worst.relative_step = relative_step
				worst.relative_at = _time
		if not previous_points.is_empty() and sample.points.size() == previous_points.size():
			sample["step"] = (sample.anchor as Vector3).distance_to(previous_anchor)
			var bone_step := 0.0
			for i in previous_points.size():
				bone_step = maxf(bone_step, (sample.points[i] as Vector3).distance_to(previous_points[i]))
			worst.bone_step = maxf(float(worst.bone_step), bone_step)
			worst.step = maxf(float(worst.step), (sample.anchor as Vector3).distance_to(previous_anchor))
		previous_points = sample.points
		previous_anchor = sample.anchor
		previous_chest = sample.chest
		previous_relative = sample.relative
		var on_rungs: bool = ladder_on and rig.ladder.pose != null and float(_bench.ladder_demo.get("across", 0.0)) < 0.05 and (not loaded or (rig.loaded_ladder != null and rig.loaded_ladder.blend >= 0.999))
		if on_rungs and rig.ladder.pose.weight > 0.9:
			(worst.free as Array).append(float(sample.free_hand_error))
			(worst.support as Array).append(float(sample.support_hand_error))
			worst.feet = maxf(float(worst.feet), float(sample.feet_error))
			if float(sample.plane_gap) < float(worst.gap):
				worst.gap = float(sample.plane_gap)
				worst.gap_bone = String(sample.get("gap_bone", ""))
				worst.gap_at = _time
				worst.gap_point = sample.get("gap_point", Vector3.ZERO)
		worst.lowest = minf(float(worst.lowest), float(sample.lowest))
		worst.deck = minf(float(worst.deck), float(sample.deck_clearance))
		if float(sample.step) > float(worst.step_peak):
			worst.step_peak = float(sample.step)
			worst.step_at = _time
		if loaded and transfer_seconds >= 0.0 and not bool(_bench.ladder_demo.playing) and (rig.loaded_ladder == null or rig.loaded_ladder.restored()):
			restored_at = _time
			break
		if not loaded and not bool(_bench.ladder_demo.is_empty()) and not bool(_bench.ladder_demo.playing):
			restored_at = _time
			break
	rig.skeleton.skeleton_updated.disconnect(final_capture)
	var result := {
		"carrier": String(carrier), "passenger": String(passenger), "direction": direction,
		"free_hand_mean_cm": _mean(worst.free), "free_hand_max_cm": _max(worst.free), "support_hand_mean_cm": _mean(worst.support), "support_hand_max_cm": _max(worst.support),
		"feet_max_cm": snappedf(float(worst.feet) * 100.0, 0.1), "passenger_step_max_cm": snappedf(float(worst.step) * 100.0, 0.1), "bone_step_max_cm": snappedf(float(worst.bone_step) * 100.0, 0.1),
		"lowest_m": snappedf(float(worst.lowest), 0.01), "deck_clearance_min_m": snappedf(float(worst.deck), 0.01), "ladder_clearance_min_m": snappedf(float(worst.gap), 0.001), "transfer_seconds": snappedf(transfer_seconds, 0.1),
		"step_peak_at_s": snappedf(float(worst.step_at), 0.01), "plane_gap_bone": worst.gap_bone, "plane_gap_point": str(worst.gap_point), "plane_gap_at_s": snappedf(float(worst.gap_at), 0.01),
		"restored": restored_at >= 0.0,
		"chest_step_max_cm": snappedf(float(worst.chest_step) * 100.0, 0.1), "relative_step_max_cm": snappedf(float(worst.relative_step) * 100.0, 0.1), "relative_step_at_s": snappedf(float(worst.relative_at), 0.01),
		"identity_ok": (not loaded) or (rig.carry_passenger != null and is_instance_valid(rig.carry_passenger) and rig.carry_passenger.definition.character_id == passenger),
	}
	_bench.queue_free()
	await process_frame
	return result


## One sample of the final pose: bone points of the passenger, where the carrier's wrists and ankles are against where they were asked to be.
func _capture(rig: CharacterRig) -> Dictionary:
	var chest_index := rig.skeleton.find_bone(rig.torso_bone_name)
	var chest_world := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(chest_index) if chest_index >= 0 else Transform3D.IDENTITY
	var out := {"chest": chest_world.origin, "relative": Vector3.ZERO, "across": float(_bench.ladder_demo.get("across", 0.0)), "points": [] as Array[Vector3], "anchor": Vector3.ZERO, "lowest": 9.0, "deck_clearance": 9.0, "plane_gap": 9.0, "free_hand_error": 0.0, "support_hand_error": 0.0, "feet_error": 0.0}
	var loaded := is_instance_valid(rig.carry_passenger) and rig.carry_passenger.skeleton != null
	var to_character := rig.character_root.global_transform.affine_inverse()
	# The character stays where it is and the ladder moves, so the ground is `climbed` below it; the deck is the ladder's rise above the ground.
	var climbed := rig.ladder.climbed if rig.ladder != null else 0.0
	var ground_y := rig.character_root.global_position.y - climbed
	var plane := rig.ladder.geometry.plane_ahead if rig.ladder != null else 9.0
	var rise := rig.ladder.length if rig.ladder != null else 0.0
	var lip := plane + (rig.ladder.landing.lip_from_rungs if rig.ladder != null and rig.ladder.landing != null else 0.0)
	if loaded:
		var carried: Skeleton3D = rig.carry_passenger.skeleton
		var lowest := INF
		var deck := INF
		var gap := INF
		var gap_bone := ""
		var geometry := rig.ladder.geometry if rig.ladder != null else null
		for bone in carried.get_bone_count():
			var world := carried.global_transform * carried.get_bone_global_pose(bone).origin
			(out.points as Array).append(world)
			var local := to_character * world
			lowest = minf(lowest, world.y - ground_y)
			if local.z > lip and float(_bench.ladder_demo.get("across", 0.0)) > 0.05:
				deck = minf(deck, world.y - (ground_y + rise))
			if geometry != null:
				# The limb is the segment from this bone to its parent; sample it at three points against the rails and the nearest rungs (heights above the ladder's floor).
				var parent := carried.get_bone_parent(bone)
				var parent_local := to_character * (carried.global_transform * carried.get_bone_global_pose(parent).origin) if parent >= 0 else local
				for fraction in [0.0, 0.5, 1.0]:
					var point: Vector3 = local.lerp(parent_local, fraction)
					var clearance := _ladder_clearance(geometry, Vector3(point.x, point.y + climbed, point.z))
					if clearance < gap:
						gap = clearance
						gap_bone = carried.get_bone_name(bone)
						out.gap_point = Vector3(point.x, point.y + climbed, point.z - geometry.plane_ahead)
		out.lowest = lowest
		out.deck_clearance = deck
		out.plane_gap = gap
		out.gap_bone = gap_bone
		out.anchor = rig.carry_passenger.anchor_world().origin
		out.relative = chest_world.affine_inverse() * rig.carry_passenger.global_position
	var wrists: Array[Vector3] = []
	for chain in [rig.right_arm_bones, rig.left_arm_bones]:
		wrists.append(rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(chain[2])).origin)
	var free_index := 0 if rig.loaded_climb_profile.free_hand == &"right" else 1
	var support_index := 1 - free_index
	out.free_hand_error = wrists[free_index].distance_to(rig.right_hand_target.global_position if free_index == 0 else rig.support_ik_target.global_position)
	out.support_hand_error = wrists[support_index].distance_to(rig.right_hand_target.global_position if support_index == 0 else rig.support_ik_target.global_position) if loaded else 0.0
	var feet_error := 0.0
	for side in 2:
		var ankle: Vector3 = rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(rig.bones.left_leg[2] if side == 0 else rig.bones.right_leg[2])).origin
		feet_error = maxf(feet_error, ankle.distance_to(rig.foot_targets[side].global_position))
	out.feet_error = feet_error
	return out


func _mean(values: Array) -> float:
	if values.is_empty():
		return -1.0
	var total := 0.0
	for value in values:
		total += float(value)
	return snappedf(total / values.size() * 100.0, 0.1)


func _max(values: Array) -> float:
	var best := 0.0
	for value in values:
		best = maxf(best, float(value))
	return snappedf(best * 100.0, 0.1)


## Profile overrides for sweeps, without editing resources: ax/ay/az the anchor from the neck, roll/pitch/yaw the turn (degrees), lean.
func _tune(profile: LoadedClimbProfile) -> void:
	var anchor := profile.anchor_from_neck
	if String(_args.ax) != "": anchor.x = float(_args.ax)
	if String(_args.ay) != "": anchor.y = float(_args.ay)
	if String(_args.az) != "": anchor.z = float(_args.az)
	profile.anchor_from_neck = anchor
	var angles := profile.orientation_degrees
	if String(_args.pitch) != "": angles.x = float(_args.pitch)
	if String(_args.yaw) != "": angles.y = float(_args.yaw)
	if String(_args.roll) != "": angles.z = float(_args.roll)
	profile.orientation_degrees = angles
	if String(_args.lean) != "": profile.climb_lean_degrees = float(_args.lean)
	var up := profile.body_up
	if String(_args.ux) != "": up.x = float(_args.ux)
	profile.body_up = up
	var face := profile.body_face
	if String(_args.fx) != "": face.x = float(_args.fx)
	if String(_args.fz) != "": face.z = float(_args.fz)
	profile.body_face = face


## How far a limb's point (the passenger's, in the character's frame with y measured from the ladder's floor) is from the nearest rail or rung once both radii are taken off: negative means the two volumes overlap.
func _ladder_clearance(geometry: LadderGeometry, point: Vector3) -> float:
	var best := INF
	for side in [-1.0, 1.0]:
		best = minf(best, Vector2(point.x - side * geometry.rail_half_span(), point.z - geometry.plane_ahead).length() - geometry.rail_radius - LIMB_RADIUS)
	var nearest := clampi(roundi((point.y - geometry.first_rung()) / geometry.spacing()), 0, geometry.rung_count() - 1)
	for index in range(maxi(nearest - 1, 0), mini(nearest + 2, geometry.rung_count())):
		var rung_y := geometry.rung_height(index)
		var on_rung := Vector3(clampf(point.x, -LadderGeometry.RUNG_HALF_LENGTH, LadderGeometry.RUNG_HALF_LENGTH), rung_y, geometry.plane_ahead)
		best = minf(best, point.distance_to(on_rung) - geometry.rung_radius - LIMB_RADIUS)
	return best
