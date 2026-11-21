extends SceneTree
## Deterministic pose trace for behavioural-equivalence checks across animation refactors (Task 07 package 4). Drives the production visual through fixed scenarios and writes, for every frame,
## the character-space transform of selected bones and the IK target positions, as JSON. Compare two traces (before / after a change) with a numerical tolerance.
## Run with a fixed frame rate so every delta is identical:
##   godot_console --headless --fixed-fps 60 --path . --script res://tools/quality/pose_trace.gd -- <output.json>
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
const BONES := ["Hips", "Spine", "Spine2", "Neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot", "RightHandIndex1", "RightHandThumb1", "LeftHandIndex1", "LeftHandThumb1"]
const DT := 1.0 / 60.0
var traces := {}
var _frame_record: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _snapshot(v: UnitVisualAdapter) -> Dictionary:
	var to_root: Transform3D = v.character_root.global_transform.affine_inverse() * v.skeleton.global_transform
	var bones := {}
	for name in BONES:
		var index := v.skeleton.find_bone("mixamorig_" + name)
		if index < 0:
			continue
		var pose := to_root * v.skeleton.get_bone_global_pose(index)
		var q := pose.basis.orthonormalized().get_rotation_quaternion()
		bones[name] = [pose.origin.x, pose.origin.y, pose.origin.z, q.x, q.y, q.z, q.w]
	var targets := {}
	var root_inverse: Transform3D = v.character_root.global_transform.affine_inverse()
	for pair in [["right_hand", v.right_hand_target], ["support_hand", v.support_ik_target], ["right_elbow", v.right_elbow_pole], ["left_elbow", v.left_elbow_pole],
			["foot_0", v.foot_targets[0] if v.foot_targets.size() > 0 else null], ["foot_1", v.foot_targets[1] if v.foot_targets.size() > 1 else null],
			["knee_0", v.knee_poles[0] if v.knee_poles.size() > 0 else null], ["knee_1", v.knee_poles[1] if v.knee_poles.size() > 1 else null], ["weapon", v.weapon]]:
		var node: Node3D = pair[1]
		if node != null and is_instance_valid(node):
			var p: Vector3 = root_inverse * node.global_position
			targets[pair[0]] = [p.x, p.y, p.z]
	var passenger := []
	if is_instance_valid(v.carry_passenger):
		var pt: Transform3D = root_inverse * v.carry_passenger.global_transform
		var pq := pt.basis.orthonormalized().get_rotation_quaternion()
		passenger = [pt.origin.x, pt.origin.y, pt.origin.z, pq.x, pq.y, pq.z, pq.w]
	return {"bones": bones, "targets": targets, "leg_ik": v.leg_ik.active if is_instance_valid(v.leg_ik) else false, "arm_ik": v.arm_ik.active, "stowed": v.is_weapon_stowed(),
		"crouch": v.crouch_modifier.depth, "kneel": v.crouch_modifier.kneel, "yaw": v.character_root.rotation.y,
		"passenger": passenger, "phase": String(v.rescue_interaction.phase_name()), "rescue_time": v.rescue_interaction.time, "position": [v.position.x, v.position.y, v.position.z]}

func _scenario(tag: String, frames: int, step: Callable, setup := Callable()) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var v: UnitVisualAdapter = VISUAL.instantiate()
	stage.add_child(v)
	for i in 20:
		await process_frame
	if setup.is_valid():
		setup.call(v)
	_frame_record = {}
	var capture := func() -> void: _frame_record = _snapshot(v)
	v.skeleton.skeleton_updated.connect(capture)
	var rows: Array = []
	for i in frames:
		step.call(v, i)
		await process_frame
		rows.append(_frame_record.duplicate(true))
	v.skeleton.skeleton_updated.disconnect(capture)
	traces[tag] = rows
	stage.queue_free()
	await process_frame

