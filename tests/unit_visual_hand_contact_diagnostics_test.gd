extends SceneTree
## The hand-contact diagnostics (presentation/diagnostics/): the measurements are finite, in metres, in one
## coordinate space, follow the pose, are stable when it is still, and are completely gone when switched off;
## gameplay never carries them; the pose workbench's controls (old and new) still work.
## This tests the diagnostic tools, not the animation: no animation-quality threshold is asserted anywhere.

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance

func _run() -> void:
	await _production_rig()
	await _workbench()
	print("Hand contact diagnostics: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _connections_to(signal_value: Signal, method_name: String) -> int:
	var count := 0
	for connection in signal_value.get_connections():
		if String(connection.callable.get_method()) == method_name:
			count += 1
	return count

func _all_finite(value: Variant) -> bool:
	if value is float:
		return is_finite(value)
	if value is Vector3:
		return value.is_finite()
	if value is Dictionary:
		for key in value:
			if not _all_finite(value[key]): return false
	if value is Array:
		for entry in value:
			if not _all_finite(entry): return false
	return true

func _production_rig() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	check(rig.find_children("*", "HandContactDiagnostics", true, false).is_empty() and rig.find_children("*", "HandContactOverlay", true, false).is_empty(), "The gameplay unit scene contains no diagnostics")
	stage.add_child(rig)
	rig.position = Vector3.ZERO
	for i in 30: await process_frame
	var skeleton: Skeleton3D = rig.skeleton
	# Listeners of skeleton_updated that are not BoneAttachment3D (the test adds some of those itself).
	var other_listeners := func() -> int:
		var count := 0
		for connection in skeleton.skeleton_updated.get_connections():
			if not connection.callable.get_object() is BoneAttachment3D:
				count += 1
		return count
	var updated_before: int = other_listeners.call()
	var children_before: Array[String] = []
	for child in skeleton.get_children(): children_before.append(String(child.name))

	var diagnostics := HandContactDiagnostics.attach(rig)
	check(diagnostics != null and diagnostics.sampler.setup_issues.is_empty(), "Diagnostics attach to the MIRA rig with no setup issues (%s)" % str(diagnostics.sampler.setup_issues if diagnostics else "null"))
	if diagnostics == null:
		return
	check(not diagnostics.enabled and diagnostics.overlay == null and int(other_listeners.call()) == updated_before, "Attached but off: no overlay and no extra skeleton_updated listener")
	var bone_attachments := {}
	for bone in [&"mixamorig_RightHand", &"mixamorig_LeftHand"]:
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = bone
		attachment.name = "TestAttachment_%s" % bone
		skeleton.add_child(attachment)
		bone_attachments[bone] = attachment
	rig.animation_controller.play(&"aim")
	rig.presenter.aim.held = true
	rig.presenter.aim.release_left = 1000000.0
	for i in 80: await process_frame
	var weapon_before: Transform3D = rig.weapon.global_transform
	var wrist_before: Vector3 = (bone_attachments[&"mixamorig_RightHand"] as Node3D).global_position

	diagnostics.set_enabled(true)
	check(diagnostics.enabled and is_instance_valid(diagnostics.overlay) and int(other_listeners.call()) == updated_before + 1, "Enabled: one overlay and one extra skeleton_updated listener")
	var listeners := skeleton.skeleton_updated.get_connections()
	check(String(listeners[listeners.size() - 1].callable.get_method()) == "_on_skeleton_updated" and _connections_to(skeleton.skeleton_updated, "_align_weapon_to_aim") == 1, "The diagnostics listener runs after the rig's own weapon alignment (it is the last listener)")
	for i in 5: await process_frame
	var latest := diagnostics.latest
	check(not latest.is_empty() and String(latest.meta.timing) == "post-update", "Samples come from the post-update callback (timing %s)" % latest.meta.get("timing", "none"))
	check(diagnostics.overlay.drawable_count() > 20, "The overlay draws markers and lines (%d nodes)" % diagnostics.overlay.drawable_count())

	# Finite, in metres, in one coordinate space.
	check(_all_finite(latest.hands) and _all_finite(latest.points), "Every measurement is finite")
	for hand: Dictionary in latest.hands:
		check(float(hand.arm_length) > 0.25 and float(hand.arm_length) < 0.9, "%s arm length is in metres (%.3f m)" % [hand.name, hand.arm_length])
		check(float(hand.reach) > 0.05 and float(hand.reach) < 1.0 and _near(float(hand.reach_margin), float(hand.arm_length) - float(hand.reach), 1e-6), "%s reach and margin are consistent metres" % hand.name)
		check(float(hand.elbow_angle_deg) >= 0.0 and float(hand.elbow_angle_deg) <= 180.0 and float(hand.finger_direction_error_deg) >= 0.0 and float(hand.finger_direction_error_deg) <= 180.0, "%s angles are degrees in range" % hand.name)
		check((hand.palm as Vector3).distance_to(hand.wrist) < 0.15 and (hand.palm as Vector3).distance_to(hand.knuckle_centre) < 0.15, "%s palm estimate lies between the wrist and the knuckles (approximation)" % hand.name)
	var right: Dictionary = latest.hands[HandContactSampler.DOMINANT]
	var left: Dictionary = latest.hands[HandContactSampler.SUPPORT]
	var final_right: Vector3 = (bone_attachments[&"mixamorig_RightHand"] as Node3D).global_position
	var final_left: Vector3 = (bone_attachments[&"mixamorig_LeftHand"] as Node3D).global_position
	check((right.wrist as Vector3).distance_to(final_right) < 0.0002 and (left.wrist as Vector3).distance_to(final_left) < 0.0002, "Wrist positions equal the rendered bone positions (BoneAttachment3D), so they are world-space final-pose values")
	check((right.ik_target as Vector3).distance_to(rig.right_hand_target.global_position) < 1e-6 and (left.ik_target as Vector3).distance_to(rig.support_ik_target.global_position) < 1e-6, "IK targets are the rig's own markers in world space")
	var weapon_frame := Transform3D(rig.weapon.global_basis.orthonormalized(), rig.weapon.global_position)
	check((weapon_frame * (right.palm_in_weapon_frame as Vector3)).distance_to(right.palm) < 1e-5, "Palm in the weapon's frame round-trips to world space")
	check((right.intended_palm as Vector3).distance_to(rig.weapon.to_global(rig.handling.firing_palm())) < 1e-6 and (left.intended_palm as Vector3).distance_to(rig.weapon.to_global(rig.handling.support_palm())) < 1e-6, "Intended palm points come from the weapon handling profile through the weapon's transform")
	check(float(latest.meta.get("weapon_basis_error_deg", 999.0)) < 0.01, "The weapon is where the rig expects it when sampled (%.4f deg)" % latest.meta.get("weapon_basis_error_deg", 999.0))
	check(_near(float(right.get("rest_palm_vs_down_deg", diagnostics.sampler._hands[0].rest_palm_vs_down_deg)), float(diagnostics.sampler._hands[0].rest_palm_vs_down_deg), 1e-6), "The rest palm tilt is exposed as data instead of being assumed")

	# Stable when the pose is still.
	var first := diagnostics.latest
	for i in 40: await process_frame
	var second := diagnostics.latest
	check(int(second.meta.frame) > int(first.meta.frame), "The post-update sample is refreshed every frame")
	var drift := 0.0
	for hand_index in 2:
		for key in ["wrist", "palm", "ik_target"]:
			drift = maxf(drift, ((first.hands as Array)[hand_index][key] as Vector3).distance_to((second.hands as Array)[hand_index][key]))
	check(drift < 0.0002, "A held pose measures the same 40 frames later (%.6f m of drift)" % drift)

	# Production is not changed by measuring.
	check((rig.weapon.global_transform.origin - weapon_before.origin).length() < 1e-5 and rig.weapon.global_basis.x.distance_to(weapon_before.basis.x) < 1e-5 and rig.weapon.global_basis.y.distance_to(weapon_before.basis.y) < 1e-5 and rig.weapon.global_basis.z.distance_to(weapon_before.basis.z) < 1e-5, "Switching diagnostics on moved nothing: the weapon is where it was")
	check(((bone_attachments[&"mixamorig_RightHand"] as Node3D).global_position - wrist_before).length() < 1e-5, "...and neither did the wrist")

	# The pose changes the numbers.
	var aim_palm: Vector3 = (second.hands as Array)[HandContactSampler.SUPPORT].palm
	rig.presenter.aim.held = false
	rig.animation_controller.play(&"rifle_idle")
	for i in 80: await process_frame
	var idle_sample := diagnostics.latest
	check(String(idle_sample.meta.state) == "rifle_idle" and (((idle_sample.hands as Array)[HandContactSampler.SUPPORT].palm as Vector3).distance_to(aim_palm) > 0.02), "The readings follow a pose change (support palm moved %.1f cm)" % (((idle_sample.hands as Array)[HandContactSampler.SUPPORT].palm as Vector3).distance_to(aim_palm) * 100.0))

	# Contact reference and displacement.
	diagnostics.mark_reference()
	check(not diagnostics.reference.is_empty() and float(diagnostics.displacement.support.palm) == 0.0 and float(diagnostics.peak_displacement.support.palm) == 0.0, "Marking a reference zeroes the displacement and the peaks")
	rig.presenter.aim.held = true
	rig.animation_controller.play(&"aim")
	diagnostics.start_recording()
	for i in 60: await process_frame
	var summary := diagnostics.stop_recording()
	check(int(summary.frames) >= 30 and summary.has("dominant") and summary.has("support") and float(diagnostics.peak_displacement.support.palm) >= float(diagnostics.displacement.support.palm), "Recording summarises the transition and the peak is never below the current value (%d frames)" % summary.frames)
	check(_all_finite(HandContactSampler.scalars(diagnostics.latest)) and not diagnostics.format_readout(diagnostics.latest).is_empty(), "The compact readout and the scalar baseline format are finite")

	# Sampling time matters: from a _process the bones are the previous update's.
	var probe := _TimingProbe.new()
	probe.diagnostics = diagnostics
	stage.add_child(probe)
	rig.presenter.aim.held = false
	rig.animation_controller.play(&"move")
	for i in 60: await process_frame
	check(probe.samples > 10 and probe.worst_wrist_metres >= 0.0 and is_finite(probe.worst_wrist_metres), "Sampling from _process was compared with the post-update sample (%d samples)" % probe.samples)
	print("TIMING sampling from _process instead of after the skeleton update: worst wrist difference %.2f mm, worst palm %.2f mm, worst weapon basis %.4f deg over %d frames while moving" % [probe.worst_wrist_metres * 1000.0, probe.worst_palm_metres * 1000.0, probe.worst_weapon_degrees, probe.samples])
	probe.queue_free()

	# Off again: everything the diagnostics made is gone.
	diagnostics.set_enabled(false)
	for i in 3: await process_frame
	check(not diagnostics.enabled and not is_instance_valid(diagnostics.overlay) and int(other_listeners.call()) == updated_before, "Disabled: overlay freed and the extra listener removed")
	check(diagnostics.find_children("*", "", true, false).is_empty(), "Disabled: the diagnostics node owns no children (no overlay, readout or layer)")
	var children_after: Array[String] = []
	for child in skeleton.get_children():
		if not String(child.name).begins_with("TestAttachment_"): children_after.append(String(child.name))
	var expected: Array[String] = []
	for name in children_before: expected.append(name)
	check(children_after == expected, "The skeleton's own children are exactly as before diagnostics existed")
	var frames_before: int = diagnostics.latest.meta.frame
	for i in 5: await process_frame
	check(diagnostics.latest.meta.frame == frames_before, "Disabled diagnostics take no more samples")
	stage.queue_free()
	await process_frame

class _TimingProbe extends Node:
	var diagnostics: HandContactDiagnostics
	var samples := 0
	var worst_wrist_metres := 0.0
	var worst_palm_metres := 0.0
	var worst_weapon_degrees := 0.0
	func _process(_delta: float) -> void:
		if not is_instance_valid(diagnostics) or not diagnostics.enabled:
			return
		var timing := diagnostics.compare_timing()
		if timing.is_empty():
			return
		samples += 1
		for hand in ["dominant", "support"]:
			worst_wrist_metres = maxf(worst_wrist_metres, float(timing[hand].wrist))
			worst_palm_metres = maxf(worst_palm_metres, float(timing[hand].get("palm", 0.0)))
		worst_weapon_degrees = maxf(worst_weapon_degrees, float(timing.weapon_basis_deg))

func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event

func _workbench() -> void:
	var workbench: Node3D = load("res://art/characters/mira_0/demo/mira_0_pose_workbench.tscn").instantiate()
	root.add_child(workbench)
	for i in 30: await process_frame
	var status: Label = workbench.get_node("UI/Status")
	check(workbench.skeleton != null and workbench.animation_controller != null and status.text.contains("STATE: rifle_idle"), "The pose workbench loads in its idle state")
	check(workbench.find_children("*", "HandContactDiagnostics", true, false).is_empty() and workbench.find_children("*", "HandContactOverlay", true, false).is_empty(), "A fresh workbench carries no diagnostics")
	check(status.text.contains("H: hand diagnostics off"), "The workbench lists the new controls")
	# Existing controls still work.
	workbench._unhandled_input(_key(KEY_3))
	for i in 10: await process_frame
	check(workbench.animation_controller.current_state == &"aim" and status.text.contains("STATE: aim"), "Key 3 still plays aim")
	workbench._unhandled_input(_key(KEY_4))
	for i in 5: await process_frame
	check(workbench.animation_controller.current_state == &"shoot", "Key 4 still plays shoot")
	workbench._unhandled_input(_key(KEY_I))
	check(not workbench.ik_enabled and status.text.contains("IK: OFF"), "Key I still toggles the IK")
	workbench._unhandled_input(_key(KEY_I))
	workbench._unhandled_input(_key(KEY_3))
	for i in 20: await process_frame
	# New controls.
	workbench._unhandled_input(_key(KEY_H))
	for i in 5: await process_frame
	var diagnostics: HandContactDiagnostics = workbench._diagnostics
	check(diagnostics != null and diagnostics.enabled and is_instance_valid(diagnostics.overlay) and status.text.contains("hand diagnostics ON"), "Key H switches the diagnostics on")
	check(workbench.get_node("UI").find_child("HandContactReadout", true, false) != null, "The readout is shown in the workbench UI")
	workbench._unhandled_input(_key(KEY_J))
	check(diagnostics.labels_visible, "Key J shows the labels")
	workbench._unhandled_input(_key(KEY_G))
	check(not diagnostics.reference.is_empty(), "Key G marks the contact reference")
	workbench._unhandled_input(_key(KEY_Z))
	workbench._unhandled_input(_key(KEY_Z))
	for i in 90: await process_frame
	check(workbench.crouch_modifier.kneel > 0.9 and workbench.crouch_modifier.depth > 0.3 and status.text.contains("half-kneel"), "Key Z reaches the half-kneel preset through the modifier's own ramp (depth %.2f, kneel %.2f)" % [workbench.crouch_modifier.depth, workbench.crouch_modifier.kneel])
	check(String(diagnostics.latest.meta.state) == "aim" and float(diagnostics.latest.meta.kneel) > 0.9, "The readings report the kneeling pose")
	var camera_before: Vector3 = workbench.camera.position
	workbench._unhandled_input(_key(KEY_X))
	for i in 5: await process_frame
	check(workbench._diagnostic_view == 1 and workbench.camera.position.distance_to(camera_before) > 0.1, "Key X moves to a diagnostic camera view")
	workbench._unhandled_input(_key(KEY_Z))
	for i in 60: await process_frame
	check(workbench.crouch_modifier.depth < 0.01 and workbench.crouch_modifier.kneel < 0.01, "Key Z returns to standing")
	workbench._unhandled_input(_key(KEY_H))
	for i in 3: await process_frame
	check(not diagnostics.enabled and not is_instance_valid(diagnostics.overlay) and workbench.get_node("UI").find_child("HandContactReadout", true, false) == null, "Key H switches the diagnostics off and removes the overlay and readout")
	workbench._unhandled_input(_key(KEY_1))
	for i in 5: await process_frame
	check(workbench.animation_controller.current_state == &"rifle_idle", "Key 1 still returns to idle")
	workbench.queue_free()
	await process_frame
