class_name PoseStageReport
extends RefCounted
## Explains pose composition for one CharacterRig: the modifier stages in the order the skeleton really runs them, what PoseOwnership DECLARES each stage writes, the intended overlaps, and which stages are
## engaged right now. Read-only; it keeps no registry of its own (PoseOwnership is the declaration, the skeleton's modifier children are the schedule) and schedules nothing.
##
## Two kinds of statement are kept apart on purpose:
##   DECLARED     what PoseOwnership says a stage may write (static; checked against real bone changes by tests/pose_ownership_test.gd, not by this class).
##   RUNTIME      the stage node's own `active` flag and the weight or request it exposes (read live). "engaged" is an interpretation of those numbers, stated per stage in `detail`.
## Neither is a measured bone change: whether a particular bone actually moved this frame is not answered here (that needs the isolation method of the ownership test).

## Below this a stage's weight is treated as off, matching the modifiers' own early-outs closely enough for a display.
const ENGAGED_EPSILON := 0.001

## The skeleton's real modifier order (names of its SkeletonModifier3D children), which is the schedule.
static func actual_order(rig: CharacterRig) -> Array[StringName]:
	var order: Array[StringName] = []
	if is_instance_valid(rig) and rig.skeleton != null:
		for child in rig.skeleton.get_children():
			if child is SkeletonModifier3D and PoseOwnership.STAGE_ORDER.has(StringName(child.name)):
				order.append(StringName(child.name))
	return order

## Problems between the declared order and the real one (empty when they agree). A stage the rig degraded away (no leg chain, say) is allowed to be missing; reordering is not.
static func order_problems(rig: CharacterRig) -> Array[String]:
	var problems: Array[String] = []
	var actual := actual_order(rig)
	var expected: Array[StringName] = []
	for stage in PoseOwnership.STAGE_ORDER:
		if actual.has(stage):
			expected.append(stage)
	if actual != expected:
		problems.append("The skeleton runs %s but PoseOwnership declares %s" % [actual, expected])
	for stage in PoseOwnership.STAGE_ORDER:
		if not actual.has(stage):
			problems.append("Stage %s is declared but absent from this skeleton" % stage)
	return problems

## One row per declared stage, in declared order: its place in the real order, what it declares, and its runtime state.
static func stages(rig: CharacterRig) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var actual := actual_order(rig)
	for stage in PoseOwnership.STAGE_ORDER:
		var writes: Array = []
		for write in PoseOwnership.WRITES:
			if write.stage == stage:
				writes.append({"role": String(write.role), "domain": String(write.domain), "component": String(write.component), "op": PoseOwnership.Op.keys()[write.op]})
		var runtime := runtime_of(rig, stage)
		rows.append({"stage": String(stage), "position": actual.find(stage), "writes": writes, "present": actual.has(stage), "active": runtime.active, "engaged": runtime.engaged, "detail": runtime.detail})
	return rows

## The live state of one stage: {active (the node's flag), engaged (its weight/request is above zero: an interpretation), detail}.
static func runtime_of(rig: CharacterRig, stage: StringName) -> Dictionary:
	var node: SkeletonModifier3D = null
	if is_instance_valid(rig) and rig.skeleton != null:
		node = rig.skeleton.get_node_or_null(NodePath(String(stage))) as SkeletonModifier3D
	if node == null:
		return {"active": false, "engaged": false, "detail": "absent"}
	var engaged := node.active
	var detail := "active" if node.active else "inactive"
	match stage:
		&"Locomotion":
			var m := rig.locomotion_modifier
			if m != null:
				var amount := absf(m.twist_degrees) + absf(m.bank_degrees) + absf(m.pitch_degrees) + absf(m.step_lift[0]) + absf(m.step_lift[1])
				engaged = node.active and amount > ENGAGED_EPSILON
				detail += " twist %.0f bank %.1f pitch %.1f deg" % [m.twist_degrees, m.bank_degrees, m.pitch_degrees]
		&"CoverCrouch":
			var c := rig.crouch_modifier
			if c != null:
				engaged = node.active and (c.depth > ENGAGED_EPSILON or c.kneel > ENGAGED_EPSILON)
				detail += " depth %.2f m kneel %.2f" % [c.depth, c.kneel]
		&"Traversal":
			if rig.traversal_modifier != null:
				engaged = node.active and rig.traversal_modifier.weight > ENGAGED_EPSILON
				detail += " weight %.2f" % rig.traversal_modifier.weight
		&"TraversalLegIK":
			if rig.leg_ik != null and rig.traversal_modifier != null:
				engaged = node.active and rig.traversal_modifier.weight > ENGAGED_EPSILON
				detail += " (follows Traversal weight %.2f)" % rig.traversal_modifier.weight
		&"TraversalFoot":
			if rig.foot_modifier != null:
				engaged = node.active and rig.foot_modifier.weight > ENGAGED_EPSILON
				detail += " weight %.2f" % rig.foot_modifier.weight
		&"WeaponPose":
			engaged = node.active and rig.has_weapon() and rig.weapon_pose_modifier_enabled
			detail += " armed %s, enabled %s" % [rig.has_weapon(), rig.weapon_pose_modifier_enabled]
		&"WeaponArmIK":
			engaged = node.active and rig.ik_enabled
			detail += " ik_enabled %s" % rig.ik_enabled
		&"HandGrip":
			var g := rig.grip_modifier
			if g != null:
				var contact: float = maxf(float(g.contact_weight[0]), float(g.contact_weight[1]))
				engaged = node.active and (g.orient_weight > ENGAGED_EPSILON or contact > ENGAGED_EPSILON)
				detail += " weapon grip %.2f, contact %.2f/%.2f" % [g.orient_weight, g.contact_weight[0], g.contact_weight[1]]
	return {"active": node.active, "engaged": engaged, "detail": detail}

