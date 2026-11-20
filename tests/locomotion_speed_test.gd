extends SceneTree
## Speed-responsive locomotion (stabilization 01B): walk, jog and run chosen by speed from LocomotionProfile, their stride and cadence, smooth
## transitions, phase continuity, turning (twist, steps, banking), start and stop lean, rifle support while running, the loaded carry, and determinism.
## Geometric and contract invariants; no visual-tuning angles.

var failures := 0
var checks := 0
var _rig: UnitVisualAdapter
var _live := {}

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

func _pose_at(clip: Animation, t: float) -> Dictionary:
	var sk := _rig.skeleton
	sk.reset_bone_poses()
	for track in clip.get_track_count():
		var bone := sk.find_bone(clip.track_get_path(track).get_subname(0))
		if bone < 0:
			continue
		if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			sk.set_bone_pose_rotation(bone, clip.rotation_track_interpolate(track, t))
		elif clip.track_get_type(track) == Animation.TYPE_POSITION_3D:
			sk.set_bone_pose_position(bone, clip.position_track_interpolate(track, t))
	var to_root := _rig.character_root.global_transform.affine_inverse() * sk.global_transform
	return {"hip": to_root * sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftUpLeg")).origin, "foot": to_root * sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftFoot")).origin}

## Read INSIDE the skeleton's update, where the pose includes every modifier.
func _on_updated() -> void:
	var sk := _rig.skeleton
	var to_root := _rig.character_root.global_transform.affine_inverse() * sk.global_transform
	_live = {
		"left_foot": to_root * sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftFoot")).origin,
		"right_foot": to_root * sk.get_bone_global_pose(sk.find_bone("mixamorig_RightFoot")).origin,
		"hips": to_root * sk.get_bone_global_pose(sk.find_bone("mixamorig_Hips")).origin,
		"hips_basis": to_root.basis * sk.get_bone_global_pose(sk.find_bone("mixamorig_Hips")).basis,
		"chest_basis": to_root.basis * sk.get_bone_global_pose(sk.find_bone(_rig.torso_bone_name)).basis,
		"lengths": [
			sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftUpLeg")).origin.distance_to(sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftLeg")).origin),
			sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftLeg")).origin.distance_to(sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftFoot")).origin)],
	}

