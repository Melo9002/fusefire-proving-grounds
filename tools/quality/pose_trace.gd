extends SceneTree
## Deterministic pose trace for behavioural-equivalence checks across animation refactors (Task 07 package 4). Drives the production visual through fixed scenarios and writes, for every frame,
## the character-space transform of selected bones and the IK target positions, as JSON. Compare two traces (before / after a change) with a numerical tolerance.
## Run with a fixed frame rate so every delta is identical:
##   godot_console --headless --fixed-fps 60 --path . --script res://tools/quality/pose_trace.gd -- <output.json>
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
const UNIT_SCENE := preload("res://units/tactical_unit.tscn")
const BONES := ["Hips", "Spine", "Spine2", "Neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot", "RightHandIndex1", "RightHandThumb1", "LeftHandIndex1", "LeftHandThumb1"]
const DT := 1.0 / 60.0
var traces := {}
var _frame_record: Dictionary = {}
var meta := {}

func _initialize() -> void:
	_run.call_deferred()

## Attack bookkeeping is read through whichever owner the code under test has (the adapter before Task 07 package 6, the presenter after), so one trace compares both.
func _attack_phase(v: TacticalCharacterAdapter) -> int:
	if v.presenter.get("attack") != null:
		return int(v.presenter.attack.phase)
	return int(v.get("attack_phase"))

func _attack_timeline(v: TacticalCharacterAdapter) -> Dictionary:
	if v.presenter.get("attack") != null:
		return v.presenter.attack.timeline
	return v.get("attack_timeline")

func _snapshot(v: TacticalCharacterAdapter) -> Dictionary:
	var to_root: Transform3D = v.rig.character_root.global_transform.affine_inverse() * v.rig.skeleton.global_transform
	var bones := {}
	for name in BONES:
		var index := v.rig.skeleton.find_bone("mixamorig_" + name)
		if index < 0:
			continue
		var pose := to_root * v.rig.skeleton.get_bone_global_pose(index)
		var q := pose.basis.orthonormalized().get_rotation_quaternion()
		bones[name] = [pose.origin.x, pose.origin.y, pose.origin.z, q.x, q.y, q.z, q.w]
	var targets := {}
	var root_inverse: Transform3D = v.rig.character_root.global_transform.affine_inverse()
	for pair in [["right_hand", v.rig.right_hand_target], ["support_hand", v.rig.support_ik_target], ["right_elbow", v.rig.right_elbow_pole], ["left_elbow", v.rig.left_elbow_pole],
			["foot_0", v.rig.foot_targets[0] if v.rig.foot_targets.size() > 0 else null], ["foot_1", v.rig.foot_targets[1] if v.rig.foot_targets.size() > 1 else null],
			["knee_0", v.rig.knee_poles[0] if v.rig.knee_poles.size() > 0 else null], ["knee_1", v.rig.knee_poles[1] if v.rig.knee_poles.size() > 1 else null], ["weapon", v.rig.weapon]]:
		var node: Node3D = pair[1]
		if node != null and is_instance_valid(node):
			var p: Vector3 = root_inverse * node.global_position
			targets[pair[0]] = [p.x, p.y, p.z]
	var passenger := []
	if is_instance_valid(v.rig.carry_passenger):
		var pt: Transform3D = root_inverse * v.rig.carry_passenger.global_transform
		var pq := pt.basis.orthonormalized().get_rotation_quaternion()
		passenger = [pt.origin.x, pt.origin.y, pt.origin.z, pq.x, pq.y, pq.z, pq.w]
	return {"bones": bones, "targets": targets, "leg_ik": v.rig.leg_ik.active if is_instance_valid(v.rig.leg_ik) else false, "arm_ik": v.rig.arm_ik.active, "stowed": v.rig.is_weapon_stowed(),
		"crouch": v.rig.crouch_modifier.depth, "kneel": v.rig.crouch_modifier.kneel, "yaw": v.rig.character_root.rotation.y, "node_yaw": v.rig.rotation.y,
		"passenger": passenger, "state": String(v.get_presentation_state()), "attack_phase": _attack_phase(v), "aim_blend": v.rig.aim_blend, "readiness": int(v.readiness_level()), "phase": String(v.rig.rescue_interaction.phase_name()), "rescue_time": v.rig.rescue_interaction.time, "position": [v.position.x, v.position.y, v.position.z], "world": _world(v)}

