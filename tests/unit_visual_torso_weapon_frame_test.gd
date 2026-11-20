extends SceneTree
## Torso-relative weapon frame (animation improvement 05A). While the chest kicks (a shot, a hit) the aimed weapon
## turns with the chest about the stock, so the weapon and both shoulders move as one body: the support hand keeps its
## grip. Settled poses, relaxed handling, turning and cover yaw are untouched. `torso_frame_enabled = false` restores the
## root-frame weapon and is the A/B reference here. Production UnitVisualAdapter path, sampled after the skeleton's
## modifiers.

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

const POSES := [
	["standing", "aim", -1.0],
	["crouch", "cover_low", 1.15],
	["half-kneel", "cover_low", 0.5],
]

func _set_pose(rig: UnitVisualAdapter, state: String, cover: float, aimed: bool) -> void:
	rig._aim_held = aimed
	rig._aim_release_left = 1000000.0
	if cover > 0.0:
		rig.last_cover_contact = {"type": MapCellData.CoverType.LOW, "height": cover, "direction": Vector3.FORWARD}
	else:
		rig.last_cover_contact = {"type": MapCellData.CoverType.NONE, "direction": Vector3.ZERO}
	rig.animation_controller.play(StringName(state))

func _settle() -> void:
	for i in 40: await process_frame
	await create_timer(1.6).timeout
	for i in 3: await process_frame

func _stock_error(rig: UnitVisualAdapter, sample: Dictionary) -> float:
	var pocket: Vector3 = (sample.hands[0].shoulder as Vector3) + rig.character_root.global_basis * rig.shoulder_contact_offset
	return (sample.points.stock as Vector3).distance_to(pocket)

func _angle(basis: Basis) -> float:
	return rad_to_deg(basis.get_rotation_quaternion().get_angle())

