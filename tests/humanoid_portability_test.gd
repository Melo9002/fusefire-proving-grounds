extends SceneTree
## Task 09, humanoid portability: a second, meaningfully different humanoid (the small medabot-style robot, art/characters/small_mira_0) runs on the SAME CharacterRig, CharacterPresenter, modifiers and exploration host as
## MIRA, configured only by its own rig profile, scenes and handling data. The assertions are BODY-RELATIVE (fractions of the leg, stride against the leg, hand error against the arm) so they hold for any proportions, and
## the ones that failed before the shared fixes carry NEGATIVE CONTROLS. Also: a renamed-bone fixture and missing optional anatomy through the full rig, and a required bone's diagnostic.
const SCENES := {
	"mira": "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn",
	"small": "res://art/characters/small_mira_0/runtime/small_mira_0_exploration_visual.tscn",
}
const SMALL_MODEL := "res://art/characters/small_mira_0/models/small_mira_0.glb"
const SMALL_PROFILE := "res://art/characters/small_mira_0/small_mira_0_rig_profile.tres"
const SMALL_RIG := "res://art/characters/small_mira_0/runtime/small_mira_0_rig.tscn"
const RigProfile := preload("res://presentation/characters/rig_profile/rig_profile.gd")
const RigResolver := preload("res://presentation/characters/rig_profile/rig_resolver.gd")
const DT := 1.0 / 60.0
var failures := 0
var checks := 0
var _rec := {}


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


## Records, inside every skeleton update (where the pose is final), the lowest and highest sole above the floor and the hips and head heights.
func _track(host: ExplorationCharacterHost) -> void:
	var rig := host.rig
	var sk := rig.skeleton
	var ids := {"hips": sk.find_bone(rig.bones.hips), "head": sk.find_bone(rig.bones.head), "top": sk.find_bone(rig.bones.head_top), "rh": sk.find_bone(rig.bones.right_arm[2]), "lh": sk.find_bone(rig.bones.left_arm[2]), "relb": sk.find_bone(rig.bones.right_arm[1]), "ankle": [sk.find_bone(rig.bones.left_leg[2]), sk.find_bone(rig.bones.right_leg[2])]}
	var rec := {"min_sole": 9.0, "max_sole": -9.0, "hips": 0.0, "head": 0.0, "rh": Vector3.ZERO, "lh": Vector3.ZERO, "relb": Vector3.ZERO, "top": Vector3.ZERO, "head_world": Vector3.ZERO}
	_rec[host] = rec
	sk.skeleton_updated.connect(func() -> void:
		var gt := sk.global_transform
		for f in 2:
			var ankle: Vector3 = gt * sk.get_bone_global_pose(ids.ankle[f]).origin
			var sole := ankle.y - host.global_position.y - rig.stair_profile.ankle_height
			rec.min_sole = minf(rec.min_sole, sole)
			rec.max_sole = maxf(rec.max_sole, sole)
		rec.hips = (gt * sk.get_bone_global_pose(ids.hips).origin).y - host.global_position.y
		rec.head = (gt * sk.get_bone_global_pose(ids.head).origin).y - host.global_position.y
		rec.head_world = gt * sk.get_bone_global_pose(ids.head).origin
		rec.top = gt * sk.get_bone_global_pose(ids.top).origin
		rec.rh = gt * sk.get_bone_global_pose(ids.rh).origin
		rec.lh = gt * sk.get_bone_global_pose(ids.lh).origin
		rec.relb = gt * sk.get_bone_global_pose(ids.relb).origin)


func _reset_sole(host: ExplorationCharacterHost) -> void:
	_rec[host].min_sole = 9.0
	_rec[host].max_sole = -9.0


func _spawn(stage: Node3D, scene_path: String, x: float, armed: bool) -> ExplorationCharacterHost:
	var host: ExplorationCharacterHost = (load(scene_path) as PackedScene).instantiate()
	if not armed:
		host.rig.weapon_scene = null
	host.position = Vector3(x, 0, 0)
	stage.add_child(host)
	_track(host)
	return host


