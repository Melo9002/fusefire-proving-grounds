extends SceneTree
## The WeaponPose modifier (animation improvement 02): weapon targets come from the shoulder of the SAME skeleton
## pass (after CoverCrouch, before the arm IK), the stock sits in the real shoulder pocket, the support arm is eased
## into reach within explicit protraction limits, the remaining deficit is reported, and unrelated states do not change.
## Runs on the production UnitVisualAdapter path. `weapon_pose_modifier_enabled = false` is the legacy behaviour
## (targets from the animation-only shoulder), used here for A/B comparisons.

var failures := 0
var checks := 0

class StaleReader extends Node:
	var skeleton: Skeleton3D
	var bone := -1
	var stale_world := Vector3.ZERO
	func _process(_delta: float) -> void:
		if skeleton != null and bone >= 0:
			stale_world = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _apply(rig: UnitVisualAdapter, entry: String) -> void:
	var state := entry.split("@")[0].replace("+aim", "")
	rig._aim_held = entry.ends_with("+aim")
	rig._aim_release_left = 1000000.0
	if "@" in entry:
		var cover_type := MapCellData.CoverType.FULL if state == "cover_high" else MapCellData.CoverType.LOW
		rig.last_cover_contact = {"type": cover_type, "height": float(entry.split("@")[1].replace("+aim", "")), "direction": Vector3.FORWARD}
	else:
		rig.last_cover_contact = {"type": MapCellData.CoverType.NONE, "direction": Vector3.ZERO}
	rig.animation_controller.play(StringName(state))
	rig._retarget_aim_blend()

func _settle(frames := 40, seconds := 1.6) -> void:
	for i in frames: await process_frame
	await create_timer(seconds).timeout
	for i in 3: await process_frame

func _new_rig() -> Array:
	var stage := Node3D.new()
	root.add_child(stage)
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	stage.add_child(rig)
	rig.position = Vector3.ZERO
	for i in 20: await process_frame
	var diagnostics := HandContactDiagnostics.attach(rig)
	diagnostics.set_readout_visible(false)
	diagnostics.set_enabled(true)
	return [stage, rig, diagnostics]

func _stock_error(rig: UnitVisualAdapter, sample: Dictionary) -> float:
	var pocket: Vector3 = (sample.hands[0].shoulder as Vector3) + rig.character_root.global_basis * rig.shoulder_contact_offset
	return (sample.points.stock as Vector3).distance_to(pocket)

