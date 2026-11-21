extends SceneTree
## Swivel-preserving elbow guidance (animation improvement 05B). While aiming, the elbow poles are built each pass from the
## shoulder, the wrist target and the chest's down, with the bend-plane swivel the standing aim has. Compared with the
## fixed standing-space guides (`elbow_guidance_enabled = false`, the A/B reference) the right elbow keeps its direction
## relative to the torso when the body drops, without moving a hand target. Production TacticalCharacterAdapter path, sampled
## after the skeleton's modifiers.

var failures := 0
var checks := 0
var rig: TacticalCharacterAdapter
var skeleton: Skeleton3D
var diagnostics: HandContactDiagnostics
var latest := {}

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

func _set_pose(pose: Array, aimed := true) -> void:
	rig.presenter.aim.held = aimed
	rig.presenter.aim.release_left = 1000000.0
	if float(pose[2]) > 0.0:
		rig.last_cover_contact = {"type": MapCellData.CoverType.LOW, "height": pose[2], "direction": Vector3.FORWARD}
	else:
		rig.last_cover_contact = {"type": MapCellData.CoverType.NONE, "direction": Vector3.ZERO}
	rig.rig.animation_controller.play(StringName(pose[1]))

func _settle() -> void:
	for i in 40: await process_frame
	await create_timer(1.6).timeout
	for i in 3: await process_frame

## The chest's world orientation as the guidance defines it: the root frame turned by the chest's change from rest.
func _chest_world() -> Basis:
	var chest := skeleton.find_bone(rig.rig.torso_bone_name)
	var sb := skeleton.global_basis.orthonormalized()
	var deviation := skeleton.get_bone_global_pose(chest).basis.orthonormalized() * skeleton.get_bone_global_rest(chest).basis.orthonormalized().inverse()
	return sb * deviation * sb.inverse() * rig.rig.character_root.global_basis.orthonormalized()

func _on_updated() -> void:
	var chest := _chest_world()
	var xf := skeleton.global_transform
	var out := {}
	for i in 2:
		var side := "Right" if i == 0 else "Left"
		var s: Vector3 = xf * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_%sArm" % side)).origin
		var e: Vector3 = xf * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_%sForeArm" % side)).origin
		var w: Vector3 = xf * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_%sHand" % side)).origin
		var axis := (w - s).normalized()
		var bend := (e - s) - axis * (e - s).dot(axis)
		var hand: Dictionary = diagnostics.latest.hands[i] if not diagnostics.latest.is_empty() else {}
		out[i] = {
			"swivel": CharacterRig.elbow_swivel_degrees(s, e, w, -chest.y),
			"height": (chest.inverse() * (e - s)).y * 100.0,
			"elbow_local": chest.inverse() * (e - s),
			"offset_from_line": bend.length() * 100.0,
			"wrist_err": float(hand.get("wrist_to_ik_target", 0.0)) * 1000.0,
			"reach_margin": float(hand.get("reach_margin", 0.0)) * 1000.0,
			"flexion": float(hand.get("elbow_angle_deg", 0.0)),
		}
	latest = out

func _angle_gap(a: float, b: float) -> float:
	return absf(wrapf(a - b, -180.0, 180.0))

func _stock_error() -> float:
	var s: Dictionary = diagnostics.latest
	var pocket: Vector3 = (s.hands[0].shoulder as Vector3) + rig.rig.character_root.global_basis * rig.rig.shoulder_contact_offset
	return (s.points.stock as Vector3).distance_to(pocket) * 1000.0