## "Why is this bone moving, and which stage is responsible?": the role the bone plays and every stage that DECLARES a write to it, in execution order, with its runtime state, plus the overlap rule when stages
## share it. A bone no stage is expected to write answers with an empty list (only the animation clip moves it).
static func explain_bone(rig: CharacterRig, bone_name: String) -> Dictionary:
	var role: StringName = PoseOwnership.role_of(rig.bones, bone_name) if rig.bones != null else &""
	var writers: Array = []
	var rules: Array = []
	for write in PoseOwnership.WRITES:
		if write.role != role:
			continue
		var runtime := runtime_of(rig, write.stage)
		writers.append({"stage": String(write.stage), "domain": String(write.domain), "component": String(write.component), "op": PoseOwnership.Op.keys()[write.op], "engaged": runtime.engaged, "detail": runtime.detail})
	for overlap in PoseOwnership.OVERLAPS:
		if overlap.role == role:
			rules.append({"domain": String(overlap.domain), "stages": overlap.stages.map(func(s: StringName) -> String: return String(s)), "rule": overlap.rule})
	return {"bone": bone_name, "role": String(role), "declared_writers": writers, "overlaps": rules, "clip_only": writers.is_empty()}

## The skeleton bones that play an ownership role (both sides). Highlights and "which bones does this stage touch" use it.
static func bones_for_role(rig: CharacterRig, role: StringName) -> Array[String]:
	var names: Array[String] = []
	if rig.bones == null or rig.skeleton == null:
		return names
	for index in rig.skeleton.get_bone_count():
		var bone_name := rig.skeleton.get_bone_name(index)
		if PoseOwnership.role_of(rig.bones, bone_name) == role:
			names.append(bone_name)
	return names

## The bones a stage is declared to write (bone writes only; IK-target declarations are listed under `targets_of`).
static func bones_of_stage(rig: CharacterRig, stage: StringName) -> Array[String]:
	var names: Array[String] = []
	for role in PoseOwnership.roles_written(stage):
		for bone_name in bones_for_role(rig, role):
			if not names.has(bone_name):
				names.append(bone_name)
	return names

## The IK targets a stage sets, by role (the declaration; the node positions are the rig's).
static func targets_of(stage: StringName) -> Array[StringName]:
	var roles: Array[StringName] = []
	for write in PoseOwnership.WRITES:
		if write.stage == stage and write.op == PoseOwnership.Op.TARGET and not roles.has(write.role):
			roles.append(write.role)
	return roles

static func text(rig: CharacterRig) -> String:
	var lines: Array[String] = []
	var number := 1
	for row: Dictionary in stages(rig):
		var mark := "#" if row.engaged else ("." if row.active else "x")
		var roles: Array[String] = []
		for write: Dictionary in row.writes:
			var entry := "%s:%s" % [write.role, String(write.op).to_lower()]
			if not roles.has(entry):
				roles.append(entry)
		lines.append("%d %s %-14s %s" % [number, mark, row.stage, row.detail])
		lines.append("      declares %s" % ", ".join(roles))
		number += 1
	var problems := order_problems(rig)
	lines.append("order: %s" % ("matches PoseOwnership.STAGE_ORDER" if problems.is_empty() else "; ".join(problems)))
	lines.append("# engaged   . active, nothing to do   x inactive   (declared roles, live weights; not a measured bone change)")
	return "\n".join(lines)
