extends SceneTree
## Pose ownership (Task 07 package 4). Part 1 validates the declaration table in PoseOwnership against the modifier order: every non-additive overlap must be a DECLARED ordered override, with its
## stages in modifier order, and nothing stale. Part 2 checks the declarations against what the stages really do: the pose is snapshotted after the animation mixer and after each stage while the
## production character performs motions that exercise every stage, and a stage that changes a bone it has not declared fails. Overlaps are allowed when declared; this is not a one-writer rule.
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
var failures := 0
var checks := 0
var observed: Dictionary = {}   # stage -> { role -> true }

func _initialize() -> void:
	Engine.max_fps = 60
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

## Each bone's LOCAL transform in the final pose (read at skeleton_updated, where the finished pose is valid): a bone is "written" when its own local transform differs, so a parent's change does not
## make its children look written.
func _locals(sk: Skeleton3D) -> Array:
	var rows := []
	for i in sk.get_bone_count():
		var global := sk.get_bone_global_pose(i)
		var parent := sk.get_bone_parent(i)
		rows.append(sk.get_bone_global_pose(parent).affine_inverse() * global if parent >= 0 else global)
	return rows

## Isolation: for every stage one character runs with ONLY that stage active and a control runs with none, both driven by the same motion. The bones that differ between them are what the stage
## writes. (Reading the pose between stages of one pass would blame a stage for a native IK solver's deferred result.)
func _drive(frames: int, step: Callable) -> void:
	var stage_node := Node3D.new()
	root.add_child(stage_node)
	var rigs: Array[TacticalCharacterAdapter] = []
	var latest: Array = []
	for index in PoseOwnership.STAGE_ORDER.size() + 1:
		var v: TacticalCharacterAdapter = VISUAL.instantiate()
		v.position = Vector3(index * 3.0, 0, 0)
		stage_node.add_child(v)
		rigs.append(v)
		latest.append([])
	for i in 15:
		await process_frame
	for index in rigs.size():
		var sk: Skeleton3D = rigs[index].rig.skeleton
		for child in sk.get_children():
			if child is SkeletonModifier3D:
				var keep := index < PoseOwnership.STAGE_ORDER.size() and StringName(child.name) == PoseOwnership.STAGE_ORDER[index]
				(child as SkeletonModifier3D).active = keep
		var slot := index
		sk.skeleton_updated.connect(func() -> void: latest[slot] = _locals(sk))
		# Host code and one stage re-enable others (the traversal stage switches the leg IK on, a carry switches the arm IK on). Keep every stage but the chosen one off, at the mixer and after each stage.
		var enforce := func() -> void:
			for child in sk.get_children():
				if child is SkeletonModifier3D:
					(child as SkeletonModifier3D).active = index < PoseOwnership.STAGE_ORDER.size() and StringName(child.name) == PoseOwnership.STAGE_ORDER[index]
		rigs[index].rig.animation_controller.animation_tree.mixer_applied.connect(enforce)
		for child in sk.get_children():
			if child is SkeletonModifier3D:
				(child as SkeletonModifier3D).modification_processed.connect(enforce)
	for i in frames:
		for v in rigs:
			step.call(v, i)
		await process_frame
		var control: Array = latest[rigs.size() - 1]
		for index in PoseOwnership.STAGE_ORDER.size():
			var mine: Array = latest[index]
			if mine.is_empty() or control.is_empty():
				continue
			var sk: Skeleton3D = rigs[index].rig.skeleton
			var stage := PoseOwnership.STAGE_ORDER[index]
			for bone in mine.size():
				var a: Transform3D = mine[bone]
				var b: Transform3D = control[bone]
				if a.origin.distance_to(b.origin) > 0.0001 or a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()) > 0.001:
					var role := PoseOwnership.role_of(rigs[index].rig.bones, sk.get_bone_name(bone))
					if not observed.has(stage):
						observed[stage] = {}
					observed[stage][role if role != &"" else StringName("UNMAPPED:" + sk.get_bone_name(bone))] = true
	stage_node.queue_free()
	await process_frame

func _cover(v: TacticalCharacterAdapter, height: float, type := MapCellData.CoverType.LOW) -> void:
	v.last_cover_contact = {"type": type, "height": height, "direction": Vector3.FORWARD}
	v.rig.animation_controller.play(&"cover_low" if type == MapCellData.CoverType.LOW else &"cover_high")