func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.000001), snappedf(v.y, 0.000001), snappedf(v.z, 0.000001)]

## World-space positions (Task 07 package 9, the foot-point convention): the visual, the character root, the hips and both feet, the weapon when there is one. Compared only for the unit-hosted scenarios,
## where the unit's own placement fixes the floor; a bare visual's world position depends on where its test stage puts it.
func _world(v: TacticalCharacterAdapter) -> Dictionary:
	var result := {"visual": _v(v.global_position), "root": _v(v.rig.character_root.global_position)}
	for pair in [["hips", "Hips"], ["left_foot", "LeftFoot"], ["right_foot", "RightFoot"], ["left_hand", "LeftHand"], ["right_hand", "RightHand"]]:
		var index := v.rig.skeleton.find_bone("mixamorig_" + pair[1])
		if index >= 0:
			result[pair[0]] = _v(v.rig.skeleton.global_transform * v.rig.skeleton.get_bone_global_pose(index).origin)
	if is_instance_valid(v.rig.weapon):
		result["weapon"] = _v(v.rig.weapon.global_position)
	return result

## A scenario hosted by a production TacticalUnit standing on a floor at y = 0 (its body centre one metre above), driven by the engine's own frames.
func _unit_scenario(tag: String, frames: int, step: Callable) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var unit := UNIT_SCENE.instantiate() as TacticalUnit
	unit.show_world_hud = false
	stage.add_child(unit)
	unit.position = Vector3(0.0, unit.standing_height, 0.0)
	for i in 20:
		await process_frame
	var v: TacticalCharacterAdapter = unit.visual_adapter
	_frame_record = {}
	var capture := func() -> void: _frame_record = _snapshot(v)
	v.rig.skeleton.skeleton_updated.connect(capture)
	var rows: Array = []
	for i in frames:
		step.call(unit, i)
		await process_frame
		var row := _frame_record.duplicate(true)
		row["unit"] = _v(unit.global_position)
		rows.append(row)
	v.rig.skeleton.skeleton_updated.disconnect(capture)
	traces[tag] = rows
	meta[tag] = {"fired": false, "forced": false, "cancelled": false, "fire_t": -1.0, "end_t": -1.0, "phases": []}
	stage.queue_free()
	await process_frame

func _scenario(tag: String, frames: int, step: Callable, setup := Callable()) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var v: TacticalCharacterAdapter = VISUAL.instantiate()
	stage.add_child(v)
	v.position = Vector3(0.0, -1.0, 0.0)   # the stage puts the feet at y = -1, as the scene itself used to: the trace must not depend on where the scene's own origin is
	for i in 20:
		await process_frame
	if setup.is_valid():
		setup.call(v)
	_frame_record = {}
	var capture := func() -> void: _frame_record = _snapshot(v)
	v.rig.skeleton.skeleton_updated.connect(capture)
	var rows: Array = []
	for i in frames:
		step.call(v, i)
		await process_frame
		rows.append(_frame_record.duplicate(true))
	v.rig.skeleton.skeleton_updated.disconnect(capture)
	traces[tag] = rows
	var timeline := _attack_timeline(v)
	var phases := []
	for p in timeline.get("phases", []):
		phases.append([int(p.phase), snappedf(float(p.t), 0.0001)])
	meta[tag] = {"fired": timeline.get("fired", false), "forced": timeline.get("forced", false), "cancelled": timeline.get("cancelled", false), "fire_t": snappedf(float(timeline.get("fire_t", -1.0)), 0.0001),
		"end_t": snappedf(float(timeline.get("end_t", -1.0)), 0.0001), "phases": phases}
	stage.queue_free()
	await process_frame

func _place(v: TacticalCharacterAdapter) -> Vector3:
	return v.rig.character_root.global_position + v.rig.character_root.global_basis.orthonormalized().z * 1.0