func _run() -> void:
	var made: Array = await _new_rig()
	var stage: Node3D = made[0]
	var rig: UnitVisualAdapter = made[1]
	var diagnostics: HandContactDiagnostics = made[2]
	var modifier: WeaponPoseModifier = rig.weapon_pose_modifier
	if modifier == null:
		push_error("The rig has no WeaponPose modifier")
		quit(1)
		return
	var skeleton: Skeleton3D = rig.skeleton

	# Order of the skeleton's modifiers.
	var order: Array[String] = []
	for child in skeleton.get_children():
		if child is SkeletonModifier3D: order.append(String(child.name))
	check(modifier != null and order == ["CoverCrouch", "WeaponPose", "WeaponArmIK", "HandGrip"], "Modifier order is CoverCrouch, WeaponPose, WeaponArmIK, HandGrip (%s)" % str(order))
	check(rig.weapon_pose_modifier_controls_targets(), "The modifier controls the targets at runtime")
	if not rig.weapon_pose_modifier_controls_targets():
		print("Weapon pose modifier: %d checks, %d failure(s) (stopped: the modifier is not in control)" % [checks, failures])
		quit(1)
		return

	# Same-pass shoulder: the modifier's shoulder is the final one, not the animation-only one a _process sees.
	var reader := StaleReader.new()
	reader.skeleton = skeleton
	reader.bone = skeleton.find_bone(rig.right_arm_bones[0])
	stage.add_child(reader)
	_apply(rig, "cover_low@0.5+aim")
	await _settle()
	var sample := diagnostics.latest
	var final_shoulder: Vector3 = sample.hands[0].shoulder
	check(modifier.last_shoulder_world.distance_to(final_shoulder) < 0.0002, "The shoulder the modifier read equals the final shoulder (%.3f mm apart)" % (modifier.last_shoulder_world.distance_to(final_shoulder) * 1000.0))
	check(reader.stale_world.distance_to(final_shoulder) > 0.15, "...which a _process reading would have missed by %.0f mm in the half-kneel" % (reader.stale_world.distance_to(final_shoulder) * 1000.0))
	reader.queue_free()

	# Stock in the real shoulder pocket, reachability, elbow and margin, for the four baseline poses plus idle.
	var settled := {}
	for entry in ["rifle_idle", "aim", "cover_low@1.15+aim", "cover_low@0.5", "cover_low@0.5+aim"]:
		_apply(rig, entry)
		await _settle()
		settled[entry] = diagnostics.latest
	for entry in ["aim", "cover_low@1.15+aim", "cover_low@0.5+aim"]:
		check(_stock_error(rig, settled[entry]) < 0.002, "%s: the stock is in the real shoulder pocket (%.2f mm)" % [entry, _stock_error(rig, settled[entry]) * 1000.0])
	for entry in settled:
		var s: Dictionary = settled[entry]
		check(float(s.hands[0].wrist_to_ik_target) < 0.001, "%s: dominant wrist reaches its target (%.2f mm)" % [entry, float(s.hands[0].wrist_to_ik_target) * 1000.0])
	check(float(settled["aim"].hands[1].wrist_to_ik_target) < 0.001 and float(settled["aim"].hands[1].elbow_angle_deg) < 170.0, "Standing aim stays reachable with a bent support elbow (%.0f deg, margin %.1f mm)" % [settled["aim"].hands[1].elbow_angle_deg, float(settled["aim"].hands[1].reach_margin) * 1000.0])
	check(float(settled["cover_low@1.15+aim"].hands[1].wrist_to_ik_target) < 0.001, "Crouch + aim stays reachable (%.2f mm)" % (float(settled["cover_low@1.15+aim"].hands[1].wrist_to_ik_target) * 1000.0))
	check(float(settled["cover_low@0.5"].hands[1].wrist_to_ik_target) < 0.001, "Half-kneel (weapon low) is reachable (was 23.4 mm)")
	var kneel_aim: Dictionary = settled["cover_low@0.5+aim"]
	var kneel_error := float(kneel_aim.hands[1].wrist_to_ik_target) * 1000.0
	check(kneel_error < 10.0, "Half-kneel + aim improves from 229.6 mm to %.1f mm" % kneel_error)
	check(absf(kneel_error - float(float(kneel_aim.meta.get("support_deficit_mm", -1.0)))) < 1.0, "...and the remaining error is exactly the reported deficit (%.1f mm reported)" % float(kneel_aim.meta.get("support_deficit_mm", -1.0)))
	check(bool(float(kneel_aim.meta.get("protraction_limited", -1.0))) and float(float(kneel_aim.meta.get("protraction_total_deg", -1.0))) <= float(float(kneel_aim.meta.get("protraction_limit_deg", -1.0))) + 0.001, "...with the protraction limit reached and not exceeded (%.1f of %.0f deg)" % [float(kneel_aim.meta.get("protraction_total_deg", -1.0)), float(kneel_aim.meta.get("protraction_limit_deg", -1.0))])

	# Unaffected states: protraction stays at its base and nothing extra is added.
	for entry in ["rifle_idle", "cover_low@0.5"]:
		var m: Dictionary = settled[entry].meta
		check(float(m.protraction_extra_deg) == 0.0 and float(m.protraction_total_deg) == float(m.protraction_base_deg), "%s: no protraction added" % entry)
	# Aiming uses only what it needs: standing aim adds a little, never the whole limit.
	check(float(float(settled["aim"].meta.get("protraction_extra_deg", -1.0))) > 0.0 and float(float(settled["aim"].meta.get("protraction_extra_deg", -1.0))) < float(float(settled["aim"].meta.get("protraction_limit_deg", -1.0))) - float(float(settled["aim"].meta.get("protraction_base_deg", -1.0))), "Standing aim adds only part of the headroom (%.1f deg)" % float(settled["aim"].meta.get("protraction_extra_deg", -1.0)))

	# Shoulder movement from the added reach is small and bounded, and bones keep their lengths.
	_apply(rig, "cover_low@0.5+aim")
	await _settle()
	var with_extra: Dictionary = diagnostics.latest
	var shoulder_with: Vector3 = (with_extra.hands[1].shoulder as Vector3)
	var limit_before := rig.support_protraction_limit_degrees
	rig.support_protraction_limit_degrees = 14.0
	await _settle(10, 0.3)
	var without: Dictionary = diagnostics.latest
	var shoulder_shift := shoulder_with.distance_to(without.hands[1].shoulder)
	check(shoulder_shift > 0.001 and shoulder_shift < 0.02, "The added protraction moves the support shoulder %.1f mm (bounded)" % (shoulder_shift * 1000.0))
	check(float(without.hands[1].wrist_to_ik_target) > float(with_extra.hands[1].wrist_to_ik_target) + 0.003, "Without the added reach the deficit is larger (%.1f mm against %.1f mm)" % [float(without.hands[1].wrist_to_ik_target) * 1000.0, float(with_extra.hands[1].wrist_to_ik_target) * 1000.0])
	check(float(float(without.meta.get("protraction_extra_deg", -1.0))) == 0.0, "A limit equal to the base adds nothing")
	var forearm_with := (with_extra.hands[1].elbow as Vector3).distance_to(with_extra.hands[1].wrist)
	var forearm_without := (without.hands[1].elbow as Vector3).distance_to(without.hands[1].wrist)
	check(absf(forearm_with - forearm_without) < 0.0005, "No bone is stretched: the forearm keeps its length (%.1f and %.1f cm)" % [forearm_with * 100.0, forearm_without * 100.0])
	# The limit is a property of the character: a wider one is used and also respected.
	rig.support_protraction_limit_degrees = 30.0
	await _settle(10, 0.3)
	var wide: Dictionary = diagnostics.latest
	check(float(float(wide.meta.get("protraction_total_deg", -1.0))) <= 30.001 and float(float(wide.meta.get("protraction_total_deg", -1.0))) > 18.0 and float(wide.hands[1].wrist_to_ik_target) < 0.0005, "A wider limit of 30 deg is used as needed and respected (%.1f deg, error %.2f mm)" % [float(wide.meta.get("protraction_total_deg", -1.0)), float(wide.hands[1].wrist_to_ik_target) * 1000.0])
	rig.support_protraction_limit_degrees = limit_before

	# Different arm length: the deficit is larger, reported, bounded, and the arm is not stretched.
	var left_hand := skeleton.find_bone(rig.left_arm_bones[2])
	var left_fore := skeleton.find_bone(rig.left_arm_bones[1])
	var rest_original := skeleton.get_bone_rest(left_hand)
	var rest_short := rest_original
	rest_short.origin *= 0.90
	skeleton.set_bone_rest(left_hand, rest_short)
	skeleton.set_bone_pose_position(left_hand, rest_short.origin)
	modifier.measure_arms(skeleton)
	diagnostics.sampler.setup(rig)
	_apply(rig, "aim")
	await _settle()
	var short_aim: Dictionary = diagnostics.latest
	_apply(rig, "cover_low@0.5+aim")
	await _settle()
	var short_kneel: Dictionary = diagnostics.latest
	var short_forearm := (short_kneel.hands[1].elbow as Vector3).distance_to(short_kneel.hands[1].wrist)
	check(float(float(short_aim.meta.get("protraction_total_deg", -1.0))) <= 18.001 and float(float(short_kneel.meta.get("protraction_total_deg", -1.0))) <= 18.001, "A shorter support arm never takes protraction past the limit")
	check(float(float(short_kneel.meta.get("support_deficit_mm", -1.0))) > kneel_error + 5.0 and absf(float(short_kneel.hands[1].wrist_to_ik_target) * 1000.0 - float(float(short_kneel.meta.get("support_deficit_mm", -1.0)))) < 1.0, "...the larger deficit is reported and matches the measurement (%.1f mm)" % float(short_kneel.meta.get("support_deficit_mm", -1.0)))
	check(absf(short_forearm - float(short_kneel.hands[1].arm_length) * 0.0 - (rest_short.origin.length() * skeleton.global_basis.get_scale().y)) < 0.01, "...and the forearm is the shorter one, not stretched (%.1f cm)" % (short_forearm * 100.0))
	skeleton.set_bone_rest(left_hand, rest_original)
	skeleton.set_bone_pose_position(left_hand, rest_original.origin)
	modifier.measure_arms(skeleton)
	diagnostics.sampler.setup(rig)

	# Different grip distance: a farther front grip needs more reach, still bounded and measured.
	var support_grip_before := rig.handling.support_grip
	rig.handling.support_grip = support_grip_before + Vector3(0, 0, 0.05)
	rig._place_hands_on_weapon()
	_apply(rig, "aim")
	await _settle()
	var far_grip: Dictionary = diagnostics.latest
	check(float(float(far_grip.meta.get("protraction_total_deg", -1.0))) <= 18.001 and float(float(far_grip.meta.get("protraction_total_deg", -1.0))) > float(float(settled["aim"].meta.get("protraction_total_deg", -1.0))), "A farther front grip asks for more protraction, within the limit (%.1f deg)" % float(far_grip.meta.get("protraction_total_deg", -1.0)))
	check(absf(float(far_grip.hands[1].wrist_to_ik_target) * 1000.0 - float(float(far_grip.meta.get("support_deficit_mm", -1.0)))) < 1.0, "...and any remaining error equals the reported deficit (%.1f mm)" % float(far_grip.meta.get("support_deficit_mm", -1.0)))
	rig.handling.support_grip = support_grip_before
	rig._place_hands_on_weapon()

	# Transitions: contact stays put in the weapon's frame.
	var transitions := [["rifle_idle", "aim"], ["aim", "rifle_idle"], ["cover_low@0.5", "cover_low@0.5+aim"], ["cover_low@0.5+aim", "cover_low@0.5"], ["aim", "cover_low@0.5+aim"], ["rifle_idle", "cover_low@1.15+aim"]]
	for pair in transitions:
		_apply(rig, pair[0])
		await _settle()
		diagnostics.mark_reference()
		diagnostics.start_recording()
		_apply(rig, pair[1])
		var elapsed := 0.0
		while elapsed < 1.4:
			var before := Time.get_ticks_msec()
			await process_frame
			elapsed += float(Time.get_ticks_msec() - before) / 1000.0
		var summary := diagnostics.stop_recording()
		check(float(summary.dominant.wrist_to_ik_target_mm) < 2.0 and float(summary.support.wrist_to_ik_target_mm) < 10.0, "%s > %s: peak wrist errors %.1f / %.1f mm" % [pair[0], pair[1], summary.dominant.wrist_to_ik_target_mm, summary.support.wrist_to_ik_target_mm])
		check(float(summary.support.palm_displacement_mm_max) < 12.0, "%s > %s: the support palm shifts at most %.1f mm in the weapon's frame (was up to 183 mm)" % [pair[0], pair[1], summary.support.palm_displacement_mm_max])
	# The shot: the weapon now follows the shoulder through the chest kick, which asks the support arm for more reach
	# than the 18 degree limit gives. That is measured and bounded here, not hidden (it was 10.9 mm with the legacy targets).
	_apply(rig, "aim")
	await _settle()
	diagnostics.mark_reference()
	diagnostics.start_recording()
	rig.animation_controller.play(&"shoot")
	var shot_time := 0.0
	while shot_time < 0.5:
		var before := Time.get_ticks_msec()
		await process_frame
		shot_time += float(Time.get_ticks_msec() - before) / 1000.0
	var shot := diagnostics.stop_recording()
	check(float(shot.dominant.wrist_to_ik_target_mm) < 2.0 and float(shot.support.palm_displacement_mm_max) < 35.0, "A shot: support palm shifts at most %.1f mm (legacy targets: 10.9 mm), dominant wrist error %.1f mm" % [shot.support.palm_displacement_mm_max, shot.dominant.wrist_to_ik_target_mm])
	print("SHOT-TRANSIENT support palm shift peak %.1f mm (legacy 10.9 mm), support wrist error peak %.1f mm" % [shot.support.palm_displacement_mm_max, shot.support.wrist_to_ik_target_mm])

	# Unrelated states: modifier vs legacy, with the legacy-to-legacy drift as the noise floor (looping clips move).
	for entry in ["rifle_idle", "move", "hit"]:
		var positions := {}
		for mode in ["legacy", "modifier", "legacy2"]:
			rig.weapon_pose_modifier_enabled = mode == "modifier"
			_apply(rig, entry)
			await _settle(30, 0.8)
			var s := diagnostics.latest
			positions[mode] = [s.hands[0].wrist, s.hands[1].wrist, s.hands[0].shoulder, s.hands[1].palm]
		var worst := 0.0
		var drift := 0.0
		for i in 4:
			var a: Vector3 = positions["legacy"][i]
			var b: Vector3 = positions["modifier"][i]
			var c: Vector3 = positions["legacy2"][i]
			worst = maxf(worst, b.distance_to((a + c) * 0.5))
			drift = maxf(drift, a.distance_to(c))
		check(worst <= drift * 0.5 + 0.001, "%s: unchanged by the modifier (%.2f mm from legacy, animation drift %.2f mm)" % [entry, worst * 1000.0, drift * 1000.0])
	# Cover poses without aim keep their body (the procedural crouch is CoverCrouch's) but the carried rifle's hands now
	# follow the REAL chest instead of the animation-only one, by exactly the amount the two chests differ. By design.
	var follower := StaleReader.new()
	follower.skeleton = skeleton
	follower.bone = skeleton.find_bone(rig.right_arm_bones[0])
	stage.add_child(follower)
	for entry in ["cover_low@1.15", "cover_high@2.0"]:
		rig.weapon_pose_modifier_enabled = false
		_apply(rig, entry)
		await _settle(30, 1.0)
		var legacy_sample := diagnostics.latest
		var chest_gap: float = follower.stale_world.distance_to(legacy_sample.hands[0].shoulder)
		var legacy_wrist: Vector3 = legacy_sample.hands[0].wrist
		rig.weapon_pose_modifier_enabled = true
		await _settle(10, 0.4)
		var new_wrist: Vector3 = diagnostics.latest.hands[0].wrist
		check(absf(new_wrist.distance_to(legacy_wrist) - chest_gap) < 0.006, "%s: the low-ready hands moved %.1f mm, the real chest differs from the animation-only chest by %.1f mm (by design)" % [entry, new_wrist.distance_to(legacy_wrist) * 1000.0, chest_gap * 1000.0])
	follower.queue_free()
	rig.weapon_pose_modifier_enabled = true

	# Carrying (06B): the arm IK now belongs to the carry contacts, so the modifier runs in the same pass and places the wrists on
	# the passenger instead of on the weapon (no weapon targets, no support reach). With the contacts switched off the arm IK stays
	# off and the modifier leaves the pose alone, as before.
	rig.preview_carrying = true
	rig.present_pickup()
	await _settle(20, 0.5)
	var passes_before := modifier.passes
	await _settle(20, 0.2)
	check(modifier.passes > passes_before and rig.carry_contacts_active() and modifier.report.get("available", true) == false, "While carrying with contacts the modifier runs and applies the carry contacts, not the weapon pose")
	rig.end_carry()
	rig.carry_contacts_enabled = false
	rig.present_pickup()
	await _settle(20, 0.5)
	passes_before = modifier.passes
	await _settle(20, 0.2)
	check(not rig.arm_ik.active and modifier.passes == passes_before, "With the carry contacts off (arm IK off) the modifier does nothing")
	stage.queue_free()
	await process_frame
	print("Weapon pose modifier: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