## Plays `kick` ("shoot" or "hit") from a settled aimed pose and returns the worst values over the next 0.5 s.
func _kick(rig: UnitVisualAdapter, diagnostics: HandContactDiagnostics, kick: StringName) -> Dictionary:
	var base: Dictionary = diagnostics.latest
	var base_support: Vector3 = base.hands[1].palm_in_weapon_frame
	var base_dominant: Vector3 = base.hands[0].palm_in_weapon_frame
	if kick == &"hit":
		rig.present_hit()
	else:
		rig.animation_controller.play(kick)
	var worst := {"support_shift": 0.0, "dominant_shift": 0.0, "dominant_wrist": 0.0, "support_wrist": 0.0, "stock": 0.0, "frame_angle": 0.0, "muzzle_vs_frame": 0.0}
	var t0: float = rig._presentation_clock
	while rig._presentation_clock - t0 < 0.5:
		await process_frame
		var s: Dictionary = diagnostics.latest
		worst.support_shift = maxf(worst.support_shift, (s.hands[1].palm_in_weapon_frame as Vector3).distance_to(base_support) * 1000.0)
		worst.dominant_shift = maxf(worst.dominant_shift, (s.hands[0].palm_in_weapon_frame as Vector3).distance_to(base_dominant) * 1000.0)
		worst.dominant_wrist = maxf(worst.dominant_wrist, float(s.hands[0].wrist_to_ik_target) * 1000.0)
		worst.support_wrist = maxf(worst.support_wrist, float(s.hands[1].wrist_to_ik_target) * 1000.0)
		worst.stock = maxf(worst.stock, _stock_error(rig, s) * 1000.0)
		worst.frame_angle = maxf(worst.frame_angle, _angle(rig.torso_frame))
		worst.muzzle_vs_frame = maxf(worst.muzzle_vs_frame, rig.weapon_alignment_error_degrees())
	return worst

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	stage.add_child(rig)
	rig.position = Vector3.ZERO
	for i in 30: await process_frame
	var diagnostics := HandContactDiagnostics.attach(rig)
	diagnostics.set_readout_visible(false)
	diagnostics.set_enabled(true)

	var order: Array[String] = []
	for child in rig.skeleton.get_children():
		if child is SkeletonModifier3D: order.append(String(child.name))
	check(order == ["Locomotion", "CoverCrouch", "Traversal", "TraversalLegIK", "WeaponPose", "WeaponArmIK", "HandGrip"], "Modifier order is unchanged: %s" % str(order))
	check(rig.torso_frame_enabled and rig.skeleton.find_bone(rig.torso_bone_name) >= 0, "The torso bone resolves on this skeleton (%s)" % rig.torso_bone_name)

	# Settled poses: the torso frame is the root frame, relaxed handling is identical with the frame on or off.
	var settled := {}
	for enabled in [true, false]:
		rig.torso_frame_enabled = enabled
		_set_pose(rig, "rifle_idle", -1.0, false)
		await _settle()
		var s: Dictionary = diagnostics.latest
		settled[enabled] = {"weapon": rig.weapon.global_transform, "dominant": s.hands[0].wrist, "support": s.hands[1].wrist, "frame": _angle(rig.torso_frame)}
	rig.torso_frame_enabled = true
	check(float(settled[true].frame) < 0.001 and float(settled[false].frame) < 0.001, "Relaxed: the torso frame is the root frame")
	check((settled[true].weapon as Transform3D).origin.distance_to((settled[false].weapon as Transform3D).origin) < 0.0001 and _angle((settled[true].weapon as Transform3D).basis * (settled[false].weapon as Transform3D).basis.inverse()) < 0.01, "Relaxed weapon placement is identical with the frame on and off")
	check((settled[true].dominant as Vector3).distance_to(settled[false].dominant) < 0.0001 and (settled[true].support as Vector3).distance_to(settled[false].support) < 0.0001, "Relaxed hands are identical with the frame on and off")

	var results := {}
	for pose in POSES:
		var label: String = pose[0]
		for enabled in [true, false]:
			rig.torso_frame_enabled = enabled
			_set_pose(rig, pose[1], pose[2], true)
			await _settle()
			var s: Dictionary = diagnostics.latest
			check(_angle(rig.torso_frame) < 0.01, "%s aim (frame %s): settled, the torso frame is the root frame" % [label, enabled])
			check(_stock_error(rig, s) < 0.0005, "%s aim: the stock is in the shoulder pocket before the shot (%.2f mm)" % [label, _stock_error(rig, s) * 1000.0])
			var muzzle_before: float = rig.weapon_alignment_error_degrees()
			var shot := await _kick(rig, diagnostics, &"shoot")
			results[[label, enabled]] = shot
			print("  %-10s frame %-5s support palm shift %.1f mm | support wrist %.1f | dominant palm shift %.2f | stock worst %.1f mm | frame turn %.1f deg" % [label, enabled, shot.support_shift, shot.support_wrist, shot.dominant_shift, shot.stock, shot.frame_angle])
			check(muzzle_before < 0.1, "%s aim: muzzle on the firing direction before the shot (%.2f deg)" % [label, muzzle_before])
			if enabled:
				check(float(shot.frame_angle) > 1.0, "%s: the weapon turns with the chest during the kick (%.1f deg)" % [label, shot.frame_angle])
				check(float(shot.dominant_wrist) < 0.001 * 1000.0, "%s: the firing wrist stays on its target (%.2f mm)" % [label, shot.dominant_wrist])
				check(float(shot.dominant_shift) < 2.0, "%s: the firing hand keeps its grip (%.2f mm)" % [label, shot.dominant_shift])
				check(float(shot.stock) < 6.0, "%s: the stock stays in the pocket within the recoil's own 5 mm (%.1f mm)" % [label, shot.stock])
				check(float(shot.muzzle_vs_frame) < 0.5, "%s: the muzzle follows the torso frame (%.2f deg)" % [label, shot.muzzle_vs_frame])
			_set_pose(rig, pose[1], pose[2], true)   # the unit returns to its aimed pose, as the attack's release does
			await create_timer(0.4).timeout
			check(_angle(rig.torso_frame) < 0.1, "%s: after the kick the frame is back to the root frame (%.2f deg)" % [label, _angle(rig.torso_frame)])
	var baseline_standing: Dictionary = results[["standing", false]]
	var baseline_crouch: Dictionary = results[["crouch", false]]
	var baseline_kneel: Dictionary = results[["half-kneel", false]]
	check(float(baseline_standing.support_shift) > 20.0 and float(baseline_crouch.support_shift) > 25.0 and float(baseline_kneel.support_shift) > 25.0, "Reference (frame off): the old drift is reproduced (%.1f / %.1f / %.1f mm)" % [baseline_standing.support_shift, baseline_crouch.support_shift, baseline_kneel.support_shift])
	check(float(results[["standing", true]].support_shift) < 2.0, "Standing support-hand drift %.1f mm (was %.1f)" % [results[["standing", true]].support_shift, baseline_standing.support_shift])
	check(float(results[["crouch", true]].support_shift) < 6.0, "Crouch support-hand drift %.1f mm (was %.1f)" % [results[["crouch", true]].support_shift, baseline_crouch.support_shift])
	check(float(results[["half-kneel", true]].support_shift) < 6.0, "Half-kneel support-hand drift %.1f mm (was %.1f)" % [results[["half-kneel", true]].support_shift, baseline_kneel.support_shift])
	for label in ["standing", "crouch", "half-kneel"]:
		check(float(results[[label, true]].support_shift) < 0.25 * float(results[[label, false]].support_shift), "%s: the drift fell by more than three quarters" % label)

	# A hit reaction while aimed: the weapon and hands move with the torso instead of detaching.
	rig.torso_frame_enabled = true
	_set_pose(rig, "aim", -1.0, true)
	await _settle()
	var hit := await _kick(rig, diagnostics, &"hit")
	rig.torso_frame_enabled = false
	_set_pose(rig, "aim", -1.0, true)
	await _settle()
	var hit_off := await _kick(rig, diagnostics, &"hit")
	rig.torso_frame_enabled = true
	print("  hit while aimed: support palm shift %.1f mm (frame off %.1f), dominant %.2f (off %.2f), frame turn %.1f deg" % [hit.support_shift, hit_off.support_shift, hit.dominant_shift, hit_off.dominant_shift, hit.frame_angle])
	check(float(hit.frame_angle) < 0.01, "A hit reaction does not turn the weapon frame (%.2f deg): it keeps the root-frame weapon" % hit.frame_angle)
	check(absf(float(hit.support_shift) - float(hit_off.support_shift)) < 0.3 and absf(float(hit.dominant_shift) - float(hit_off.dominant_shift)) < 0.3, "Hit reactions behave exactly as before (support %.2f vs %.2f mm)" % [hit.support_shift, hit_off.support_shift])
	await create_timer(1.6).timeout
	check(_angle(rig.torso_frame) < 0.01, "After the hit the frame is settled")

	# Turning and cover-facing changes turn the root, not the torso frame.
	_set_pose(rig, "aim", -1.0, true)
	await _settle()
	var weapon_before: Basis = rig.weapon.global_basis
	rig.rotation.y += deg_to_rad(70.0)
	var worst_turn_frame := 0.0
	for i in 20:
		await process_frame
		worst_turn_frame = maxf(worst_turn_frame, _angle(rig.torso_frame))
	check(worst_turn_frame < 0.01, "Turning the character does not appear in the torso frame (%.3f deg)" % worst_turn_frame)
	var turned := rig.weapon.global_basis * weapon_before.inverse()
	check(absf(_angle(turned) - 70.0) < 0.2, "The weapon turns with the character (%.2f of 70 deg)" % _angle(turned))
	rig.rotation.y -= deg_to_rad(70.0)

	# Switching it off restores the root-frame weapon exactly.
	rig.torso_frame_enabled = false
	await process_frame
	check(_angle(rig.torso_frame) < 0.0001, "Switched off, the frame is the root frame")
	print("Torso weapon frame: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
