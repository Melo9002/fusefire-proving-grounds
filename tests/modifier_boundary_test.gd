extends SceneTree
## The typed modifier boundary and the supported modifier callback (Task 07 package 4). Proves that the weapon-pose modifier works against nothing but its PoseTargetPlacer (a recording fake stands in
## for the rig), that it receives the engine's own pass delta (no second Engine.time_scale), that the engine applies modifier influence exactly once, that every modifier is safe at a zero delta,
## and that the traversal modifier is fed only a typed TraversalPoseInput which the rig keeps in step with its traversal and stair state. Structural headless checks.
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
var failures := 0
var checks := 0

func _initialize() -> void:
	Engine.max_fps = 60
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

class RecordingPlacer extends PoseTargetPlacer:
	var calls: Array[String] = []
	var deltas: Array[float] = []
	var is_carrying := false
	var is_holding := false
	func carrying() -> bool: return is_carrying
	func holding_traversal() -> bool: return is_holding
	func place_carry_targets(_r: Vector3, _l: Vector3) -> void: calls.append("carry")
	func observe_torso_frame(_chest: Basis, delta: float) -> void:
		calls.append("torso")
		deltas.append(delta)
	func place_weapon_targets(_s: Vector3) -> void: calls.append("weapon")
	func place_traversal_hand_targets() -> void: calls.append("hands")
	func guide_elbows(_r: Vector3, _l: Vector3, _c: Basis, carrying_now: bool) -> void: calls.append("elbows:%s" % carrying_now)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _locals(sk: Skeleton3D, bone: int) -> Transform3D:
	var parent := sk.get_bone_parent(bone)
	return sk.get_bone_global_pose(bone) if parent < 0 else sk.get_bone_global_pose(parent).affine_inverse() * sk.get_bone_global_pose(bone)

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var v: UnitVisualAdapter = VISUAL.instantiate()
	stage.add_child(v)
	await _frames(15)

	# ---- 1. The weapon-pose modifier against a fake placer: no rig involved.
	v.rig.weapon_pose_modifier.active = false
	var placer := RecordingPlacer.new()
	var binding := WeaponPoseBinding.new()
	binding.skeleton = v.rig.skeleton
	binding.right_shoulder_bone = v.rig.right_arm_bones[0]
	binding.left_arm_bones.assign(v.rig.left_arm_bones)
	binding.chest_bone = v.rig.torso_bone_name
	binding.character_root = v.rig.character_root
	binding.arm_ik = v.rig.arm_ik
	binding.support_target = v.rig.support_ik_target
	binding.crouch = v.rig.crouch_modifier
	binding.settings = WeaponPoseSettings.new()
	binding.placer = placer
	var modifier := WeaponPoseModifier.new()
	modifier.name = "FakeWeaponPose"
	check(modifier.setup(binding), "The modifier wires itself from a binding alone")
	v.rig.skeleton.add_child(modifier)
	var seen_delta: Array[float] = []
	modifier.modification_processed.connect(func() -> void: seen_delta.append(v.get_process_delta_time()))
	await _frames(6)
	check(modifier.passes >= 4 and placer.calls.size() >= 12, "It ran its passes against the fake (%d passes)" % modifier.passes)
	var frame_calls := placer.calls.slice(0, 3)
	check(frame_calls == ["torso", "weapon", "elbows:false"], "One ordinary pass asks the body for: the torso frame, the weapon targets, the elbow guidance, in that order: %s" % [frame_calls])
	# The delta it hands on is the engine's own for the pass, and is not scaled a second time.
	Engine.time_scale = 0.5
	placer.deltas.clear()
	seen_delta.clear()
	await _frames(8)
	Engine.time_scale = 1.0
	var delta_ok := placer.deltas.size() >= 5 and placer.deltas.size() == seen_delta.size()
	for i in mini(placer.deltas.size(), seen_delta.size()):
		delta_ok = delta_ok and absf(placer.deltas[i] - seen_delta[i]) < 0.00001
	check(delta_ok, "The pass delta is exactly the engine's frame delta, also under Engine.time_scale 0.5 (never scaled again)")
	# Carrying: the weapon targets are skipped and the carry contacts placed instead.
	placer.calls.clear()
	placer.is_carrying = true
	await _frames(3)
	check(placer.calls.slice(0, 2) == ["carry", "elbows:true"] and not placer.calls.has("weapon") and not placer.calls.has("torso"), "While carrying: carry targets then elbow guidance, no weapon targets, no torso frame: %s" % [placer.calls.slice(0, 3)])
	check(modifier.report.get("available", true) == false, "...and the support-reach report says it is unavailable")
	# A ladder holding the hands: the traversal hands are placed after the weapon targets.
	placer.is_carrying = false
	placer.is_holding = true
	placer.calls.clear()
	await _frames(3)
	check(placer.calls.slice(0, 4) == ["torso", "weapon", "hands", "elbows:true"], "Holding a ladder: weapon targets, then the traversal hands, then guidance as carrying: %s" % [placer.calls.slice(0, 4)])
	# Arm IK off: the modifier leaves everything alone.
	placer.is_holding = false
	placer.calls.clear()
	v.rig.arm_ik.active = false
	await _frames(3)
	check(placer.calls.is_empty(), "With the arm IK off the modifier asks for nothing")
	v.rig.arm_ik.active = true
	modifier.queue_free()
	v.rig.weapon_pose_modifier.active = true
	await process_frame

	# ---- 2. Every custom modifier is safe at a zero delta (the engine can call them with 0 right after the skeleton initialises).
	for child in v.rig.skeleton.get_children():
		if child is SkeletonModifier3D and child.has_method("_process_modification_with_delta"):
			child._process_modification_with_delta(0.0)
	check(true, "Every custom modifier runs at delta 0 without error")
	check(not FileAccess.get_file_as_string("res://presentation/characters/rig/modifiers/weapon_pose_modifier.gd").contains("_process_modification()"), "The deprecated callback is gone from the weapon-pose modifier")

	# ---- 3. Influence is applied by the engine, once. The locomotion twist at influence 0.5 is half of the twist at influence 1.
	v.set_process(false)   # nothing else rewrites the twist while measuring
	var hips := v.rig.skeleton.find_bone("mixamorig_Hips")
	var input := RigInput.new()
	input.twist_degrees = 40.0
	var angles := {}
	for influence in [0.0, 0.5, 1.0]:
		v.rig.locomotion_modifier.influence = influence
		v.rig.locomotion_modifier.apply_input(input)
		var latest := [Transform3D.IDENTITY]
		var grab := func() -> void: latest[0] = _locals(v.rig.skeleton, hips)
		v.rig.skeleton.skeleton_updated.connect(grab)
		await _frames(3)
		v.rig.skeleton.skeleton_updated.disconnect(grab)
		angles[influence] = latest[0].basis.get_rotation_quaternion()
	var base: Quaternion = angles[0.0]
	var full := rad_to_deg(base.angle_to(angles[1.0]))
	var half := rad_to_deg(base.angle_to(angles[0.5]))
	check(full > 20.0, "Setup: the full twist turns the hips (%.1f degrees)" % full)
	check(absf(half - full * 0.5) < full * 0.08, "Influence 0.5 gives half the turn (%.1f of %.1f degrees): the engine applies influence once, the modifier does not apply it again" % [half, full])
	v.rig.locomotion_modifier.influence = 1.0
	v.rig.locomotion_modifier.apply_input(RigInput.new())
	v.set_process(true)

	# ---- 4. The traversal modifier is fed typed input that the rig keeps in step with its state.
	var tm := v.rig.traversal_modifier
	var ti: TraversalPoseInput = tm.input
	check(ti.mode == TraversalPoseInput.Mode.NONE, "Idle: the traversal input is NONE")
	v.rig.begin_traversal(&"ladder", 3.0, 1)
	check(ti.mode == TraversalPoseInput.Mode.LADDER and not ti.solved, "A ladder begins: LADDER, nothing solved yet")
	v.rig.set_traversal_progress(1.5)
	check(ti.solved and is_equal_approx(ti.weight, v.rig.ladder.pose.weight) and ti.hips_local.is_equal_approx(v.rig.ladder.pose.hips) and ti.feet_local[1].is_equal_approx(v.rig.ladder.pose.feet[1]), "The published input is the solved ladder pose (weight %.2f)" % ti.weight)
	await _frames(3)
	check(v.rig.leg_ik.active and v.rig.foot_targets[0].global_position.distance_to(v.rig.character_root.to_global(ti.feet_local[0])) < 0.0005, "The modifier places the foot target from the typed input alone")
	var model := StairModel.from_links(Vector3.ZERO, Vector3(0, 0, 1), 1.0, 1.0, 2, 3)
	v.rig.begin_stairs(model, true)
	v.rig.set_stair_progress(0.8, 1.2)
	check(ti.mode == TraversalPoseInput.Mode.LADDER, "A ladder takes precedence over stairs, as before")
	v.rig.end_traversal()
	check(ti.mode == TraversalPoseInput.Mode.STAIRS and ti.solved and is_equal_approx(ti.pelvis_height, v.rig.stairs.pose.pelvis_height) and ti.ankles_world[0].is_equal_approx(v.rig.stairs.pose.feet[0].position) and ti.stair_profile == v.rig.stair_profile, "With the ladder over, the stair pose is published (pelvis %.3f)" % ti.pelvis_height)
	v.rig.end_stairs()
	check(ti.mode == TraversalPoseInput.Mode.NONE and ti.weight == 0.0, "Ending everything clears the input: nothing of the traversal is left")
	await _frames(3)
	check(not v.rig.leg_ik.active and tm.weight == 0.0, "...and the leg IK is off again")

	print("Modifier boundary: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
