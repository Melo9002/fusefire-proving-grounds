extends RefCounted
## Measures one loaded (or unloaded) ladder climb in the real Workbench, in paused fixed steps, from the FINAL pose (sampled inside `skeleton_updated`, where every modifier is included). Shared by the loaded-ladder
## test and tools/quality/loaded_ladder_probe.gd. Not a test itself.
##
## What is and is not measured:
##   - contact TARGETS and WRISTS/ANKLES: the distance from a limb's end bone to the point the presentation asked it to reach (an IK-target error; it does not prove nothing intersects);
##   - the passenger: the largest one-step movement of its attachment and of every bone, its attachment relative to the carrier's chest (continuity), its lowest bone above the ground and above the deck, and the
##     smallest clearance between any of its limbs (a bone-to-parent segment with a 5 cm radius) and the ladder's rails and rungs;
##   - NOT measured: mesh penetration (bone segments only), physical support, the carrier's own mesh against the passenger's.
## `chest_step_max_cm` is the carrier's own chest step: the unloaded climb has the same steps (the landing's), so it is reported to separate what the carrier does from what the passenger adds.

const SCENE := "res://tools/animation_workbench/pose_workbench.tscn"
const STEP := 1.0 / 30.0
const LIMB_RADIUS := 0.05
const CARRY_SETTLE_FRAMES := 30

var _host: SceneTree
var _bench: Node3D
var _sample := {}