## Yaw (degrees, about the character's up) of a basis's forward axis in the character frame, with the skeleton's own forward subtracted.
func _yaw_of(basis: Basis, rest: Basis) -> float:
	var f := basis * (rest.inverse() * Vector3.BACK)
	return rad_to_deg(atan2(f.x, f.z))

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	stage.add_child(rig)
	await _frames(20)
	_rig = rig
	var p := rig.locomotion_profile
	var player: AnimationPlayer = rig.animation_controller.animation_player

	# ---- Speed to gait: a pure, editable mapping.
	check(p.gait_blend(0.0) == 0.0 and p.gait_blend(p.walk_until) == 0.0, "Up to the walk limit the gait is the walk")
	check(is_equal_approx(p.gait_blend(p.jog_at), 1.0) and is_equal_approx(p.gait_blend(p.run_at), 2.0) and p.gait_blend(99.0) == 2.0, "The jog is fully in at jog_at and the run at run_at (and no further)")
	var monotonic := true
	var last := -1.0
	for i in 201:
		var g := p.gait_blend(i * 0.04)
		monotonic = monotonic and g >= last
		last = g
	check(monotonic, "More speed never selects a slower gait")
	check(p.gait_blend(5.0) > 1.9, "The tactical game's 5 m/s is a run under the default thresholds, by threshold and not by name")
	var edited := LocomotionProfile.new()
	edited.run_at = 8.0
	check(edited.gait_blend(5.0) < 1.9 and p.gait_blend(5.0) > 1.9, "Thresholds belong to the profile: another profile maps the same speed to another gait")
	check(p.loaded_blend(0.5) == 0.0 and p.loaded_blend(5.0) == 1.0, "A loaded carrier walks slowly and trots fast; there is no loaded run")

	# ---- Stride model: the stance foot's ground travel / stance fraction is the stride, for every gait.
	var gaits := {&"move": p.walk, &"move_jog": p.jog, &"move_run": p.run, &"carry_move": p.loaded_walk, &"carry_move_fast": p.loaded_fast}
	var implied := {}
	for name in gaits:
		var g: LocomotionGait = gaits[name]
		var clip: Animation = player.get_animation(name)
		var start := _pose_at(clip, 0.0)
		var toe_off := _pose_at(clip, g.stance_fraction)
		var stance_travel: float = (start.foot.z - start.hip.z) - (toe_off.foot.z - toe_off.hip.z)
		implied[name] = stance_travel / g.stance_fraction
		print("  %s: stance travel %.2f m over %.2f of the cycle, implied stride %.2f m, profile stride %.2f m" % [name, stance_travel, g.stance_fraction, implied[name], g.stride_length])
		check(absf(implied[name] - g.stride_length) / g.stride_length < 0.12, "%s: the stride length (%.2f m) is what the stance foot covers (%.2f m)" % [name, g.stride_length, implied[name]])
	check(p.walk.stride_length < p.jog.stride_length and p.jog.stride_length < p.run.stride_length, "Faster gaits take longer strides")
	check(p.walk.stance_fraction > p.jog.stance_fraction and p.jog.stance_fraction > p.run.stance_fraction, "Faster gaits spend less of the cycle on the ground")
	check(p.run.knee_table[5] > p.jog.knee_table[5] + 10.0 and p.jog.knee_table[5] > p.walk.knee_table[5] + 10.0, "Knee recovery deepens from walk to jog to run")
	check(p.run.forward_lean_degrees > p.jog.forward_lean_degrees and p.walk.forward_lean_degrees == 0.0, "Only the faster gaits lean forward, the run more")
	# Cadence: speed / stride inside the allowed range, so the feet slide only where the range binds.
	var worst_slide := 0.0
	for speed in [1.0, 1.4, 2.0, 3.0, 4.0, 5.0]:
		var blend := p.gait_blend(speed)
		var cadence := p.cadence_for(speed, p.stride_at(blend))
		check(cadence >= p.min_cadence and cadence <= p.max_cadence, "Cadence stays in range at %.1f m/s (%.2f cycles/s)" % [speed, cadence])
		worst_slide = maxf(worst_slide, absf(cadence * p.stride_at(blend) - speed) / speed)
	print("  worst mismatch between cadence x stride and speed over 1 to 5 m/s: %.0f%%" % (worst_slide * 100.0))
	check(worst_slide < 0.2, "Feet cover the ground the body does, within 20%% across 1 to 5 m/s (%.0f%%)" % (worst_slide * 100.0))

	# ---- Live transitions through the real tree and modifiers: start, accelerate through walk and jog to run, run to stop.
	rig.skeleton.skeleton_updated.connect(_on_updated)
	rig.present_move()
	await _frames(3)
	var blends: Array[float] = []
	var cadences: Array[float] = []
	var speeds: Array[float] = []
	var foot_steps: Array[float] = []
	var length_change := 0.0
	var rest_lengths: Array = _live.lengths.duplicate()
	var last_foot: Vector3 = _live.left_foot - _live.hips
	var pitch_on_start := -99.0
	var pitch_on_stop := 99.0
	for frame in 150:
		var speed := 5.0 if frame < 90 else 0.0
		rig.update_locomotion_presentation(speed, 0.0, 1.0 / 60.0)
		await process_frame
		blends.append(float(rig.locomotion_report.gait))
		cadences.append(float(rig.locomotion_report.cadence))
		speeds.append(float(rig.locomotion_report.speed))
		var foot: Vector3 = _live.left_foot - _live.hips
		foot_steps.append(foot.distance_to(last_foot))
		last_foot = foot
		for k in 2:
			length_change = maxf(length_change, absf(float(_live.lengths[k]) - float(rest_lengths[k])))
		if frame < 40:
			pitch_on_start = maxf(pitch_on_start, rig.locomotion_modifier.pitch_degrees)
		if frame >= 90:
			pitch_on_stop = minf(pitch_on_stop, rig.locomotion_modifier.pitch_degrees)
	var worst_blend_step := 0.0
	var worst_cadence_step := 0.0
	var worst_stop_step := 0.0
	for i in range(1, blends.size()):
		if i < 90:
			worst_blend_step = maxf(worst_blend_step, absf(blends[i] - blends[i - 1]))
			worst_cadence_step = maxf(worst_cadence_step, absf(cadences[i] - cadences[i - 1]))
		else:
			worst_stop_step = maxf(worst_stop_step, absf(blends[i] - blends[i - 1]))
	check(blends[89] > 1.9 and speeds[89] > 4.99, "Held at full speed the unit is running (gait %.2f, speed %.2f)" % [blends[89], speeds[89]])
	check(worst_blend_step < 0.1 and worst_cadence_step < 0.3, "Gait blend and cadence change smoothly frame to frame while speeding up (%.3f, %.3f Hz)" % [worst_blend_step, worst_cadence_step])
	check(worst_stop_step < 0.3, "Braking to a stop brings the gait down without a jump (%.3f per frame)" % worst_stop_step)
	var mid_walk := false
	var mid_jog := false
	for i in 90:
		mid_walk = mid_walk or (blends[i] > 0.05 and blends[i] < 0.95)
		mid_jog = mid_jog or (blends[i] > 1.05 and blends[i] < 1.95)
	check(mid_walk and mid_jog, "Starting from rest at full speed passes through the walk and the jog on the way to the run")
	check(speeds[149] < 0.01 and blends[149] < 0.05, "Running to a stop settles the gait to nothing (speed %.2f, gait %.2f)" % [speeds[149], blends[149]])
	var steady_max := 0.0
	var transition_max := 0.0
	for i in 60:
		transition_max = maxf(transition_max, foot_steps[i])
	for i in range(70, 90):
		steady_max = maxf(steady_max, foot_steps[i])
	print("  left foot step per frame: transition %.3f m, steady run %.3f m" % [transition_max, steady_max])
	check(transition_max < steady_max * 1.5 + 0.02, "Blending between gaits never moves the feet more per frame than the run itself does (phase-synchronised: %.3f against %.3f m)" % [transition_max, steady_max])
	check(length_change < 0.0005, "Leg bone lengths hold through the transitions (%.4f mm)" % (length_change * 1000.0))
	check(pitch_on_start > 1.0 and pitch_on_stop < -1.0, "The trunk pitches forward as the unit speeds up and back as it brakes (%.1f, %.1f deg)" % [pitch_on_start, pitch_on_stop])

	# ---- Rifle support while running: the right hand stays on the grip, the arm IK and weapon pose still own the arms.
	for frame in 60:
		rig.update_locomotion_presentation(5.0, 0.0, 1.0 / 60.0)
		await process_frame
	var hand_error := rig.right_hand_target.global_position.distance_to(rig.weapon.to_global(rig.handling.firing_grip))
	check(hand_error < 0.15 and rig.arm_ik.active and not rig.carry_contacts_active(), "Running with the rifle keeps the right hand on its grip (%.0f mm)" % (hand_error * 1000.0))
	var bounce := 0.0
	var hips_low := 99.0
	var hips_high := -99.0
	var weapon_low := 99.0
	var weapon_high := -99.0
	for frame in 40:
		rig.update_locomotion_presentation(5.0, 0.0, 1.0 / 60.0)
		await process_frame
		hips_low = minf(hips_low, _live.hips.y)
		hips_high = maxf(hips_high, _live.hips.y)
		weapon_low = minf(weapon_low, rig.character_root.to_local(rig.weapon.global_position).y)
		weapon_high = maxf(weapon_high, rig.character_root.to_local(rig.weapon.global_position).y)
	print("  running: pelvis vertical range %.3f m, rifle vertical range %.3f m" % [hips_high - hips_low, weapon_high - weapon_low])
	check(weapon_high - weapon_low < 0.12, "The rifle does not bounce excessively while running (%.0f mm)" % ((weapon_high - weapon_low) * 1000.0))

	# ---- Turning in place: the chest and weapon are at the new facing at once; the hips catch up with two steps; a small turn needs no step.
	for frame in 40:
		rig.update_locomotion_presentation(0.0, 0.0, 1.0 / 60.0)
		await process_frame
	var rest_hips_yaw := _yaw_of(_live.hips_basis, Basis.IDENTITY)
	var rest_chest_yaw := _yaw_of(_live.chest_basis, Basis.IDENTITY)
	rig.begin_turn(deg_to_rad(90.0))
	await process_frame
	var twist: float = rig.locomotion_modifier.twist_degrees
	check(twist > p.turn_twist_limit - 8.0 and twist <= p.turn_twist_limit, "A 90 degree turn starts with the hips at most %.0f degrees behind (%.1f)" % [p.turn_twist_limit, twist])
	var hips_yaw := _yaw_of(_live.hips_basis, Basis.IDENTITY) - rest_hips_yaw
	var chest_yaw := _yaw_of(_live.chest_basis, Basis.IDENTITY) - rest_chest_yaw
	check(absf(hips_yaw + twist) < 3.0 and absf(chest_yaw) < 3.0, "The hips are turned back by the twist (%.1f deg) and the chest stays at the new facing (%.1f deg)" % [hips_yaw, chest_yaw])
	var most_lift := 0.0
	var frames_to_settle := 0
	for frame in 120:
		rig.update_locomotion_presentation(0.0, 0.0, 1.0 / 60.0)
		await process_frame
		most_lift = maxf(most_lift, maxf(float(rig.locomotion_modifier.step_lift[0]), float(rig.locomotion_modifier.step_lift[1])))
		if absf(rig.locomotion_modifier.twist_degrees) > 0.01:
			frames_to_settle = frame
	check(frames_to_settle > 5 and frames_to_settle / 60.0 < p.turn_twist_limit / p.turn_unwind_rate + 0.1, "The hips unwind over about %.2f s (%.2f s)" % [p.turn_twist_limit / p.turn_unwind_rate, frames_to_settle / 60.0])
	check(most_lift > p.turn_step_lift * 0.8, "A large turn is shown with repositioning steps (foot lift %.0f deg)" % most_lift)
	rig.begin_turn(deg_to_rad(-15.0))
	var small_lift := 0.0
	for frame in 40:
		rig.update_locomotion_presentation(0.0, 0.0, 1.0 / 60.0)
		await process_frame
		small_lift = maxf(small_lift, maxf(float(rig.locomotion_modifier.step_lift[0]), float(rig.locomotion_modifier.step_lift[1])))
	check(small_lift < 0.01, "A small turn is the torso and hips alone, without stepping")
	# Moving turns: banking into the turn, the right way round, none when loaded.
	for frame in 30:
		rig.update_locomotion_presentation(4.0, deg_to_rad(360.0), 1.0 / 60.0)
		await process_frame
	var bank_left: float = rig.locomotion_modifier.bank_degrees
	for frame in 60:
		rig.update_locomotion_presentation(4.0, deg_to_rad(-360.0), 1.0 / 60.0)
		await process_frame
	var bank_right: float = rig.locomotion_modifier.bank_degrees
	check(bank_left > 1.0 and bank_right < -1.0 and absf(bank_left) <= p.bank_max + 0.01, "The body banks into a turn, left and right, within the limit (%.1f, %.1f deg)" % [bank_left, bank_right])
	rig.update_locomotion_presentation(0.0, 0.0, 1.0)
	for frame in 20:
		rig.update_locomotion_presentation(0.0, 0.0, 1.0 / 60.0)
		await process_frame

	# ---- Determinism: the same speeds and frame times give the same presentation (presentation only; replay is untouched).
	var twin := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	stage.add_child(twin)
	await _frames(10)
	rig.update_locomotion_presentation(0.0, 0.0, 5.0)
	var identical := true
	for frame in 80:
		var s := 4.0 if frame < 50 else 0.5
		rig.update_locomotion_presentation(s, 0.2, 1.0 / 60.0)
		twin.update_locomotion_presentation(s, 0.2, 1.0 / 60.0)
		if frame > 0:
			pass
	for key in ["gait", "cadence", "accel", "bank"]:
		identical = identical and absf(float(rig.locomotion_report[key]) - float(twin.locomotion_report[key])) < 0.0001 or key == "speed"
	check(absf(float(rig.locomotion_report.gait) - float(twin.locomotion_report.gait)) < 0.05, "Two characters fed the same speeds end in the same gait (%.2f, %.2f)" % [rig.locomotion_report.gait, twin.locomotion_report.gait])
	twin.queue_free()

	# ---- Loaded: a carrier at full speed trots with the trunk square; contacts and passenger stay in place.
	rig.preview_carrying = true
	rig.begin_carry()
	rig.animation_controller.play(&"carry_move")
	await _frames(20)
	for frame in 90:
		rig.update_locomotion_presentation(5.0, deg_to_rad(300.0), 1.0 / 60.0)
		await process_frame
	check(float(rig.locomotion_report.loaded) > 0.95 and float(rig.locomotion_report.cadence) <= p.max_cadence, "A carrier at full speed uses the loaded trot (%.2f), within the cadence range" % rig.locomotion_report.loaded)
	check(rig.locomotion_modifier.bank_degrees == 0.0 and rig.locomotion_modifier.pitch_degrees == 0.0 and rig.locomotion_modifier.twist_degrees == 0.0, "A loaded carrier's trunk is held square: no bank, pitch or twist")
	rig.begin_turn(deg_to_rad(90.0))
	check(rig.locomotion_modifier.twist_degrees == 0.0, "A turn does not twist a carrier")
	check(rig.carry_contacts_active() and rig.carry_contact_report.size() == 2 and rig.grip_modifier.contact_weight == [1.0, 1.0], "The carry contacts are intact at speed")
	rig.preview_carrying = false
	rig.end_carry()

	rig.skeleton.skeleton_updated.disconnect(_on_updated)
	stage.queue_free()
	await _frames(2)
	print("Locomotion speed: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