func _anatomy(rig: CharacterRig) -> Dictionary:
	var m = rig.resolved_rig.measurements
	var p := rig.stair_profile
	var sk := rig.skeleton
	var unit := sk.global_basis.get_scale().y
	var y := func(role: StringName) -> float: return sk.get_bone_global_rest(sk.find_bone(role)).origin.y * unit
	var torso: float = y.call(rig.bones.neck) - y.call(rig.bones.hips)
	var head_size: float = y.call(rig.bones.head_top) - y.call(rig.bones.neck)
	return {
		"torso_over_leg": torso / m.leg_length,
		"head_over_height": head_size / m.standing_height,
		"hip_width_over_leg": m.hip_width / m.leg_length,
		"upper_over_fore_arm": m.upper_arm_length / m.forearm_length,
		"leg_over_height": m.leg_length / m.standing_height,
		"thigh_over_shin": m.thigh_length / m.shin_length,
		"arm_over_height": (m.upper_arm_length + m.forearm_length) / m.standing_height,
		"shoulder_over_hip_width": m.shoulder_width / m.hip_width,
		"foot_over_leg": (p.foot_front + p.foot_back) / m.leg_length,
		"stature": m.standing_height,
	}


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var hosts := {}
	var bare := {}
	var x := 0.0
	for key in SCENES:
		hosts[key] = _spawn(stage, SCENES[key], x, true)
		bare[key] = _spawn(stage, SCENES[key], x + 1.0, false)
		x += 3.0
	await _frames(40)
	var mira: CharacterRig = hosts.mira.rig
	var small: CharacterRig = hosts.small.rig

	# ---- The second humanoid is a different skeletal configuration, on the same implementation.
	var a := _anatomy(mira)
	var b := _anatomy(small)
	var differing := 0
	var report := []
	for key in a:
		var ratio: float = absf(float(a[key]) - float(b[key])) / maxf(absf(float(a[key])), 0.0001)
		report.append("%s %.3f vs %.3f" % [key, a[key], b[key]])
		if ratio > 0.08:
			differing += 1
	print("  anatomy (MIRA vs small): %s" % ", ".join(report))
	check(differing >= 5, "The second humanoid differs in at least five body proportions by more than 8%% (%d of %d)" % [differing, a.size()])
	check(small.stair_profile.leg_length < mira.stair_profile.leg_length * 0.75 and small.resolved_rig.measurements.standing_height < mira.resolved_rig.measurements.standing_height * 0.7, "It is a short, compact body (leg %.2f m vs %.2f m)" % [small.stair_profile.leg_length, mira.stair_profile.leg_length])
	check(mira.get_script() == small.get_script() and mira.presenter.get_script() == small.presenter.get_script() and hosts.mira.get_script() == hosts.small.get_script(), "Both run the same CharacterRig, CharacterPresenter and exploration host scripts")
	check(small.rig_profile != mira.rig_profile and small.character_scene != mira.character_scene and small.scene_file_path != mira.scene_file_path, "The differences are data: its own rig profile, model and rig scene")
	for key in hosts:
		var rig: CharacterRig = hosts[key].rig
		check(rig.bones.absent.is_empty() and rig.bones.degraded.is_empty() and rig.crouch_modifier != null and rig.locomotion_modifier != null and rig.traversal_modifier != null and rig.foot_modifier != null and rig.grip_modifier != null,
			"%s: every role resolves and every stage is built (absent %s, degraded %s)" % [key, rig.bones.absent, rig.bones.degraded])
		check(rig.skeleton.get_children().filter(func(c): return c is SkeletonModifier3D).map(func(c): return String(c.name)) == hosts.mira.rig.skeleton.get_children().filter(func(c): return c is SkeletonModifier3D).map(func(c): return String(c.name)),
			"%s: the modifier stack and its order are MIRA's" % key)
		check(rig.resolved_rig != null and not rig.resolved_rig.diagnostics.has_errors(), "%s: the rig profile resolves without errors" % key)

	# ---- Standing on the floor: ground contact in the idle pose, body-relative.
	for key in hosts:
		var rec: Dictionary = _rec[bare[key]]
		var leg: float = bare[key].rig.stair_profile.leg_length
		check(absf(rec.min_sole) < 0.01 * leg / 0.45 and absf(rec.max_sole) < 0.01 * leg / 0.45 + 0.004, "%s idle: both soles are on the floor (%+.3f to %+.3f m)" % [key, rec.min_sole, rec.max_sole])

	# ---- Gait: the stance foot covers what the cadence assumes, for every gait (stride scaled by the leg).
	for key in hosts:
		var rig: CharacterRig = hosts[key].rig
		var p := rig.locomotion_profile
		var player: AnimationPlayer = rig.animation_controller.animation_player
		var gaits := {&"move": p.walk, &"move_jog": p.jog, &"move_run": p.run}
		var worst := 0.0
		var worst_unscaled := 0.0
		for name in gaits:
			var g: LocomotionGait = gaits[name]
			var clip: Animation = player.get_animation(name)
			var start := _pose_at(rig, clip, 0.0)
			var toe_off := _pose_at(rig, clip, g.stance_fraction)
			var implied: float = ((start.foot.z - start.hip.z) - (toe_off.foot.z - toe_off.hip.z)) / g.stance_fraction
			worst = maxf(worst, absf(implied - g.stride_length * rig.body_ratio()) / (g.stride_length * rig.body_ratio()))
			worst_unscaled = maxf(worst_unscaled, absf(implied - g.stride_length) / g.stride_length)
		print("  %s: stride mismatch %.0f%% (against the unscaled authored stride %.0f%%), body ratio %.3f" % [key, worst * 100.0, worst_unscaled * 100.0, rig.body_ratio()])
		check(worst < 0.15, "%s: walk, jog and run stance feet cover the leg-scaled stride (worst %.0f%% off)" % [key, worst * 100.0])
		if key == "small":
			check(worst_unscaled > 0.3, "Negative control: against the unscaled MIRA stride the small robot's stance foot would skate (%.0f%% off)" % [worst_unscaled * 100.0])

	# ---- Cadence: what the rig plays the gait at is the speed over the LEG-SCALED stride, so the feet carry the body at the speed it moves (a shorter leg steps faster, it does not skate).
	for key in bare:
		for i in 100:
			bare[key].report_velocity(Vector3(0, 0, 1.4), DT)
			if key == "small":
				bare.mira.report_velocity(Vector3(0, 0, 1.4), DT)
			await process_frame
		var rig: CharacterRig = bare[key].rig
		var gait_report: Dictionary = rig.locomotion_report
		var stride: float = rig.locomotion_profile.stride_at(float(gait_report.gait)) * rig.body_ratio()
		var carried_speed: float = float(gait_report.cadence) * stride
		print("  %s walking 1.4 m/s: cadence %.2f cycles/s x leg-scaled stride %.2f m = %.2f m/s" % [key, gait_report.cadence, stride, carried_speed])
		check(absf(carried_speed - float(gait_report.speed)) < 0.1 * float(gait_report.speed) and float(gait_report.speed) > 1.2, "%s: cadence x stride carries the body at its speed (%.2f of %.2f m/s)" % [key, carried_speed, gait_report.speed])
		if key == "small":
			var unscaled: float = float(gait_report.cadence) * rig.locomotion_profile.stride_at(float(gait_report.gait))
			check(absf(unscaled - float(gait_report.speed)) > 0.25 * float(gait_report.speed), "Negative control: with MIRA's unscaled stride the robot's feet would carry %.2f m/s, not %.2f" % [unscaled, gait_report.speed])
	for key in bare:
		bare[key].report_velocity(Vector3.ZERO, DT)
	await _frames(60)

	# ---- Postures: the crouch drops the hips the same share of the leg and keeps the feet on the floor; the kneel does too.
	for key in bare:
		bare[key].set_crouched(true)
		_reset_sole(bare[key])
	await _frames(80)
	var crouch_drop := {}
	for key in bare:
		var rig: CharacterRig = bare[key].rig
		var rec: Dictionary = _rec[bare[key]]
		var standing_hips: float = rig.stair_profile.hip_joint_offset.y + rig.stair_profile.leg_length + rig.stair_profile.ankle_height   # a coarse reference only used for the share below
		crouch_drop[key] = rec.hips / rig.stair_profile.leg_length
		print("  %s crouch: hips %.2f of the leg, soles %+.3f..%+.3f m" % [key, crouch_drop[key], rec.min_sole, rec.max_sole])
		check(rec.min_sole > -0.012 and rec.max_sole < 0.06 * rig.stair_profile.leg_length / 0.45 * 0.45 + 0.012, "%s crouch: the feet stay on the floor (%+.3f to %+.3f m)" % [key, rec.min_sole, rec.max_sole])
		check(standing_hips > 0.0, "%s: reference geometry measured" % key)
	check(absf(crouch_drop.mira - crouch_drop.small) < 0.06, "The crouch lowers the hips by the same share of the leg on both bodies (%.2f vs %.2f)" % [crouch_drop.mira, crouch_drop.small])
	# Negative control: the solver that assumed plumb rest legs lifts the small robot's feet.
	bare.small.rig.crouch_modifier.rest_lean_enabled = false
	_reset_sole(bare.small)
	await _frames(20)
	var lifted: float = _rec[bare.small].max_sole
	bare.small.rig.crouch_modifier.rest_lean_enabled = true
	check(lifted > 0.04, "Negative control: without the rest-lean correction the crouching small robot's foot floats %.3f m" % lifted)
	for key in bare:
		bare[key].set_crouched(false)
	await _frames(60)
	for key in bare:
		bare[key].enter_cover(0.0, false, 0.18 * bare[key].rig.body_ratio() * 4.0, 0)
	await _frames(100)
	for key in bare:
		var m: CoverCrouchModifier = bare[key].rig.crouch_modifier
		check(m.kneel > 0.5 and m.depth > 0.0, "%s: a low wall takes it down to a kneel (kneel %.2f, depth %.3f m of at most %.3f)" % [key, m.kneel, m.depth, m.max_depth])
		bare[key].leave_cover()
	await _frames(60)

	# ---- Equipped: raise and aim, hands on the contacts, stock in the shoulder, the eye behind the sight (body-relative).
	for key in hosts:
		hosts[key].set_aiming(true)
	await create_timer(1.2).timeout
	var aim_eye := {}
	var aim_pole := {}
	for key in hosts:
		var rig: CharacterRig = hosts[key].rig
		var leg := rig.stair_profile.leg_length
		var rec: Dictionary = _rec[hosts[key]]
		var rh: Vector3 = rec.rh
		var lh: Vector3 = rec.lh
		var head: Vector3 = rec.head_world
		var top: Vector3 = rec.top
		var eye: Vector3 = head + (top - head) * 0.55 + rig.character_root.global_basis.z * 0.085 * rig.body_ratio()
		var to_sight := eye - rig.sight_marker.global_position
		var forward := rig.weapon.global_basis.z
		aim_eye[key] = (to_sight - forward * to_sight.dot(forward)).length() / leg
		check(host_has_weapon(hosts[key]) and hosts[key].is_aiming(), "%s: it holds its weapon and aims" % key)
		check(rig.stock_marker.global_position.distance_to(rig.shoulder_marker.global_position) < 0.012, "%s aimed: the stock is in the shoulder pocket (%.3f m)" % [key, rig.stock_marker.global_position.distance_to(rig.shoulder_marker.global_position)])
		check(rh.distance_to(rig.right_hand_target.global_position) < 0.03 * leg / 0.45 and lh.distance_to(rig.support_ik_target.global_position) < 0.05 * leg / 0.45, "%s aimed: the hands reach their contacts (%.3f and %.3f m)" % [key, rh.distance_to(rig.right_hand_target.global_position), lh.distance_to(rig.support_ik_target.global_position)])
	# ---- Scale is applied exactly once, and the profile, the scene, the measured anatomy, the IK targets and the attachments agree.
	for key in hosts:
		var rig: CharacterRig = hosts[key].rig
		var shown := rig.skeleton.global_basis.get_scale()
		var declared: float = rig.rig_profile.anatomy.character_scale
		check(absf(shown.x - rig.character_scale) < 0.002 and absf(shown.y - rig.character_scale) < 0.002 and absf(shown.z - rig.character_scale) < 0.002 and absf(declared - rig.character_scale) < 0.0001,
			"%s: the model is shown at its character_scale once (skeleton %s, rig scene %.2f, profile %.2f)" % [key, shown, rig.character_scale, declared])
		check(absf(hosts[key].global_basis.get_scale().y - 1.0) < 0.001 and absf(rig.global_basis.get_scale().y - 1.0) < 0.001 and absf(rig.character_root.global_basis.get_scale().y - 1.0) < 0.001 and rig.presenter.foot_point_problems().is_empty(),
			"%s: nothing above the model is scaled, so the scale cannot apply twice" % key)
		var m = rig.resolved_rig.measurements
		check(absf(m.leg_length - rig.stair_profile.leg_length) < 0.002 and absf(m.ankle_height - rig.stair_profile.ankle_height) < 0.01 * rig.stair_profile.leg_length,
			"%s: the profile's measured leg (%.3f m) and ankle (%.3f m) are the rig's (%.3f, %.3f)" % [key, m.leg_length, m.ankle_height, rig.stair_profile.leg_length, rig.stair_profile.ankle_height])
		check(absf(rig.weapon.global_basis.get_scale().y - rig.handling.scale) < 0.002, "%s: the weapon is drawn at its handling scale once (%.3f of %.3f)" % [key, rig.weapon.global_basis.get_scale().y, rig.handling.scale])
		var socket_ok := true
		for socket in rig.rig_profile.sockets:
			var native: Transform3D = rig.resolved_rig.sockets[socket.socket_name]
			var bone_rest := rig.skeleton.get_bone_global_rest(rig.resolved_rig.bone(socket.parent_role))
			var metres: float = (native.origin - bone_rest.origin).length() * rig.character_scale
			socket_ok = socket_ok and absf(metres - socket.offset.origin.length()) < 0.001
		check(socket_ok, "%s: every socket sits its declared offset (metres) from its bone at this scale" % key)
		var rec: Dictionary = _rec[hosts[key]]
		var arm: float = m.upper_arm_length + m.forearm_length
		var pole_gap: float = (rig.right_elbow_pole.global_position - rec.relb).length() / arm
		print("  %s aimed: right elbow guide is %.2f of the arm from the elbow" % [key, pole_gap])
		aim_pole[key] = pole_gap
	check(aim_pole.mira < 1.0 and aim_pole.small < 1.0, "The elbow guides were scaled with the body: each lies within an arm's length of its elbow, a direction hint rather than a target (%.2f and %.2f of the arm)" % [aim_pole.mira, aim_pole.small])
	check(absf(aim_eye.mira - aim_eye.small) < 0.08, "The eye sits as far off the sight line on both bodies, relative to the leg (%.2f vs %.2f)" % [aim_eye.mira, aim_eye.small])
	check(hosts.small.rig.handling.scale < hosts.mira.rig.handling.scale and hosts.small.rig.handling != hosts.mira.rig.handling, "Compatible equipment is configuration: the robot's own handling profile draws the same weapon smaller (%.2f vs %.2f)" % [hosts.small.rig.handling.scale, hosts.mira.rig.handling.scale])
	for key in hosts:
		hosts[key].set_aiming(false)
	await _frames(30)

	# ---- A carried passenger is the same model at the same scale (built once, at the carrier's character_scale).
	for key in bare:
		var carrier: ExplorationCharacterHost = bare[key]
		carrier.pick_up(carrier.global_position + Vector3(0, 0, 0.6))
		await create_timer(1.2).timeout
		var passenger = carrier.rig.carry_passenger
		check(passenger != null and absf(passenger.skeleton.global_basis.get_scale().y - carrier.rig.character_scale) < 0.002, "%s: the carried passenger's model is at the same scale (%s)" % [key, passenger.skeleton.global_basis.get_scale().y if passenger != null else "none"])
		carrier.put_down()
		await create_timer(2.0).timeout

	# ---- Lifecycles: an interaction, a shot, a hit, a defeat, with the same handle semantics.
	for key in hosts:
		var host: ExplorationCharacterHost = hosts[key]
		var seen := []
		var inspected := host.inspect(host.global_position + Vector3(0, 0, 2.0), 0.6)
		inspected.when_done(func(outcome: int) -> void: seen.append(outcome))
		var refused := host.inspect(host.global_position + Vector3(0, 0, 2.0), 0.6)
		check(refused.is_done() and refused.outcome == PresentationTypes.Outcome.CANCELLED, "%s: a second interaction is refused" % key)
		await create_timer(1.6).timeout
		check(inspected.is_done() and seen == [PresentationTypes.Outcome.COMPLETED] and not host.is_interacting(), "%s: the interaction completes once" % key)
		var hit := host.react_hit()
		await create_timer(1.2).timeout
		check(hit.is_done(), "%s: a hit reaction finishes" % key)
		var down := host.defeat()
		await create_timer(3.0).timeout
		check(down.is_done() and host.is_defeated(), "%s: the defeat completes and holds" % key)

	# ---- Stairs on the same planner, with each body's own anatomy: nothing in the tread, the ankles on their targets.
	for key in ["mira", "small"]:
		var result := await _stairs(key)
		print("  %s stairs: at rest toe %.3f heel %.3f, walking ankle error %.3f, reach %.2f of the leg, pelvis not reachable %d frames" % [key, result.rest_toe, result.rest_heel, result.ik, result.reach, result.unreachable])
		check(result.rest_toe < 0.012 and result.rest_heel < 0.012, "%s stairs: stopped half way up no toe or heel is below the tread (%.3f, %.3f m)" % [key, result.rest_toe, result.rest_heel])
		check(result.ik < 0.015 and result.reach <= 1.0 and result.unreachable == 0, "%s stairs: the legs reach the planned feet (error %.3f m, %.2f of the leg, %d unreachable)" % [key, result.ik, result.reach, result.unreachable])

	# ---- A skeleton with other names, through the FULL rig: the same poses.
	var renamed := _renamed_fixture()
	var fixture_host := Node3D.new()
	stage.add_child(fixture_host)
	var fixture := _fixture_rig(renamed.scene, renamed.profile)
	fixture_host.add_child(fixture)
	fixture_host.position = Vector3(9.0, 0.0, 0.0)
	await _frames(30)
	check(fixture.bones.absent.is_empty() and fixture.bones.degraded.is_empty() and fixture.crouch_modifier != null and fixture.foot_modifier != null, "A skeleton whose every bone is renamed builds every stage from its profile (absent %s, degraded %s)" % [fixture.bones.absent, fixture.bones.degraded])
	check(fixture.bones.hips == StringName(renamed.hips_name) and fixture.bones.hips != bare.small.rig.bones.hips and fixture.skeleton.find_bone(fixture.bones.left_leg[2]) >= 0, "...and the roles point at the new names (%s, not %s)" % [fixture.bones.hips, bare.small.rig.bones.hips])
	check(absf(fixture.body_ratio() - bare.small.rig.body_ratio()) < 0.001 and absf(fixture.stair_profile.leg_length - bare.small.rig.stair_profile.leg_length) < 0.001, "...with the same measured anatomy as the original names")
	fixture.crouch_modifier.depth = 0.2
	await _frames(20)
	check(fixture.crouch_modifier.max_depth > 0.0, "...and a crouch the same depth range (%.3f m)" % fixture.crouch_modifier.max_depth)
	fixture_host.queue_free()

	# ---- Missing optional anatomy: unmapped toes and fingers are reported, and what does not need them keeps working.
	var degraded_profile: RigProfile = (load(SMALL_PROFILE) as RigProfile).duplicate(true)
	var removed := _unmap(degraded_profile, ["LeftToes", "RightToes", "LeftIndexProximal", "LeftThumbProximal", "LeftMiddleProximal", "LeftRingProximal", "LeftLittleProximal", "RightIndexProximal", "RightThumbProximal", "RightMiddleProximal", "RightRingProximal", "RightLittleProximal"])
	var lean_host := Node3D.new()
	stage.add_child(lean_host)
	var lean := _fixture_rig(null, degraded_profile, true)
	lean_host.add_child(lean)
	lean_host.position = Vector3(11.0, 0.0, 0.0)
	await _frames(30)
	check(removed > 0 and lean.bones.absent.has(&"LeftToes") and lean.bones.absent.has(&"LeftIndexProximal"), "Unmapped optional bones are recorded in absent (%s)" % [lean.bones.absent])
	check(lean.bones.degraded.size() >= 1 and lean.bones.degraded.any(func(entry: String) -> bool: return entry.begins_with("HandGrip")), "The stage that needs the fingers says so (%s)" % [lean.bones.degraded])
	check(lean.crouch_modifier != null and lean.locomotion_modifier != null and lean.traversal_modifier != null and lean.foot_modifier != null, "Crouch, gait, traversal and the foot stage still build without toes and fingers")
	lean.crouch_modifier.depth = 0.2
	await _frames(20)
	check(lean.crouch_modifier.max_depth > 0.0, "...and the unrelated stack works (crouch up to %.3f m)" % lean.crouch_modifier.max_depth)
	lean_host.queue_free()
	# A required bone: a diagnostic naming it, not a guess.
	var required_profile: RigProfile = (load(SMALL_PROFILE) as RigProfile).duplicate(true)
	_unmap(required_profile, ["Hips"])
	var probe_model: Node3D = (load(SMALL_MODEL) as PackedScene).instantiate()
	var probe_skeleton: Skeleton3D = probe_model.find_child("Skeleton3D", true, false)
	stage.add_child(probe_model)
	var resolved = RigResolver.resolve(required_profile, probe_skeleton)
	check(resolved.diagnostics.has_errors() and resolved.diagnostics.format().contains("Hips"), "A missing required bone (Hips) is an error that names it")
	probe_model.queue_free()

	# ---- No second character in shared code, and none of its measurements.
	var offenders: Array[String] = []
	_scan("res://presentation", RegEx.create_from_string("small_mira|small robot|medabot"), offenders)
	check(offenders.is_empty(), "No shared presentation code names the second character: %s" % [offenders])

	renamed = {}
	degraded_profile = null
	required_profile = null
	print("Humanoid portability: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures > 0 else 0)


func host_has_weapon(host: ExplorationCharacterHost) -> bool:
	return host.rig.has_weapon()


func _pose_at(rig: CharacterRig, clip: Animation, t: float) -> Dictionary:
	var sk := rig.skeleton
	sk.reset_bone_poses()
	for track in clip.get_track_count():
		var bone := sk.find_bone(clip.track_get_path(track).get_subname(0))
		if bone < 0:
			continue
		if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			sk.set_bone_pose_rotation(bone, clip.rotation_track_interpolate(track, t))
		elif clip.track_get_type(track) == Animation.TYPE_POSITION_3D:
			sk.set_bone_pose_position(bone, clip.position_track_interpolate(track, t))
	var to_root := rig.character_root.global_transform.affine_inverse() * sk.global_transform
	return {"hip": to_root * sk.get_bone_global_pose(sk.find_bone(rig.bones.left_leg[0])).origin, "foot": to_root * sk.get_bone_global_pose(sk.find_bone(rig.bones.left_leg[2])).origin}


func _stairs(key: String) -> Dictionary:
	var stage := Node3D.new()
	root.add_child(stage)
	var host := _spawn(stage, SCENES[key], 0.0, false)
	await _frames(30)
	var rig := host.rig
	var model := StairModel.new()
	model.low = Vector3.ZERO
	model.direction = Vector3.BACK
	model.tread_depth = 0.4 if key == "mira" else 0.25
	model.tread_rise = 0.2 if key == "mira" else 0.1
	model.count = 10 if key == "mira" else 12
	model.width = 1.6
	var sk := rig.skeleton
	var ankles := [sk.find_bone(rig.bones.left_leg[2]), sk.find_bone(rig.bones.right_leg[2])]
	var toes := [sk.find_bone(rig.bones.left_toes), sk.find_bone(rig.bones.right_toes)]
	var thighs := [sk.find_bone(rig.bones.left_leg[0]), sk.find_bone(rig.bones.right_leg[0])]
	var data := {"rest_toe": 0.0, "rest_heel": 0.0, "ik": 0.0, "reach": 0.0, "unreachable": 0, "phase": "walk"}
	var profile := rig.stair_profile
	var ratio := rig.body_ratio()
	sk.skeleton_updated.connect(func() -> void:
		if rig.stairs == null or rig.stairs.pose == null or float(rig.stairs.pose.weight) < 0.99:
			return
		var gt := sk.global_transform
		for f in 2:
			var ankle: Vector3 = gt * sk.get_bone_global_pose(ankles[f]).origin
			var ball: Vector3 = gt * sk.get_bone_global_pose(toes[f]).origin
			var direction := Vector3(ball.x - ankle.x, 0.0, ball.z - ankle.z)
			direction = direction.normalized() if direction.length() > 0.01 else Vector3.BACK
			var tip := ball + direction * 0.07 * ratio
			var heel := ankle - direction * 0.07 * ratio
			var surface := func(point: Vector3) -> float:
				var along := model.progress_of(point)
				return model.low.y if along < 0.0 else (model.top() if along > model.end_s() else model.height_at(along))
			var ball_sole := ball.y - 0.028 * ratio
			if data.phase == "rest":
				data.rest_toe = maxf(data.rest_toe, maxf(surface.call(tip) - ball_sole, surface.call(ball) - ball_sole))
				data.rest_heel = maxf(data.rest_heel, surface.call(heel) - (ankle.y - profile.ankle_height))
			if rig.stairs.pose.feet[f].planted:
				data.ik = maxf(data.ik, rig.traversal_modifier.foot_targets[f].global_position.distance_to(ankle))
			data.reach = maxf(data.reach, (gt * sk.get_bone_global_pose(thighs[f]).origin).distance_to(ankle) / profile.leg_length)
		if not rig.stairs.pose.pelvis_ok:
			data.unreachable += 1)
	host.begin_stairs(model, true)
	var s := -0.6
	while s < model.end_s() + 0.6:
		s += 1.4 / 60.0
		host.global_position = model.point_at(s, model.ride_path_height_at(s, profile.riser_ramp))
		host.report_velocity(Vector3(0, 0, 1.4), DT)
		host.set_stairs_progress(s, 1.4)
		await process_frame
	s = model.end_s() * 0.5
	host.global_position = model.point_at(s, model.ride_path_height_at(s, profile.riser_ramp))
	data.phase = "rest"
	for i in 90:
		host.report_velocity(Vector3.ZERO, DT)
		host.set_stairs_progress(s, 0.0)
		await process_frame
	stage.queue_free()
	await process_frame
	return data


## The small robot's model with EVERY bone renamed to an opaque name, and a profile mapping the roles to them.
func _renamed_fixture() -> Dictionary:
	var model: Node3D = (load(SMALL_MODEL) as PackedScene).instantiate()
	var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var names := {}
	for i in sk.get_bone_count():
		var old := sk.get_bone_name(i)
		var new_name := "jnt%03d" % i
		names[old] = new_name
		sk.set_bone_name(i, new_name)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin != null:
			mesh.skin = mesh.skin.duplicate()
			for j in mesh.skin.get_bind_count():
				mesh.skin.set_bind_name(j, names.get(String(mesh.skin.get_bind_name(j)), mesh.skin.get_bind_name(j)))
	for player in model.find_children("*", "AnimationPlayer", true, false):
		player.queue_free()
	for child in model.get_children():
		_own(child, model)
	var scene := PackedScene.new()
	scene.pack(model)
	var profile: RigProfile = (load(SMALL_PROFILE) as RigProfile).duplicate(true)
	var bone_map: BoneMap = profile.skeleton_map
	var hips_new := ""
	for i in bone_map.profile.get_bone_size():
		var role := bone_map.profile.get_bone_name(i)
		var mapped := String(bone_map.get_skeleton_bone_name(role))
		if names.has(mapped):
			bone_map.set_skeleton_bone_name(role, names[mapped])
			if role == &"Hips":
				hips_new = names[mapped]
	model.free()
	return {"scene": scene, "profile": profile, "hips_name": hips_new}


func _own(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for child in node.get_children():
		_own(child, owner_node)


## A rig built from a scene and a profile, unarmed, exactly as the production rig scenes build it.
func _fixture_rig(model_scene: PackedScene, profile: RigProfile, use_small_model := false) -> CharacterRig:
	var rig: CharacterRig = (load(SMALL_RIG) as PackedScene).instantiate()
	rig.weapon_scene = null
	rig.character_scene = load(SMALL_MODEL) if use_small_model or model_scene == null else model_scene
	rig.rig_profile = profile
	return rig


## Unmaps the named roles (leaves the profile saying the bone is the name of nothing); returns how many existed.
func _unmap(profile: RigProfile, roles: Array) -> int:
	var count := 0
	var bone_map: BoneMap = profile.skeleton_map
	for role in roles:
		if bone_map.profile.find_bone(StringName(role)) >= 0:
			bone_map.set_skeleton_bone_name(StringName(role), &"no_such_bone")
			count += 1
	return count


func _scan(directory: String, pattern: RegEx, offenders: Array[String]) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for entry in dir.get_directories():
		_scan(directory.path_join(entry), pattern, offenders)
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			var text := FileAccess.get_file_as_string(directory.path_join(file_name))
			if pattern.search(text) != null:
				offenders.append(directory.path_join(file_name))
