extends SceneTree
## Task 05 evidence (a PROTOTYPE, not production): one rig-profile schema and one validator describe two meaningfully different humanoid skeletons (the real MIRA skeleton and a small synthetic
## Unreal-style one), reject deliberately broken profiles with clear diagnostics, and feed a production pure solver (the stair planner) from profile-derived proportions. It does NOT animate the
## second skeleton: the full modifier stack on another rig is Task 09's proof. Structural headless checks say nothing about how any pose looks.
const Fix := preload("res://research/rig_profile_prototype/fixtures.gd")
const Resolver := preload("res://research/rig_profile_prototype/rig_resolver.gd")
const Roles := preload("res://research/rig_profile_prototype/rig_roles.gd")
const RigProfile := preload("res://research/rig_profile_prototype/rig_profile.gd")
const Status := Resolver.Status
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _status(r, capability: StringName) -> int:
	return r.status_of(capability)

func _run() -> void:
	var a_skeleton := Fix.mira_skeleton()
	var b_skeleton := Fix.alternate_skeleton()
	var a = Resolver.resolve(Fix.mira_profile(), a_skeleton)
	var b = Resolver.resolve(Fix.alternate_profile(), b_skeleton)

	# ---- 1. The same validator accepts both configurations.
	check(not a.diagnostics.has_errors(), "MIRA's profile validates against the real skeleton with no errors")
	check(not b.diagnostics.has_errors(), "The synthetic alternate validates with no errors through the same code")
	print("  A diagnostics:\n", a.diagnostics.format())
	print("  B diagnostics:\n", b.diagnostics.format())

	# ---- 2. Semantic roles resolve on different naming and hierarchy.
	var all_required := true
	for role: StringName in Roles.REQUIRED:
		all_required = all_required and a.has_role(role) and b.has_role(role)
	check(all_required, "Every FuseFire-required role resolves to a bone on both skeletons")
	check(a.has_role(&"LeftToes") and a.has_role(&"UpperChest") and a.has_role(&"LeftIndexDistal") and a.has_role(&"RightThumbMetacarpal"), "MIRA also resolves toes, a third spine bone and all finger roles")
	check(not b.has_role(&"LeftToes") and not b.has_role(&"UpperChest") and not b.has_role(&"LeftIndexDistal") and b.has_role(&"Root"), "The alternate lacks toes, a third spine bone and fingers, and has a root bone MIRA does not")
	check(a_skeleton.get_bone_name(a.bone(&"LeftLowerLeg")) == "mixamorig_LeftLeg" and b_skeleton.get_bone_name(b.bone(&"LeftLowerLeg")) == "calf_l", "The same role (LeftLowerLeg) is a different bone name on each body")
	check(b.diagnostics.has_code(&"W_OPTIONAL_MISSING") and not a.diagnostics.has_code(&"W_OPTIONAL_MISSING"), "Missing optional bones are WARNINGS (and only on the body that lacks them)")

	# ---- 3. Proportions, conventions, and rest-pose handling differ and are reported correctly.
	var ma = a.measurements
	var mb = b.measurements
	print("  A: leg %.3f shoulder %.3f hip height %.3f ankle %.3f height %.3f | B: leg %.3f shoulder %.3f hip height %.3f ankle %.3f height %.3f" % [ma.leg_length, ma.shoulder_width, ma.hip_height, ma.ankle_height, ma.standing_height, mb.leg_length, mb.shoulder_width, mb.hip_height, mb.ankle_height, mb.standing_height])
	check(mb.leg_length < ma.leg_length - 0.03 and mb.hip_height < ma.hip_height - 0.08 and mb.upper_arm_length > ma.upper_arm_length - 0.0 and mb.shoulder_width > ma.shoulder_width + 0.05, "Proportions differ as built: B has shorter legs and a lower hip, and wider shoulders")
	check(ma.forward.dot(Vector3.BACK) > 0.99 and mb.forward.dot(Vector3.FORWARD) > 0.99, "Forward is derived from geometry: +Z for MIRA, -Z for the alternate")
	check(b.diagnostics.has_code(&"W_FORWARD_NOT_PLUS_Z") and not a.diagnostics.has_code(&"W_FORWARD_NOT_PLUS_Z"), "The alternate's non-standard facing is reported as a warning with its consequence")
	var rest_a: Array = a.diagnostics.entries.filter(func(e) -> bool: return e.code == &"I_REST_POSE")
	var rest_b: Array = b.diagnostics.entries.filter(func(e) -> bool: return e.code == &"I_REST_POSE")
	check(rest_a.size() == 1 and rest_a[0].message.contains("T-pose") and rest_b[0].message.contains("A-pose"), "Rest pose type is recognised: T-pose for MIRA, A-pose for the alternate")
	check(not is_nan(ma.standing_height) and not is_nan(mb.standing_height) and b.diagnostics.has_code(&"I_DECLARED_HEIGHT") and not a.diagnostics.has_code(&"I_DECLARED_HEIGHT"), "MIRA's height is measured from her head-top bone; the alternate's is declared (and said to be)")
	check(absf(a.measurements.thigh_length - 0.388) < 0.005 and absf(a.measurements.upper_arm_length - 0.251) < 0.005, "MIRA's measured thigh and upper arm equal the independently measured production values (0.388 m, 0.251 m)")

	# ---- 4. Agreement with what PRODUCTION already measures on the real rig (the visual scene, scaled 1.6).
	var visual: Node3D = load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate()
	root.add_child(visual)
	for i in 20:
		await process_frame
	var axes: Dictionary = visual.animation_controller.locomotion_axes()
	var up_error := rad_to_deg(ma.up.angle_to(axes.up))
	var forward_error := rad_to_deg(ma.forward.angle_to(axes.forward))
	print("  production vs profile: up %.2f deg, forward %.2f deg, standing head height %.3f vs %.3f" % [up_error, forward_error, visual.crouch_modifier.standing_head_height, ma.standing_height - ma.ankle_height])
	check(up_error < 0.5, "The profile's derived up axis equals production's measured up axis (%.2f degrees)" % up_error)
	check(forward_error < 4.0, "The derived forward (from the hips) agrees with production's toe-based forward within 4 degrees (%.2f); production measures from the toes, the profile needs none" % forward_error)
	check(absf((ma.standing_height - ma.ankle_height) - visual.crouch_modifier.standing_head_height) < 0.02, "Standing head height above the ankle equals what CoverCrouchModifier measures (within 2 cm)")
	var live = Resolver.resolve(Fix.mira_profile(), visual.skeleton)
	check(not live.diagnostics.has_code(&"E_SCALE_MISMATCH") and not live.diagnostics.has_errors(), "Against the in-scene production skeleton (shown at 1.6x) the declared character_scale 1.6 is consistent")
	var wrong := Fix.mira_profile()
	wrong.anatomy.character_scale = 1.0
	check(Resolver.resolve(wrong, visual.skeleton).diagnostics.has_code(&"E_SCALE_MISMATCH"), "A wrong declared scale against the in-scene skeleton is an error (the scale would be applied twice or not at all)")
	visual.queue_free()
	await process_frame

	# ---- 5. Capabilities: structure decides, with fallbacks and honest 'not implemented'.
	check(_status(a, &"hand_grip") == Status.SUPPORTED and _status(b, &"hand_grip") == Status.FALLBACK, "Hand grip: supported on MIRA, a defined fallback on the finger-less body")
	check(_status(a, &"biped_locomotion") == Status.SUPPORTED and _status(b, &"biped_locomotion") == Status.SUPPORTED and _status(b, &"stair_foot_placement") == Status.SUPPORTED and _status(b, &"unarmed") == Status.SUPPORTED, "Both bodies support walking, stair foot placement and unarmed presentation")
	check(_status(a, &"object_interaction") == Status.NOT_IMPLEMENTED and _status(a, &"head_attention") == Status.NOT_IMPLEMENTED, "Capabilities with no implementation yet say NOT_IMPLEMENTED rather than claiming support")
	var rifle := Fix.rifle()
	check(not Resolver.supports_equipment(a, rifle).has_errors() and not Resolver.supports_equipment(b, rifle).has_errors(), "Both bodies can physically carry the rifle presentation (sockets exist); no rifle is built into either profile")
	var no_support_hand := Fix.alternate_profile()
	no_support_hand.sockets = no_support_hand.sockets.filter(func(s) -> bool: return s.socket_name != &"weapon_support_hand")
	var b_no_socket = Resolver.resolve(no_support_hand, b_skeleton)
	check(Resolver.supports_equipment(b_no_socket, rifle).has_code(&"E_EQUIPMENT_SOCKET") and _status(b_no_socket, &"weapon_ready_pose") == Status.UNSUPPORTED and _status(b_no_socket, &"unarmed") == Status.SUPPORTED, "A body without weapon sockets cannot carry the rifle but stays fully usable unarmed")

	# ---- 6. Invalid configurations produce specific, actionable diagnostics.
	var broken := Fix.mira_profile()
	broken.skeleton_map.set_skeleton_bone_name(&"LeftLowerLeg", &"")
	var r1 = Resolver.resolve(broken, a_skeleton)
	check(r1.diagnostics.has_code(&"E_REQUIRED_ROLE_MISSING") and r1.diagnostics.entries.any(func(e) -> bool: return e.role == &"LeftLowerLeg"), "An unmapped required role is an ERROR naming the role")
	check(_status(r1, &"biped_locomotion") == Status.UNSUPPORTED and _status(r1, &"stair_foot_placement") == Status.UNSUPPORTED and _status(r1, &"two_arm_ik") == Status.SUPPORTED, "No usable leg chain: stair foot IK and locomotion are NOT claimed, while the arms still are")
	var missing_bone := Fix.mira_profile()
	missing_bone.skeleton_map.set_skeleton_bone_name(&"Head", &"mixamorig_NoSuchBone")
	check(Resolver.resolve(missing_bone, a_skeleton).diagnostics.has_code(&"E_BONE_NOT_FOUND"), "A role mapped to a bone the skeleton does not have is an error")
	var duplicate := Fix.mira_profile()
	duplicate.skeleton_map.set_skeleton_bone_name(&"RightUpperLeg", &"mixamorig_LeftUpLeg")
	check(Resolver.resolve(duplicate, a_skeleton).diagnostics.has_code(&"E_DUPLICATE_BONE"), "Two roles claiming one bone is an error")
	var wrong_parent := Fix.mira_profile()
	wrong_parent.skeleton_map.set_skeleton_bone_name(&"LeftLowerLeg", &"mixamorig_LeftHandIndex4")
	var r4 = Resolver.resolve(wrong_parent, a_skeleton)
	check(r4.diagnostics.has_code(&"E_HIERARCHY") and _status(r4, &"biped_locomotion") == Status.UNSUPPORTED, "A bone outside its chain (a finger end bone as the lower leg) is a hierarchy error and disables locomotion")
	var swapped := Fix.mira_profile()
	swapped.skeleton_map.set_skeleton_bone_name(&"LeftHand", &"mixamorig_RightHand")
	swapped.skeleton_map.set_skeleton_bone_name(&"RightHand", &"mixamorig_LeftHand")
	check(Resolver.resolve(swapped, a_skeleton).diagnostics.has_code(&"E_SIDE_INCONSISTENT"), "Swapped left and right hands are detected from geometry")
	var collapsed := Fix.alternate_skeleton()
	collapsed.set_bone_rest(collapsed.find_bone("calf_l"), Transform3D(Basis.from_scale(Vector3(0.0, 1.0, 1.0)), Vector3.ZERO))
	check(Resolver.resolve(Fix.alternate_profile(), collapsed).diagnostics.has_code(&"E_REST_DEGENERATE"), "A collapsed (zero-scale) rest transform is an error")
	var renamed := Fix.alternate_skeleton("", {"calf_l": "shin_l"})
	check(Resolver.resolve(Fix.alternate_profile(), renamed).diagnostics.has_code(&"E_BONE_NOT_FOUND"), "A renamed bone breaks the map visibly (a clear 'not found') instead of silently disabling a modifier")
	var orphan_socket := Fix.mira_profile()
	orphan_socket.skeleton_map.set_skeleton_bone_name(&"LeftToes", &"")
	orphan_socket.sockets.append(Fix.socket(&"left_toe_tag", &"LeftToes"))
	check(Resolver.resolve(orphan_socket, a_skeleton).diagnostics.has_code(&"E_SOCKET_PARENT_MISSING"), "A socket on an unmapped role is diagnosed")
	var bad_joint := Fix.mira_profile()
	bad_joint.anatomy.joints[0].min_degrees = 160.0
	check(Resolver.resolve(bad_joint, a_skeleton).diagnostics.has_code(&"E_JOINT_LIMITS"), "Inverted joint limits are an error")
	var no_height := Fix.alternate_profile()
	no_height.anatomy.declared_height = 0.0
	var r_no_height = Resolver.resolve(no_height, b_skeleton)
	check(r_no_height.diagnostics.has_code(&"W_NO_HEAD_TOP") and _status(r_no_height, &"crouch") == Status.UNSUPPORTED and r_no_height.capabilities[&"crouch"].reason.contains("head_top_bone") and _status(r_no_height, &"biped_locomotion") == Status.SUPPORTED, "No head-top and no declared height: crouch is unsupported with the fix named, walking is unaffected")
	var no_fingers := Fix.mira_profile()
	for role: StringName in Roles.finger_roles("Left") + Roles.finger_roles("Right"):
		no_fingers.skeleton_map.set_skeleton_bone_name(role, &"")
	var r_no_fingers = Resolver.resolve(no_fingers, a_skeleton)
	check(not r_no_fingers.diagnostics.has_errors() and _status(r_no_fingers, &"hand_grip") == Status.FALLBACK and _status(r_no_fingers, &"biped_locomotion") == Status.SUPPORTED, "A rig with no finger bones does not fail validation for walking; grip degrades to the fallback")
	var scale_bad := Fix.mira_profile()
	scale_bad.anatomy.character_scale = 100.0
	check(Resolver.resolve(scale_bad, a_skeleton).diagnostics.has_code(&"E_IMPLAUSIBLE_HEIGHT"), "A unit mix-up (scale 100) is caught as an implausible height")
	var bad_declared := Fix.alternate_profile()
	bad_declared.anatomy.declared_height = 0.9
	check(Resolver.resolve(bad_declared, b_skeleton).diagnostics.has_code(&"W_DECLARED_HEIGHT_INCONSISTENT"), "A declared height that cannot fit the head bone is flagged")
	var no_map := RigProfile.new()
	check(Resolver.resolve(no_map, b_skeleton).diagnostics.has_code(&"E_NO_BONE_MAP"), "A profile with no bone map fails clearly")

	# ---- 7. A production PURE solver consumes profile-derived data for both bodies.
	var heights: Array[float] = []
	var solver_ok := true
	for resolved in [a, b]:
		var stairs := StairProfile.new()
		stairs.leg_length = resolved.measurements.hips_to_ankle   # the planner's leg_length spans the Hips origin to the ankle, not the thigh plus shin
		stairs.ankle_height = resolved.measurements.ankle_height
		stairs.pelvis_standing_height = resolved.measurements.hip_height
		var model := StairModel.from_links(Vector3.ZERO, Vector3(0, 0, -1), 1.0, 1.0, 2, 3)
		var holds := StairFootPlanner.holds(model, true, 1)
		var pelvis_at: Array[float] = []
		for s in [0.6, 1.2, 1.8, 2.4]:
			var result := StairFootPlanner.pelvis_smoothed(model, stairs, holds, true, s, model.point_at(s, 0.0))
			solver_ok = solver_ok and bool(result.ok)
			pelvis_at.append(float(result.height) - model.height_at(s))
		heights.append(pelvis_at[1])
		print("  %s: stair pelvis height above the tread at s=1.2: %.3f m (hips-to-ankle %.3f, hip height %.3f)" % [resolved.profile.display_name, pelvis_at[1], resolved.measurements.hips_to_ankle, resolved.measurements.hip_height])
	var tuned := StairProfile.new()
	var traversal_tuned := TraversalProfile.new()
	print("  MIRA measured vs production-tuned: hips-to-ankle %.3f vs leg_length %.2f; ankle %.3f vs %.2f; hip half-width %.3f vs foot_half_spread %.2f; hip height %.3f vs traversal hips_height %.2f and stair pelvis_standing_height %.2f" % [ma.hips_to_ankle, tuned.leg_length, ma.ankle_height, tuned.ankle_height, ma.hip_width * 0.5, tuned.foot_half_spread, ma.hip_height, traversal_tuned.hips_height, tuned.pelvis_standing_height])
	check(absf(ma.hips_to_ankle - tuned.leg_length) / tuned.leg_length < 0.03, "MIRA's measured hips-to-ankle length (%.3f m) is within 3%% of the stair planner's tuned leg_length (%.2f): that constant is anatomy, derivable from the skeleton" % [ma.hips_to_ankle, tuned.leg_length])
	check(solver_ok, "StairFootPlanner finds valid pelvis heights along the stair for both profile-derived bodies")
	check(heights[0] - heights[1] > 0.04 and heights[0] - heights[1] < 0.2, "The same solver puts the shorter body's pelvis lower (%.3f m): the difference comes from profile data, not code" % (heights[0] - heights[1]))

	# ---- 8. Separation: no gameplay role in the anatomy resources; resources round-trip as .tres.
	var forbidden := ["faction", "archetype", "objective", "mission", "movement_range", "tactical", "unit_class", "team", "action_points"]
	var leak := false
	for resource in [Fix.mira_profile(), Fix.mira_profile().anatomy, Fix.socket(&"x", &"Hips"), Fix.joint(&"Hips", 1.0, Vector3.UP)]:
		for property in resource.get_property_list():
			for word in forbidden:
				if String(property.name).to_lower().contains(word):
					leak = true
	check(not leak, "The rig profile resources contain no gameplay-role field (faction, archetype, mission, AP, movement range...)")
	var loaded_a = Resolver.resolve(load("res://research/rig_profile_prototype/profiles/mira_rig_profile.tres"), a_skeleton)
	var loaded_b = Resolver.resolve(load("res://research/rig_profile_prototype/profiles/alternate_rig_profile.tres"), b_skeleton)
	check(not loaded_a.diagnostics.has_errors() and not loaded_b.diagnostics.has_errors() and loaded_a.bone_index == a.bone_index and loaded_b.bone_index == b.bone_index and absf(loaded_a.measurements.leg_length - ma.leg_length) < 0.0001, "The saved .tres files (BoneMap and SkeletonProfileHumanoid included) load and resolve identically to the code-built profiles")

	a_skeleton.free()
	b_skeleton.free()
	collapsed.free()
	renamed.free()
	print("Rig profile prototype: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