## `options`: armed (false), step (STEP seconds), tune (a Callable(rig) run before the carry starts, for controls and sweeps), keep (true leaves the bench alive in `bench` for the caller),
## landing (the ladder demo's landing kind, "rails"), rate (climb speed), stop_early (a Callable(rig, bench, time) -> bool).
func run(host: SceneTree, carrier: StringName, passenger: StringName, direction: int, options := {}) -> Dictionary:
	_host = host
	var step := float(options.get("step", STEP))
	WorkbenchSession.character = carrier
	WorkbenchSession.armed = bool(options.get("armed", false))
	WorkbenchSession.passenger = &""
	WorkbenchSession.autostart_scenario = &""
	WorkbenchSession.start_tab = -1
	_bench = (load(SCENE) as PackedScene).instantiate()
	host.root.add_child(_bench)
	for i in 10:
		await host.process_frame
	var rig: CharacterRig = _bench.rig
	PassengerFit.clear_cache()
	if options.has("tune"):
		(options.tune as Callable).call(rig)
	var loaded := passenger != &"none"
	if loaded:
		rig.passenger_definition = PassengerDefinition.for_character(passenger)
		rig.begin_carry()
		rig.animation_controller.play(&"carry_idle")
	for i in CARRY_SETTLE_FRAMES:
		await host.process_frame
	_sample = {}
	var previous := {}
	var worst := {"free": [], "support": [], "feet": 0.0, "step": 0.0, "bone_step": 0.0, "lowest": INF, "gap": INF, "deck": INF, "gap_bone": "", "gap_at": 0.0, "chest_step": 0.0, "relative_step": 0.0, "relative_at": 0.0}
	var final_capture := func() -> void:
		_sample = _capture(rig)
	rig.skeleton.skeleton_updated.connect(final_capture)
	_bench.step_seconds = step
	var start_height := 0.0 if direction > 0 else 3.0
	_bench.start_ladder_demo(3.0, direction, float(options.get("rate", 0.85 if direction > 0 else 0.75)), -1.0, String(options.get("landing", "rails")))
	_bench.set_sim_paused(true)
	var time := 0.0
	var transfer_seconds := -1.0
	var height_at_ready := -1.0
	var moved_during_transfer := false
	var restored_at := -1.0
	var guard := 0
	while guard < 2400:
		guard += 1
		_bench.step_sim()
		await host.process_frame
		time += step
		var sample := _sample
		if sample.is_empty():
			continue
		var climbed := float(_bench.ladder_demo.get("climbed", start_height))
		if loaded and transfer_seconds < 0.0:
			if rig.loaded_ladder != null and rig.loaded_ladder.blend >= 0.999:
				transfer_seconds = time
				height_at_ready = climbed
			elif absf(climbed - start_height) > 0.001:
				moved_during_transfer = true
		if previous.has("chest"):
			worst.chest_step = maxf(float(worst.chest_step), (sample.chest as Vector3).distance_to(previous.chest))
			if loaded:
				var relative_step := (sample.relative as Vector3).distance_to(previous.relative)
				if relative_step > float(worst.relative_step):
					worst.relative_step = relative_step
					worst.relative_at = time
				worst.step = maxf(float(worst.step), (sample.anchor as Vector3).distance_to(previous.anchor))
				if sample.points.size() == previous.points.size():
					for i in (sample.points as Array).size():
						worst.bone_step = maxf(float(worst.bone_step), (sample.points[i] as Vector3).distance_to(previous.points[i]))
		previous = sample
		var on_rungs: bool = rig.ladder != null and rig.ladder.pose != null and float(_bench.ladder_demo.get("across", 0.0)) < 0.05 and (not loaded or (rig.loaded_ladder != null and rig.loaded_ladder.blend >= 0.999))
		if on_rungs and rig.ladder.pose.weight > 0.9:
			(worst.free as Array).append(float(sample.free_hand_error))
			(worst.support as Array).append(float(sample.support_hand_error))
			worst.feet = maxf(float(worst.feet), float(sample.feet_error))
			if float(sample.ladder_clearance) < float(worst.gap):
				worst.gap = float(sample.ladder_clearance)
				worst.gap_bone = String(sample.gap_bone)
				worst.gap_at = time
		worst.lowest = minf(float(worst.lowest), float(sample.lowest))
		worst.deck = minf(float(worst.deck), float(sample.deck_clearance))
		if options.has("stop_early") and bool((options.stop_early as Callable).call(rig, _bench, time)):
			restored_at = -2.0
			break
		if loaded and transfer_seconds >= 0.0 and not bool(_bench.ladder_demo.playing) and (rig.loaded_ladder == null or rig.loaded_ladder.restored()):
			restored_at = time
			break
		if not loaded and not bool(_bench.ladder_demo.is_empty()) and not bool(_bench.ladder_demo.playing):
			restored_at = time
			break
	if is_instance_valid(rig.skeleton) and rig.skeleton.skeleton_updated.is_connected(final_capture):
		rig.skeleton.skeleton_updated.disconnect(final_capture)
	var result := {
		"carrier": String(carrier), "passenger": String(passenger), "direction": direction,
		"free_hand_mean_cm": _mean(worst.free), "free_hand_max_cm": _max(worst.free), "support_hand_mean_cm": _mean(worst.support), "support_hand_max_cm": _max(worst.support),
		"feet_max_cm": snappedf(float(worst.feet) * 100.0, 0.1), "passenger_step_max_cm": snappedf(float(worst.step) * 100.0, 0.1), "bone_step_max_cm": snappedf(float(worst.bone_step) * 100.0, 0.1),
		"chest_step_max_cm": snappedf(float(worst.chest_step) * 100.0, 0.1), "relative_step_max_cm": snappedf(float(worst.relative_step) * 100.0, 0.1), "relative_step_at_s": snappedf(float(worst.relative_at), 0.01),
		"lowest_m": snappedf(float(worst.lowest), 0.01), "deck_clearance_min_m": snappedf(float(worst.deck), 0.01),
		"ladder_clearance_min_m": snappedf(float(worst.gap), 0.001), "ladder_clearance_bone": worst.gap_bone, "ladder_clearance_at_s": snappedf(float(worst.gap_at), 0.01),
		"transfer_seconds": snappedf(transfer_seconds, 0.01), "height_at_ready_m": snappedf(height_at_ready, 0.001), "moved_during_transfer": moved_during_transfer, "restored": restored_at >= 0.0,
		"identity_ok": (not loaded) or (rig.carry_passenger != null and is_instance_valid(rig.carry_passenger) and rig.carry_passenger.definition.character_id == passenger),
	}
	if not bool(options.get("keep", false)):
		_bench.queue_free()
		await host.process_frame
	return result


func bench() -> Node3D:
	return _bench