func _cover(v: UnitVisualAdapter, height: float, type := MapCellData.CoverType.LOW) -> void:
	v.last_cover_contact = {"type": type, "height": height, "direction": Vector3.FORWARD}
	v.animation_controller.play(&"cover_low" if type == MapCellData.CoverType.LOW else &"cover_high")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "pose_trace.json"
	await _scenario("locomotion", 200, func(v: UnitVisualAdapter, i: int) -> void:
		var speed := 1.3 if i < 70 else (4.0 if i < 130 else 0.0)
		var heading := Vector3(0, 0, 1) if i < 100 else Vector3(1, 0, 1).normalized()
		if speed > 0.0:
			v.update_locomotion(heading * speed, DT))
	await _scenario("cover_twist_aim", 160, func(v: UnitVisualAdapter, i: int) -> void:
		if i == 0: _cover(v, 1.1)
		if i == 20: v.begin_turn(deg_to_rad(70.0))
		if i == 70: v.request_readiness(&"trace", WeaponReadiness.Level.AIMED)
		if i == 130: v.release_readiness(&"trace"))
	await _scenario("kneel_aim", 140, func(v: UnitVisualAdapter, i: int) -> void:
		if i == 0: _cover(v, 0.4)
		if i == 50: v.request_readiness(&"trace", WeaponReadiness.Level.AIMED))
	await _scenario("full_cover_aim", 140, func(v: UnitVisualAdapter, i: int) -> void:
		if i == 0: _cover(v, 2.0, MapCellData.CoverType.FULL)
		if i == 50: v.request_readiness(&"trace", WeaponReadiness.Level.AIMED))
	await _scenario("aim_hold", 150, func(v: UnitVisualAdapter, i: int) -> void:
		if i == 10: v.request_readiness(&"trace", WeaponReadiness.Level.AIMED)
		if i == 100: v.release_readiness(&"trace"))
	await _scenario("stow", 120, func(v: UnitVisualAdapter, i: int) -> void:
		if i == 20: v.stow_weapon()
		if i == 80: v.unstow_weapon())
	var model := StairModel.from_links(Vector3.ZERO, Vector3(0, 0, 1), 1.0, 1.0, 2, 3)
	await _scenario("stairs", 180, func(v: UnitVisualAdapter, i: int) -> void:
		if i == 5: v.begin_stairs(model, true)
		if i >= 5 and i < 150:
			v.update_locomotion(Vector3(0, 0, 1.2), DT)
			v.set_stair_progress(clampf(float(i - 5) * 0.012, 0.0, model.end_s()), 1.2)
		if i == 150: v.end_stairs())
	await _scenario("ladder", 200, func(v: UnitVisualAdapter, i: int) -> void:
		if i == 5: v.begin_traversal(&"ladder", 3.0, 1)
		if i >= 5 and i < 160: v.set_traversal_progress(clampf(float(i - 5) * 0.017, 0.0, 2.6))
		if i == 160: v.end_traversal())
	await _scenario("carry", 160, func(v: UnitVisualAdapter, i: int) -> void:
		if i == 20: v.begin_carry()
		if i >= 20 and i < 100: v.update_locomotion(Vector3(0, 0, 1.0), DT)
		if i == 110: v.end_carry())
	# Rescue (Task 07 package 5): a whole pickup (start, contact, attachment, settle), the carry walking, and a whole release. 3.0 s pickup, 3.0 s release at 60 fps.
	await _scenario("rescue_pickup", 260, func(v: UnitVisualAdapter, i: int) -> void:
		if i == 10: v.begin_pickup(v.character_root.global_position + v.character_root.global_basis.orthonormalized().z * 1.0)
		if i >= 200 and i < 250: v.update_locomotion(Vector3(0, 0, 1.0), DT))
	await _scenario("rescue_release", 360, func(v: UnitVisualAdapter, i: int) -> void:
		if i == 0: v.begin_carry()
		if i >= 5 and i < 60: v.update_locomotion(Vector3(0, 0, 1.0), DT)
		if i == 90: v.begin_release())
	await _scenario("rescue_cover_return", 330, func(v: UnitVisualAdapter, i: int) -> void:
		if i == 0: _cover(v, 1.1)
		if i == 30: v.begin_pickup(v.character_root.global_position + v.character_root.global_basis.orthonormalized().z * 1.0)
		if i == 100: v.end_carry()
		if i == 101: _cover(v, 1.1))
	await _scenario("rescue_cancel", 200, func(v: UnitVisualAdapter, i: int) -> void:
		if i == 10: v.begin_pickup(v.character_root.global_position + v.character_root.global_basis.orthonormalized().z * 1.0)
		if i == 90: v.end_carry())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(traces))
	file.close()
	print("pose_trace: wrote %d scenarios to %s" % [traces.size(), path])
	quit(0)