## Plays the transition and returns the worst per-frame change over the next 3 s of presentation time.
func _transition(from_pose: Array, to_pose: Array) -> Dictionary:
	_set_pose(from_pose)
	await _settle()
	_set_pose(to_pose)
	var prev := latest.duplicate(true)
	var worst := {"swivel_jump": 0.0, "elbow_jump": 0.0, "pole_jump": 0.0, "wrist_err": 0.0, "max_height": -99.0}
	var prev_pole: Vector3 = rig.rig.right_elbow_pole.global_position
	var t0: float = rig.presenter.time
	while rig.presenter.time - t0 < 3.0:
		await process_frame
		for i in 2:
			if float(latest[i].offset_from_line) > 3.0 and float(prev[i].offset_from_line) > 3.0:
				worst.swivel_jump = maxf(worst.swivel_jump, _angle_gap(latest[i].swivel, prev[i].swivel))
			worst.elbow_jump = maxf(worst.elbow_jump, ((latest[i].elbow_local as Vector3) - (prev[i].elbow_local as Vector3)).length() * 1000.0)
			worst.wrist_err = maxf(worst.wrist_err, latest[i].wrist_err)
		worst.max_height = maxf(worst.max_height, latest[0].height)
		worst.pole_jump = maxf(worst.pole_jump, rig.rig.right_elbow_pole.global_position.distance_to(prev_pole) * 1000.0)
		prev_pole = rig.rig.right_elbow_pole.global_position
		prev = latest.duplicate(true)
	return worst

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	rig = load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as TacticalCharacterAdapter
	stage.add_child(rig)
	for i in 30: await process_frame
	skeleton = rig.rig.skeleton
	diagnostics = HandContactDiagnostics.attach(rig.rig)
	diagnostics.set_readout_visible(false)
	diagnostics.set_enabled(true)
	skeleton.skeleton_updated.connect(_on_updated)

	var order: Array[String] = []
	for child in skeleton.get_children():
		if child is SkeletonModifier3D: order.append(String(child.name))
	check(order == ["Locomotion", "CoverCrouch", "Traversal", "TraversalLegIK", "WeaponPose", "WeaponArmIK", "HandGrip"], "Modifier order is unchanged: %s" % str(order))
	check(rig.rig.elbow_guidance_enabled, "Elbow guidance is on by default")

	# Relaxed handling is not touched: poles, wrists and weapon are identical with the guidance on and off.
	var relaxed := {}
	for enabled in [true, false]:
		rig.rig.elbow_guidance_enabled = enabled
		_set_pose(["rifle_idle", "rifle_idle", -1.0], false)
		await _settle()
		relaxed[enabled] = {"pole_r": rig.rig.right_elbow_pole.position, "pole_l": rig.rig.left_elbow_pole.position, "weapon": rig.rig.weapon.global_transform, "r": latest[0].elbow_local, "l": latest[1].elbow_local}
	rig.rig.elbow_guidance_enabled = true
	check((relaxed[true].pole_r as Vector3).distance_to(relaxed[false].pole_r) < 0.0001 and (relaxed[true].pole_l as Vector3).distance_to(relaxed[false].pole_l) < 0.0001, "Relaxed: the elbow poles are the existing ones")
	check((relaxed[true].r as Vector3).distance_to(relaxed[false].r) < 0.0001 and (relaxed[true].l as Vector3).distance_to(relaxed[false].l) < 0.0001, "Relaxed: the elbows are where they were")

	# Settled aimed poses: guidance vs the fixed guides.
	var res := {}
	for enabled in [true, false]:
		rig.rig.elbow_guidance_enabled = enabled
		for pose in POSES:
			_set_pose(pose)
			await _settle()
			res[[pose[0], enabled]] = {"arm": latest.duplicate(true), "diag": diagnostics.latest.duplicate(true), "stock": _stock_error()}
			var r: Dictionary = latest[0]
			print("  %-10s guidance %-5s right elbow height %.1f cm swivel %.0f deg | flexion %.0f | wrist %.3f mm margin %.1f mm | support wrist %.2f mm" % [pose[0], enabled, r.height, r.swivel, r.flexion, r.wrist_err, r.reach_margin, latest[1].wrist_err])
	rig.rig.elbow_guidance_enabled = true
	var stand_swivel: float = res[["standing", true]].arm[0].swivel
	var stand_legacy: float = res[["standing", false]].arm[0].swivel
	check(_angle_gap(stand_swivel, stand_legacy) < 4.0, "Standing aim keeps the existing bend plane (%.1f vs %.1f deg)" % [stand_swivel, stand_legacy])
	var legacy_height: Dictionary = {}
	for pose in POSES:
		var label: String = pose[0]
		var now: Dictionary = res[[label, true]].arm
		var before: Dictionary = res[[label, false]].arm
		legacy_height[label] = before[0].height
		check(_angle_gap(now[0].swivel, stand_swivel) < 3.0, "%s: the right elbow keeps the standing swivel (%.1f vs %.1f deg)" % [label, now[0].swivel, stand_swivel])
		check(float(now[0].wrist_err) < 0.01, "%s: the firing wrist is on its target (%.3f mm)" % [label, now[0].wrist_err])
		check(float(now[1].wrist_err) <= float(before[1].wrist_err) + 0.05, "%s: the support wrist is no further from its target (%.2f vs %.2f mm)" % [label, now[1].wrist_err, before[1].wrist_err])
		check(absf(float(now[0].reach_margin) - float(before[0].reach_margin)) < 0.5 and absf(float(now[1].reach_margin) - float(before[1].reach_margin)) < 0.5, "%s: reach margins are unchanged (the guidance only chooses the bend plane)" % label)
		check(absf(float(now[0].flexion) - float(before[0].flexion)) < 0.5 and absf(float(now[1].flexion) - float(before[1].flexion)) < 0.5, "%s: elbow flexion is unchanged (%.1f / %.1f deg)" % [label, now[0].flexion, now[1].flexion])
		check(absf(float(res[[label, true]].stock) - float(res[[label, false]].stock)) < 0.1, "%s: the stock is where it was in the pocket (%.2f mm)" % [label, res[[label, true]].stock])
	check(_angle_gap(res[["crouch", false]].arm[0].swivel, stand_legacy) > 20.0 and _angle_gap(res[["half-kneel", false]].arm[0].swivel, stand_legacy) > 20.0, "Reference (guidance off): the fixed guide twists the elbow plane by more than 20 deg when the body drops")
	check(float(res[["crouch", false]].arm[0].height) - float(res[["crouch", true]].arm[0].height) > 6.0, "Crouch: the right elbow sits more than 6 cm lower relative to the shoulder (%.1f vs %.1f cm)" % [res[["crouch", true]].arm[0].height, res[["crouch", false]].arm[0].height])
	check(float(res[["half-kneel", false]].arm[0].height) - float(res[["half-kneel", true]].arm[0].height) > 12.0, "Half-kneel: the right elbow sits more than 12 cm lower (%.1f vs %.1f cm)" % [res[["half-kneel", true]].arm[0].height, res[["half-kneel", false]].arm[0].height])
	check(float(res[["half-kneel", true]].arm[0].height) < 0.0, "Half-kneel: the right elbow is below the shoulder, as when standing (%.1f cm)" % res[["half-kneel", true]].arm[0].height)
	# The support arm is nearly straight in every pose: its swivel is not claimed, only that nothing got worse.
	for pose in POSES:
		check(float(res[[pose[0], true]].arm[1].offset_from_line) < 4.0, "%s: the near-straight support arm keeps a small bend offset (%.1f cm)" % [pose[0], res[[pose[0], true]].arm[1].offset_from_line])

	# Shots: the elbow plane holds while the chest kicks, and the contacts the previous work fixed stay fixed.
	for pose in POSES:
		_set_pose(pose)
		await _settle()
		var base_support: Vector3 = diagnostics.latest.hands[1].palm_in_weapon_frame
		var worst := {"swivel": 0.0, "support": 0.0, "stock": 0.0, "wrist": 0.0}
		var base_swivel: float = latest[0].swivel
		rig.rig.animation_controller.play(&"shoot")
		var t0: float = rig.presenter.time
		while rig.presenter.time - t0 < 0.5:
			await process_frame
			worst.swivel = maxf(worst.swivel, _angle_gap(latest[0].swivel, base_swivel))
			worst.support = maxf(worst.support, (diagnostics.latest.hands[1].palm_in_weapon_frame as Vector3).distance_to(base_support) * 1000.0)
			worst.stock = maxf(worst.stock, _stock_error())
			worst.wrist = maxf(worst.wrist, latest[0].wrist_err)
		print("  %-10s shot: worst swivel change %.1f deg, support palm shift %.1f mm, stock %.1f mm, firing wrist %.3f mm" % [pose[0], worst.swivel, worst.support, worst.stock, worst.wrist])
		check(float(worst.swivel) < 12.0, "%s shot: the elbow plane follows the chest without flipping (%.1f deg)" % [pose[0], worst.swivel])
		check(float(worst.support) < (2.0 if pose[0] == "standing" else 6.0), "%s shot: support-hand drift is still within the torso-frame result (%.1f mm)" % [pose[0], worst.support])
		check(float(worst.stock) < 6.0, "%s shot: the stock stays in the pocket (%.1f mm)" % [pose[0], worst.stock])
		check(float(worst.wrist) < 0.01, "%s shot: the firing wrist stays on its target (%.3f mm)" % [pose[0], worst.wrist])

	# Transitions: no flips, no snapping poles, hand targets as accurate as before.
	for pair in [[0, 1, "aim to crouch"], [1, 2, "crouch to half-kneel"], [2, 0, "half-kneel to aim"], [0, 2, "aim to half-kneel"]]:
		rig.rig.elbow_guidance_enabled = true
		var now := await _transition(POSES[pair[0]], POSES[pair[1]])
		rig.rig.elbow_guidance_enabled = false
		var before := await _transition(POSES[pair[0]], POSES[pair[1]])
		rig.rig.elbow_guidance_enabled = true
		print("  %-22s swivel jump %.2f deg (was %.2f) | elbow jump %.1f mm (was %.1f) | pole jump %.1f mm (was %.1f) | wrist err %.2f (was %.2f) | highest right elbow %.1f cm (was %.1f)" % [pair[2], now.swivel_jump, before.swivel_jump, now.elbow_jump, before.elbow_jump, now.pole_jump, before.pole_jump, now.wrist_err, before.wrist_err, now.max_height, before.max_height])
		check(float(now.swivel_jump) < 3.0, "%s: no bend-plane flip (%.2f deg per frame)" % [pair[2], now.swivel_jump])
		check(float(now.elbow_jump) <= float(before.elbow_jump) + 3.0, "%s: the elbow moves no more abruptly than before (%.1f vs %.1f mm per frame)" % [pair[2], now.elbow_jump, before.elbow_jump])
		check(float(now.pole_jump) < 30.0, "%s: the pole never snaps (%.1f mm per frame)" % [pair[2], now.pole_jump])
		check(float(now.wrist_err) <= float(before.wrist_err) + 0.1, "%s: hand targets are as accurate as before (%.2f vs %.2f mm)" % [pair[2], now.wrist_err, before.wrist_err])
	print("Elbow guidance: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