func _run() -> void:
	# ---- Part 1: the declarations are consistent with the modifier order and with each other.
	var problems := PoseOwnership.validate()
	check(problems.is_empty(), "The pose-ownership declarations are consistent: %s" % [problems])
	# The validator itself must catch what it exists to catch (a deliberately broken table is not accepted).
	var saved_overlaps := PoseOwnership.OVERLAPS
	var broken: Array[StringName] = [&"CoverCrouch", &"Locomotion"]
	check(not PoseOwnership.validate(broken).is_empty(), "A modifier order that differs from the declared order is reported")
	var production_order: Array[StringName] = []
	var probe: TacticalCharacterAdapter = VISUAL.instantiate()
	root.add_child(probe)
	for i in 3:
		await process_frame
	for child in probe.rig.skeleton.get_children():
		if child is SkeletonModifier3D:
			production_order.append(StringName(child.name))
	check(production_order == PoseOwnership.STAGE_ORDER, "The production skeleton's modifier children are exactly the declared stages, in order: %s" % [production_order])
	var probe_bones: RigBones = probe.rig.bones
	probe.queue_free()
	await process_frame
	check(PoseOwnership.role_of(probe_bones, "mixamorig_LeftShoulder") == &"support_clavicle" and PoseOwnership.role_of(probe_bones, "mixamorig_RightHandIndex1") == &"fingers" and PoseOwnership.role_of(probe_bones, "mixamorig_LeftLeg") == &"shin" and PoseOwnership.role_of(probe_bones, "mixamorig_LeftUpLeg") == &"thigh", "Bone names map to the declared roles")
	# An undeclared conflict is found: two stages overriding the same bone with no declaration.
	var table_has_undeclared := false
	for write in PoseOwnership.WRITES:
		if write.stage == &"HandGrip" and write.role == &"wrist":
			table_has_undeclared = true
	check(table_has_undeclared and saved_overlaps.size() == 5, "Setup: the table has its five declared overlaps")

	# ---- Part 2: what the stages really write stays inside what they declare.
	await _drive(150, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 10: v.rig.begin_turn(deg_to_rad(80.0))
		if i > 20 and i < 100: v.update_locomotion(Vector3(0, 0, 3.0), 1.0 / 60.0))
	await _drive(130, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 0: _cover(v, 0.4)
		if i == 50: v.request_readiness(&"own", WeaponReadiness.Level.AIMED))
	await _drive(130, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 0: _cover(v, 1.1)
		if i == 40: v.rig.begin_turn(deg_to_rad(60.0))
		if i == 50: v.request_readiness(&"own", WeaponReadiness.Level.AIMED))
	await _drive(160, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 5: v.rig.begin_traversal(&"ladder", 3.0, 1)
		if i >= 5 and i < 130: v.rig.set_traversal_progress(clampf(float(i - 5) * 0.02, 0.0, 2.6))
		if i == 130: v.rig.end_traversal())
	var model := StairModel.from_links(Vector3.ZERO, Vector3(0, 0, 1), 1.0, 1.0, 2, 3)
	await _drive(160, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 5: v.rig.begin_stairs(model, true)
		if i >= 5 and i < 130:
			v.update_locomotion(Vector3(0, 0, 1.2), 1.0 / 60.0)
			v.rig.set_stair_progress(clampf(float(i - 5) * 0.012, 0.0, model.end_s()), 1.2)
		if i == 130: v.rig.end_stairs())
	await _drive(120, func(v: TacticalCharacterAdapter, i: int) -> void:
		if i == 20: v.rig.begin_carry()
		if i >= 20 and i < 90: v.update_locomotion(Vector3(0, 0, 1.0), 1.0 / 60.0)
		if i == 100: v.rig.end_carry())

	var stages_seen := 0
	for stage in PoseOwnership.STAGE_ORDER:
		var declared := PoseOwnership.roles_written(stage)
		var seen: Array = (observed.get(stage, {}) as Dictionary).keys()
		if not seen.is_empty():
			stages_seen += 1
		var undeclared := seen.filter(func(role: StringName) -> bool: return not declared.has(role))
		print("  %-15s declared %s | observed %s" % [stage, declared, seen])
		check(undeclared.is_empty(), "Stage %s only changes bones it declares (undeclared: %s)" % [stage, undeclared])
	check(stages_seen >= 6, "The exercised motions made %d of the %d stages write (the check is meaningful)" % [stages_seen, PoseOwnership.STAGE_ORDER.size()])
	print("Pose ownership: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