## One sample of the final pose.
func _capture(rig: CharacterRig) -> Dictionary:
	var chest_index := rig.skeleton.find_bone(rig.torso_bone_name)
	var chest_world := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(chest_index) if chest_index >= 0 else Transform3D.IDENTITY
	var out := {"chest": chest_world.origin, "relative": Vector3.ZERO, "points": [] as Array[Vector3], "anchor": Vector3.ZERO, "lowest": 9.0, "deck_clearance": 9.0, "ladder_clearance": 9.0, "gap_bone": "",
		"free_hand_error": 0.0, "support_hand_error": 0.0, "feet_error": 0.0}
	var loaded := is_instance_valid(rig.carry_passenger) and rig.carry_passenger.skeleton != null
	var to_character := rig.character_root.global_transform.affine_inverse()
	# The character stays where it is and the ladder moves, so the ground is `climbed` below it; the deck is the ladder's rise above the ground.
	var climbed := rig.ladder.climbed if rig.ladder != null else 0.0
	var ground_y := rig.character_root.global_position.y - climbed
	var geometry := rig.ladder.geometry if rig.ladder != null else null
	var rise := rig.ladder.length if rig.ladder != null else 0.0
	var plane := geometry.plane_ahead if geometry != null else 9.0
	var lip := plane + (rig.ladder.landing.lip_from_rungs if rig.ladder != null and rig.ladder.landing != null else 0.0)
	var across := float(_bench.ladder_demo.get("across", 0.0))
	if loaded:
		var carried: Skeleton3D = rig.carry_passenger.skeleton
		var lowest := INF
		var deck := INF
		var gap := INF
		var gap_bone := ""
		for bone in carried.get_bone_count():
			var world := carried.global_transform * carried.get_bone_global_pose(bone).origin
			(out.points as Array).append(world)
			var local := to_character * world
			lowest = minf(lowest, world.y - ground_y)
			if local.z > lip and across > 0.05:
				deck = minf(deck, world.y - (ground_y + rise))
			if geometry != null:
				# The limb is the segment from this bone to its parent, sampled at three points against the rails and the nearest rungs (heights above the ladder's floor).
				var parent := carried.get_bone_parent(bone)
				var parent_local := to_character * (carried.global_transform * carried.get_bone_global_pose(parent).origin) if parent >= 0 else local
				for fraction in [0.0, 0.5, 1.0]:
					var point: Vector3 = local.lerp(parent_local, fraction)
					var clearance := _ladder_clearance(geometry, Vector3(point.x, point.y + climbed, point.z))
					if clearance < gap:
						gap = clearance
						gap_bone = carried.get_bone_name(bone)
		out.lowest = lowest
		out.deck_clearance = deck
		out.ladder_clearance = gap
		out.gap_bone = gap_bone
		out.anchor = rig.carry_passenger.anchor_world().origin
		out.relative = chest_world.affine_inverse() * rig.carry_passenger.global_position
	var wrists: Array[Vector3] = []
	for chain in [rig.right_arm_bones, rig.left_arm_bones]:
		wrists.append(rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(chain[2])).origin)
	var free_index := 0 if rig.loaded_climb_profile.free_hand == &"right" else 1
	var support_index := 1 - free_index
	var targets: Array[Vector3] = [rig.right_hand_target.global_position, rig.support_ik_target.global_position]
	out.free_hand_error = wrists[free_index].distance_to(targets[free_index])
	out.support_hand_error = wrists[support_index].distance_to(targets[support_index]) if loaded else 0.0
	var feet_error := 0.0
	for side in 2:
		var ankle: Vector3 = rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(rig.bones.left_leg[2] if side == 0 else rig.bones.right_leg[2])).origin
		feet_error = maxf(feet_error, ankle.distance_to(rig.foot_targets[side].global_position))
	out.feet_error = feet_error
	return out


## How far a limb's point (in the character's frame, y measured from the ladder's floor) is from the nearest rail or rung once both radii are taken off: negative means the two volumes overlap.
func _ladder_clearance(geometry: LadderGeometry, point: Vector3) -> float:
	var best := INF
	for side in [-1.0, 1.0]:
		best = minf(best, Vector2(point.x - side * geometry.rail_half_span(), point.z - geometry.plane_ahead).length() - geometry.rail_radius - LIMB_RADIUS)
	var nearest := clampi(roundi((point.y - geometry.first_rung()) / geometry.spacing()), 0, geometry.rung_count() - 1)
	for index in range(maxi(nearest - 1, 0), mini(nearest + 2, geometry.rung_count())):
		var on_rung := Vector3(clampf(point.x, -LadderGeometry.RUNG_HALF_LENGTH, LadderGeometry.RUNG_HALF_LENGTH), geometry.rung_height(index), geometry.plane_ahead)
		best = minf(best, point.distance_to(on_rung) - geometry.rung_radius - LIMB_RADIUS)
	return best


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