func _cover(v: TacticalCharacterAdapter, height: float, type := MapCellData.CoverType.LOW) -> void:
	v.last_cover_contact = {"type": type, "height": height, "direction": Vector3.FORWARD}
	v.rig.animation_controller.play(&"cover_low" if type == MapCellData.CoverType.LOW else &"cover_high")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "pose_trace.json"
	await _scenario("locomotion", 200, func(v: TacticalCharacterAdapter, i: int) -> void:
		var speed := 1.3 if i < 70 else (4.0 if i < 130 else 0.0)
		var heading := Vector3(0, 0, 1) if i < 100 else Vector3(1, 0, 1).normalized()
		if speed > 0.0:
			v.update_locomotion(heading * speed, DT))
	await _scenario("cover_twist_aim", 160, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 0: _cover(v, 1.1)
		if i == 20: v.rig.begin_turn(deg_to_rad(70.0))
		if i == 70: v.request_readiness(&"trace", WeaponReadiness.Level.AIMED)
		if i == 130: v.release_readiness(&"trace"))
	await _scenario("kneel_aim", 140, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 0: _cover(v, 0.4)
		if i == 50: v.request_readiness(&"trace", WeaponReadiness.Level.AIMED))
	await _scenario("full_cover_aim", 140, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 0: _cover(v, 2.0, MapCellData.CoverType.FULL)
		if i == 50: v.request_readiness(&"trace", WeaponReadiness.Level.AIMED))
	await _scenario("aim_hold", 150, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 10: v.request_readiness(&"trace", WeaponReadiness.Level.AIMED)
		if i == 100: v.release_readiness(&"trace"))
	await _scenario("stow", 120, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 20: v.rig.stow_weapon()
		if i == 80: v.rig.unstow_weapon())
	var model := StairModel.from_links(Vector3.ZERO, Vector3(0, 0, 1), 1.0, 1.0, 2, 3)
	await _scenario("stairs", 180, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 5: v.rig.begin_stairs(model, true)
		if i >= 5 and i < 150:
			v.update_locomotion(Vector3(0, 0, 1.2), DT)
			v.rig.set_stair_progress(clampf(float(i - 5) * 0.012, 0.0, model.end_s()), 1.2)
		if i == 150: v.rig.end_stairs())
	await _scenario("ladder", 200, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 5: v.rig.begin_traversal(&"ladder", 3.0, 1)
		if i >= 5 and i < 160: v.rig.set_traversal_progress(clampf(float(i - 5) * 0.017, 0.0, 2.6))
		if i == 160: v.rig.end_traversal())
	await _scenario("carry", 160, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 0: v.preview_carrying = true
		if i == 20: v.rig.begin_carry()
		if i >= 20 and i < 100: v.update_locomotion(Vector3(0, 0, 1.0), DT)
		if i == 110: v.rig.end_carry())
	# Rescue (Task 07 package 5): a whole pickup (start, contact, attachment, settle), the carry walking, and a whole release. 3.0 s pickup, 3.0 s release at 60 fps.
	await _scenario("rescue_pickup", 260, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 0: v.preview_carrying = true   # without it the lift clock never advances (the adapter only runs it for a carrier)
		if i == 10: v.rig.begin_pickup(v.rig.character_root.global_position + v.rig.character_root.global_basis.orthonormalized().z * 1.0)
		if i >= 200 and i < 250: v.update_locomotion(Vector3(0, 0, 1.0), DT))
	await _scenario("rescue_release", 360, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 0: v.preview_carrying = true   # without it the lift clock never advances (the adapter only runs it for a carrier)
		if i == 0: v.rig.begin_carry()
		if i >= 5 and i < 60: v.update_locomotion(Vector3(0, 0, 1.0), DT)
		if i == 90: v.rig.begin_release())
	await _scenario("rescue_cover_return", 330, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 0: v.preview_carrying = true   # without it the lift clock never advances (the adapter only runs it for a carrier)
		if i == 0: _cover(v, 1.1)
		if i == 30: v.rig.begin_pickup(v.rig.character_root.global_position + v.rig.character_root.global_basis.orthonormalized().z * 1.0)
		if i == 100: v.rig.end_carry()
		if i == 101: _cover(v, 1.1))
	await _scenario("rescue_cancel", 200, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 0: v.preview_carrying = true   # without it the lift clock never advances (the adapter only runs it for a carrier)
		if i == 10: v.rig.begin_pickup(v.rig.character_root.global_position + v.rig.character_root.global_basis.orthonormalized().z * 1.0)
		if i == 90: v.rig.end_carry())
	# Combat presentation (Task 07 package 6): attack from several starting poses, repeated and interrupted attacks, aim hold and release, hit and defeat in the middle of other actions.
	var ahead := func(v: TacticalCharacterAdapter) -> Vector3: return v.global_position + v.global_basis.z * 6.0
	var side := func(v: TacticalCharacterAdapter) -> Vector3: return v.global_position + v.global_basis.x * 5.0 + v.global_basis.z * 2.0
	await _scenario("attack_standing", 200, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 20: v.present_attack(ahead.call(v)))
	await _scenario("attack_aimed", 200, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 5: v.present_aim()
		if i == 60: v.present_attack(ahead.call(v)))
	await _scenario("attack_cover_low", 220, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 0: _cover(v, 1.1)
		if i == 30: v.present_attack(side.call(v)))
	await _scenario("attack_full_cover", 220, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 0: _cover(v, 2.0, MapCellData.CoverType.FULL)
		if i == 30: v.present_attack(side.call(v)))
	await _scenario("attack_repeat", 260, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 20: v.present_attack(ahead.call(v))
		if i == 24: v.present_attack(ahead.call(v))
		if i == 140: v.present_attack(side.call(v)))
	await _scenario("hit_idle", 160, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 20: v.present_hit()
		if i == 90: v.present_hit())
	await _scenario("hit_during_aim", 200, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 5: v.present_aim()
		if i == 40: v.present_hit())
	await _scenario("hit_during_attack", 220, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 20: v.present_attack(ahead.call(v))
		if i == 32: v.present_hit())
	await _scenario("defeat_during_attack", 180, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 20: v.present_attack(ahead.call(v))
		if i == 31: v.present_defeat()
		if i == 50: v.present_defeat())
	await _scenario("defeat_during_aim", 160, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 5: v.present_aim()
		if i == 40: v.present_defeat())
	await _scenario("aim_release", 200, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 10: v.present_aim()
		if i == 150: v.present_hit())
	await _scenario("rescue_defeat", 200, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 0: v.preview_carrying = true
		if i == 10: v.rig.begin_pickup(_place(v))
		if i == 70: v.present_defeat()
		if i == 72: v.present_carry_released())
	await _scenario("rescue_hit_idle_timer", 260, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 0: v.preview_carrying = true
		if i == 10: v.present_pickup()
		if i == 40: v.present_hit())
	# Facing (Task 07 package 7): a facing change toward a world point from idle and from cover (absorbed into the cover yaw), explicit repeats, a facing change while an attack is staged and while a
	# hit reaction holds, and the velocity-follow turn of a walk (the "locomotion" scenario). The node yaw and the visual root yaw are both recorded.
	var east := func(v: TacticalCharacterAdapter) -> Vector3: return v.global_position + Vector3(5.0, 0.0, 1.0)
	var west := func(v: TacticalCharacterAdapter) -> Vector3: return v.global_position + Vector3(-4.0, 0.0, -3.0)
	await _scenario("face_idle", 200, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 20: v.face_world_position(east.call(v))
		if i == 24: v.face_world_position(east.call(v))
		if i == 70: v.face_world_position(west.call(v))
		if i == 71: v.face_world_position(v.global_position))
	await _scenario("face_cover_low", 220, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 0: _cover(v, 1.1)
		if i == 30: v.face_world_position(east.call(v))
		if i == 90: v.face_world_position(west.call(v)))
	await _scenario("face_cover_aimed", 240, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 0: _cover(v, 2.0, MapCellData.CoverType.FULL)
		if i == 20: v.request_readiness(&"trace", WeaponReadiness.Level.AIMED)
		if i == 50: v.face_world_position(east.call(v))
		if i == 120: v.present_attack(west.call(v)))
	await _scenario("face_during_hit", 200, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 20: v.present_hit()
		if i == 30: v.face_world_position(east.call(v)))
	await _scenario("walk_turn", 240, func(v: TacticalCharacterAdapter, i: int) -> void:
		var heading := Vector3(0, 0, 1) if i < 60 else (Vector3(1, 0, 0) if i < 120 else Vector3(-1, 0, -1).normalized())
		if i < 180: v.update_locomotion(heading * 2.5, DT)
		if i == 200: v.face_world_position(east.call(v)))
	# Traversal transitions (Task 07 package 8): a descent, a ladder and a stair walk ended midway, a ladder taking precedence over a stair walk, and stairs descended.
	await _scenario("ladder_down", 200, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 5: v.rig.begin_traversal(&"ladder", 3.0, -1)
		if i >= 5 and i < 160: v.rig.set_traversal_progress(clampf(2.6 - float(i - 5) * 0.017, 0.0, 3.0))
		if i == 160: v.rig.end_traversal())
	await _scenario("ladder_interrupted", 160, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 5: v.rig.begin_traversal(&"ladder", 3.0, 1)
		if i >= 5 and i < 70: v.rig.set_traversal_progress(clampf(float(i - 5) * 0.017, 0.0, 2.6))
		if i == 70: v.rig.end_traversal())
	await _scenario("stairs_interrupted", 160, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 5: v.rig.begin_stairs(model, true)
		if i >= 5 and i < 70:
			v.update_locomotion(Vector3(0, 0, 1.2), DT)
			v.rig.set_stair_progress(clampf(float(i - 5) * 0.012, 0.0, model.end_s()), 1.2)
		if i == 70: v.rig.end_stairs())
	await _scenario("stairs_down", 180, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 5: v.rig.begin_stairs(model, false)
		if i >= 5 and i < 150:
			v.update_locomotion(Vector3(0, 0, 1.2), DT)
			v.rig.set_stair_progress(clampf(model.end_s() - float(i - 5) * 0.012, 0.0, model.end_s()), 1.2)
		if i == 150: v.rig.end_stairs())
	await _scenario("ladder_over_stairs", 200, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 5: v.rig.begin_traversal(&"ladder", 3.0, 1)
		if i == 30: v.rig.begin_stairs(model, true)
		if i >= 5 and i < 100: v.rig.set_traversal_progress(clampf(float(i - 5) * 0.017, 0.0, 2.6))
		if i >= 30 and i < 160: v.rig.set_stair_progress(clampf(float(i - 30) * 0.012, 0.0, model.end_s()), 1.2)
		if i == 100: v.rig.end_traversal()
		if i == 160: v.rig.end_stairs())
	# Unit-hosted scenarios (Task 07 package 9): the foot-point. A tactical unit stands on a floor at y = 0 idle, walks, faces and defeats; the world positions of its visual, hips, feet, hands and weapon are
	# compared across the foot-point migration, and the unit's own world position shows nothing moved.
	await _unit_scenario("unit_idle_walk", 200, func(unit: TacticalUnit, i: int) -> void:
		if i == 60: unit.move_along_path(PackedVector3Array([unit.global_position, unit.global_position + Vector3(0, 0, 2.5), unit.global_position + Vector3(2.0, 0, 2.5)]))
		if i == 150: unit.visual_adapter.face_world_position(unit.global_position + Vector3(-3, 0, 1)))
	await _unit_scenario("unit_aim_defeat", 200, func(unit: TacticalUnit, i: int) -> void:
		if i == 10: unit.visual_adapter.present_aim()
		if i == 60: unit.present_attack(unit.global_position + Vector3(0, 0, 6))
		if i == 140: unit.visual_adapter.present_defeat())
	await _unit_scenario("unit_carry", 240, func(unit: TacticalUnit, i: int) -> void:
		if i == 0: unit.visual_adapter.preview_carrying = true
		if i == 10: unit.visual_adapter.rig.begin_pickup(unit.visual_adapter.rig.character_root.global_position + unit.visual_adapter.rig.character_root.global_basis.orthonormalized().z)
		if i == 130: unit.visual_adapter.rig.begin_release())
	# Timelines the code under test recorded for the attacks (phases and times in presentation seconds): the shot and release timing the frame-by-frame rows cannot show on their own.
	traces["__meta"] = meta
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(traces))
	file.close()
	print("pose_trace: wrote %d scenarios (plus the __meta attack timelines) to %s" % [traces.size() - 1, path])
	quit(0)
