extends RefCounted
## Task 05 PROTOTYPE: resolves a RigProfile against a real Skeleton3D. It maps semantic roles to bone indices, derives the body's axes and proportions from the REST POSE (metres, with the
## character scale applied exactly once), validates everything against FuseFire's needs, and reports what the body can structurally present. It never writes to the skeleton.
## It is a validation experiment: no production code calls it, and it does not animate anything.
const Roles := preload("res://presentation/characters/rig_profile/rig_roles.gd")
const Diagnostics := preload("res://presentation/characters/rig_profile/rig_diagnostics.gd")
const RigProfile := preload("res://presentation/characters/rig_profile/rig_profile.gd")
const EquipmentPresentation := preload("res://presentation/characters/equipment/equipment_presentation.gd")

enum Status { SUPPORTED, FALLBACK, UNSUPPORTED, NOT_IMPLEMENTED }

## Structural capability, never gameplay permission: it says what the BODY can show, not what the game allows.
class Capability extends RefCounted:
	var status: Status = Status.UNSUPPORTED
	var reason := ""

## Derived proportions in METRES (the character scale already applied) and unit axes in skeleton space.
class Measurements extends RefCounted:
	var up := Vector3.UP
	var forward := Vector3.BACK
	var lateral := Vector3.RIGHT          # toward the character's LEFT
	var hip_height := NAN
	var ankle_height := NAN
	var thigh_length := NAN
	var shin_length := NAN
	var leg_length := NAN                  # thigh + shin (the hip JOINT to the ankle along the bones)
	var hips_to_ankle := NAN               # the Hips bone origin to the ankle (the legs hang from the hip joints, so the stair planner uses `leg_length`)
	var upper_arm_length := NAN
	var forearm_length := NAN
	var shoulder_width := NAN              # between the two upper-arm joints
	var hip_width := NAN                   # between the two upper-leg joints
	var standing_height := NAN             # NAN when neither a head-top bone nor a declared height exists

class Resolved extends RefCounted:
	var profile: RigProfile
	var bone_index: Dictionary = {}        # role (StringName) -> int
	var measurements := Measurements.new()
	var bend_axes: Dictionary = {}         # role -> unit vector in the bone's LOCAL rest frame (the axis a hinge flexes about)
	var sockets: Dictionary = {}           # socket name -> Transform3D (skeleton space, native units)
	var capabilities: Dictionary = {}      # capability name (StringName) -> Capability
	var diagnostics := Diagnostics.new()
	func has_role(role: StringName) -> bool:
		return bone_index.has(role)
	func bone(role: StringName) -> int:
		return int(bone_index.get(role, -1))
	func status_of(capability: StringName) -> Status:
		return (capabilities[capability] as Capability).status if capabilities.has(capability) else Status.UNSUPPORTED
	func supports(capability: StringName) -> bool:
		return status_of(capability) in [Status.SUPPORTED, Status.FALLBACK]

static func resolve(profile: RigProfile, skeleton: Skeleton3D) -> Resolved:
	var result := Resolved.new()
	result.profile = profile
	var diag := result.diagnostics
	if profile == null or profile.skeleton_map == null or profile.skeleton_map.profile == null:
		diag.error(&"E_NO_BONE_MAP", &"", "The profile has no BoneMap with a SkeletonProfile", "assign a BoneMap whose profile is SkeletonProfileHumanoid")
		_evaluate_capabilities(result)
		return result
	_map_roles(result, skeleton)
	_check_hierarchy(result, skeleton)
	_check_rest_poses(result, skeleton)
	_measure(result, skeleton)
	_check_sockets(result, skeleton)
	_check_joints(result, skeleton)
	_evaluate_capabilities(result)
	return result

# ---------------------------------------------------------------- mapping

static func _map_roles(result: Resolved, skeleton: Skeleton3D) -> void:
	var diag := result.diagnostics
	var map := result.profile.skeleton_map
	var claimed: Dictionary = {}     # bone index -> role that claimed it
	for index in map.profile.bone_size:
		var role: StringName = map.profile.get_bone_name(index)
		var name: StringName = map.get_skeleton_bone_name(role)
		if name == &"":
			continue
		var bone := skeleton.find_bone(name)
		if bone < 0:
			diag.error(&"E_BONE_NOT_FOUND", role, "mapped to '%s', which this skeleton does not have" % name, "correct the BoneMap entry or the skeleton's bone name")
			continue
		if claimed.has(bone):
			diag.error(&"E_DUPLICATE_BONE", role, "'%s' is already the bone of role %s" % [name, claimed[bone]], "each role needs its own bone")
			continue
		claimed[bone] = role
		result.bone_index[role] = bone
	for role: StringName in Roles.REQUIRED:
		# A role that IS mapped but unusable was already reported (bone not found, duplicate); only an unmapped required role is new information here.
		if not result.has_role(role) and map.get_skeleton_bone_name(role) == &"":
			diag.error(&"E_REQUIRED_ROLE_MISSING", role, "FuseFire needs this role and it is not mapped", "map %s in the profile's BoneMap" % role)
	var optional_groups := {
		"fingers": Roles.finger_roles("Left") + Roles.finger_roles("Right"),
		"toes": [&"LeftToes", &"RightToes"], "neck": [&"Neck"], "upper spine": [&"Chest", &"UpperChest"],
		"clavicles": [&"LeftShoulder", &"RightShoulder"],
	}
	for group: String in optional_groups:
		var missing: Array = []
		for role: StringName in optional_groups[group]:
			if not result.has_role(role):
				missing.append(role)
		if missing.size() == (optional_groups[group] as Array).size():
			diag.warn(&"W_OPTIONAL_MISSING", &"", "no %s mapped" % group, "features that use the %s fall back or are unavailable (see the capability report)" % group)
		elif not missing.is_empty():
			diag.warn(&"W_OPTIONAL_PARTIAL", &"", "%s partly mapped (missing %s)" % [group, ", ".join(PackedStringArray(missing.map(func(r: StringName) -> String: return String(r))))], "map the rest or none")

static func _is_descendant(skeleton: Skeleton3D, bone: int, ancestor: int) -> bool:
	var parent := skeleton.get_bone_parent(bone)
	while parent >= 0:
		if parent == ancestor:
			return true
		parent = skeleton.get_bone_parent(parent)
	return false

static func _check_hierarchy(result: Resolved, skeleton: Skeleton3D) -> void:
	var diag := result.diagnostics
	for pair: Array in Roles.CHAINS:
		var parent_role: StringName = pair[0]
		var child_role: StringName = pair[1]
		if not result.has_role(parent_role) or not result.has_role(child_role):
			continue
		var parent_bone := result.bone(parent_role)
		var child_bone := result.bone(child_role)
		if not _is_descendant(skeleton, child_bone, parent_bone):
			diag.error(&"E_HIERARCHY", child_role, "'%s' is not below '%s' (the %s chain is broken)" % [skeleton.get_bone_name(child_bone), skeleton.get_bone_name(parent_bone), parent_role], "check both mappings (a swapped or wrong bone?)")
		elif skeleton.get_bone_parent(child_bone) != parent_bone:
			diag.info(&"I_INTERMEDIATE_BONES", child_role, "there are bones between %s and %s; they are ignored by the roles" % [parent_role, child_role])

static func _check_rest_poses(result: Resolved, skeleton: Skeleton3D) -> void:
	var diag := result.diagnostics
	for role: StringName in result.bone_index:
		var rest := skeleton.get_bone_rest(result.bone(role))
		var scale := rest.basis.get_scale()
		if scale.x < 0.0001 or scale.y < 0.0001 or scale.z < 0.0001:
			diag.error(&"E_REST_DEGENERATE", role, "the rest transform has a zero or collapsed scale", "re-export the skeleton with applied transforms")
		elif absf(scale.x - 1.0) > 0.02 or absf(scale.y - 1.0) > 0.02 or absf(scale.z - 1.0) > 0.02:
			diag.warn(&"W_REST_SCALE", role, "rest scale is %s, not 1 (solvers assume unit bone scale)" % scale, "apply transforms in the source file")

# ---------------------------------------------------------------- geometry

static func _rest_origin(skeleton: Skeleton3D, result: Resolved, role: StringName) -> Vector3:
	return skeleton.get_bone_global_rest(result.bone(role)).origin

static func _have(result: Resolved, roles: Array) -> bool:
	for role: StringName in roles:
		if not result.has_role(role):
			return false
	return true

static func _measure(result: Resolved, skeleton: Skeleton3D) -> void:
	var diag := result.diagnostics
	var m := result.measurements
	var anatomy := result.profile.anatomy
	var scale := anatomy.character_scale if anatomy != null else 1.0
	if skeleton.is_inside_tree():
		var actual := skeleton.global_basis.get_scale().y
		if absf(actual - scale) > 0.01 * maxf(scale, 0.0001):
			diag.error(&"E_SCALE_MISMATCH", &"", "the profile declares character_scale %.3f but the skeleton is shown at %.3f" % [scale, actual], "set anatomy.character_scale to the scale the model is displayed at (scale is applied once)")
	if not _have(result, [&"Hips", &"Head", &"LeftUpperLeg", &"RightUpperLeg"]):
		return
	var hips := _rest_origin(skeleton, result, &"Hips")
	var up := _rest_origin(skeleton, result, &"Head") - hips
	if up.length() < 0.0001:
		diag.error(&"E_ZERO_LENGTH", &"Head", "Head and Hips share a position; the body has no height", "check the mapping")
		return
	m.up = up.normalized()
	var left_leg := _rest_origin(skeleton, result, &"LeftUpperLeg")
	var right_leg := _rest_origin(skeleton, result, &"RightUpperLeg")
	var side := left_leg - right_leg
	side -= m.up * side.dot(m.up)
	if side.length() < 0.0001:
		diag.error(&"E_ZERO_WIDTH", &"LeftUpperLeg", "the two hip joints do not differ sideways; left and right cannot be told apart", "check the leg mappings")
		return
	m.lateral = side.normalized()
	# A skeleton space is right-handed; with left on +lateral and up on +up, forward = lateral x up (for Godot's X-left, Y-up it is +Z).
	m.forward = m.lateral.cross(m.up).normalized()
	# Left/right consistency: every counterpart pair must keep the same orientation.
	for pair: Array in Roles.SIDE_PAIRS:
		if _have(result, pair):
			var offset := _rest_origin(skeleton, result, pair[0]) - _rest_origin(skeleton, result, pair[1])
			if offset.dot(m.lateral) <= 0.0:
				diag.error(&"E_SIDE_INCONSISTENT", pair[0], "%s lies on the opposite side from the hips' left/right (swapped or mixed mapping)" % pair[0], "left roles must all be on one side of the body")
	if result.has_role(&"LeftToes"):
		var toe := _rest_origin(skeleton, result, &"LeftToes") - _rest_origin(skeleton, result, &"LeftFoot")
		toe -= m.up * toe.dot(m.up)
		if toe.length() > 0.001 and toe.normalized().dot(m.forward) < 0.5:
			diag.warn(&"W_FORWARD_DISAGREES_WITH_TOES", &"LeftToes", "the toes point away from the forward direction derived from the hips (%.2f)" % toe.normalized().dot(m.forward), "check the left/right mapping or the foot orientation")
	if m.up.dot(Vector3.UP) < 0.9:
		diag.warn(&"W_NOT_Y_UP", &"", "the body's up is %s, not +Y (%.0f degrees away)" % [m.up, rad_to_deg(acos(clampf(m.up.dot(Vector3.UP), -1.0, 1.0)))], "production code assumes a Y-up skeleton in places (see the migration inventory)")
	if m.forward.dot(Vector3.BACK) < 0.9:
		diag.warn(&"W_FORWARD_NOT_PLUS_Z", &"", "the body faces %s, not +Z (Godot's import convention)" % m.forward, "rotate the model at import or give the character a root yaw")
	# Proportions, METRES (scale applied once here and nowhere else).
	var s := scale
	if _have(result, [&"LeftFoot"]):
		m.ankle_height = _rest_origin(skeleton, result, &"LeftFoot").dot(m.up) * s
	m.hip_height = hips.dot(m.up) * s
	m.hip_width = left_leg.distance_to(right_leg) * s
	if _have(result, [&"LeftLowerLeg", &"LeftFoot"]):
		m.thigh_length = left_leg.distance_to(_rest_origin(skeleton, result, &"LeftLowerLeg")) * s
		m.shin_length = _rest_origin(skeleton, result, &"LeftLowerLeg").distance_to(_rest_origin(skeleton, result, &"LeftFoot")) * s
		m.leg_length = m.thigh_length + m.shin_length
		m.hips_to_ankle = hips.distance_to(_rest_origin(skeleton, result, &"LeftFoot")) * s
		if _have(result, [&"RightLowerLeg", &"RightFoot"]):
			var right_total := (right_leg.distance_to(_rest_origin(skeleton, result, &"RightLowerLeg")) + _rest_origin(skeleton, result, &"RightLowerLeg").distance_to(_rest_origin(skeleton, result, &"RightFoot"))) * s
			if absf(right_total - m.leg_length) > 0.1 * m.leg_length:
				diag.warn(&"W_ASYMMETRY", &"LeftUpperLeg", "left leg %.3f m vs right leg %.3f m" % [m.leg_length, right_total], "check the mapping (or the rig is deliberately asymmetric)")
		if m.thigh_length > 0.0 and (m.shin_length / m.thigh_length < 0.8 or m.shin_length / m.thigh_length > 1.25):
			diag.warn(&"W_LEG_SEGMENTS_UNEQUAL", &"LeftLowerLeg", "shin/thigh = %.2f; the stair planner assumes about equal segments" % (m.shin_length / m.thigh_length), "acceptable for walking; stairs will be approximate")
	if _have(result, [&"LeftUpperArm", &"LeftLowerArm", &"LeftHand"]):
		var shoulder := _rest_origin(skeleton, result, &"LeftUpperArm")
		var elbow := _rest_origin(skeleton, result, &"LeftLowerArm")
		m.upper_arm_length = shoulder.distance_to(elbow) * s
		m.forearm_length = elbow.distance_to(_rest_origin(skeleton, result, &"LeftHand")) * s
		if result.has_role(&"RightUpperArm"):
			m.shoulder_width = shoulder.distance_to(_rest_origin(skeleton, result, &"RightUpperArm")) * s
		var arm_direction := (_rest_origin(skeleton, result, &"LeftHand") - shoulder).normalized()
		var below_horizontal := rad_to_deg(asin(clampf(-arm_direction.dot(m.up), -1.0, 1.0)))
		diag.info(&"I_REST_POSE", &"", "arms rest %.0f degrees below horizontal (%s)" % [below_horizontal, "T-pose" if below_horizontal < 12.0 else "A-pose"])
	var top_bone := anatomy.head_top_bone if anatomy != null else &""
	if top_bone != &"" and skeleton.find_bone(top_bone) >= 0:
		m.standing_height = skeleton.get_bone_global_rest(skeleton.find_bone(top_bone)).origin.dot(m.up) * s
	elif anatomy != null and anatomy.declared_height > 0.0:
		m.standing_height = anatomy.declared_height
		diag.info(&"I_DECLARED_HEIGHT", &"", "standing height %.2f m is declared, not measured (no head-top bone)" % anatomy.declared_height)
		var head_height := _rest_origin(skeleton, result, &"Head").dot(m.up) * s
		if anatomy.declared_height < head_height or anatomy.declared_height > head_height * 1.4:
			diag.warn(&"W_DECLARED_HEIGHT_INCONSISTENT", &"Head", "declared height %.2f m does not fit a head bone at %.2f m" % [anatomy.declared_height, head_height], "the declared height should be a little above the head bone")
	else:
		diag.warn(&"W_NO_HEAD_TOP", &"Head", "no head-top bone and no declared height: standing height is unknown", "set anatomy.head_top_bone or anatomy.declared_height")
	# Plausibility.
	if not is_nan(m.standing_height) and (m.standing_height < 0.5 or m.standing_height > 3.0):
		diag.error(&"E_IMPLAUSIBLE_HEIGHT", &"", "standing height %.2f m is outside 0.5 to 3.0 m" % m.standing_height, "check character_scale (a unit mix-up is the usual cause)")
	if not is_nan(m.ankle_height) and (m.ankle_height < 0.02 or m.ankle_height > 0.25):
		diag.warn(&"W_IMPLAUSIBLE_ANKLE", &"LeftFoot", "ankle height %.3f m is outside 0.02 to 0.25 m (is the skeleton origin on the floor?)" % m.ankle_height, "the feet are expected to rest at the skeleton origin's height")
	if not is_nan(m.leg_length) and not is_nan(m.hip_height) and (m.leg_length > m.hip_height * 1.1 or m.leg_length < m.hip_height * 0.5):
		diag.warn(&"W_IMPLAUSIBLE_LEG", &"LeftUpperLeg", "leg length %.2f m vs hip height %.2f m" % [m.leg_length, m.hip_height])
	# Derived hinge axes (the axis a knee or elbow flexes about, in the bone's own rest frame): the body's lateral axis, which the legs' and arms' rest poses share.
	for role: StringName in [&"LeftLowerLeg", &"RightLowerLeg", &"LeftLowerArm", &"RightLowerArm"]:
		if result.has_role(role):
			var rest_basis := skeleton.get_bone_global_rest(result.bone(role)).basis.orthonormalized()
			if absf(rest_basis.determinant()) < 0.5:
				continue   # a degenerate rest (already reported as E_REST_DEGENERATE) has no usable axes
			result.bend_axes[role] = (rest_basis.inverse() * m.lateral).normalized()

# ---------------------------------------------------------------- sockets and joints

static func _check_sockets(result: Resolved, skeleton: Skeleton3D) -> void:
	var diag := result.diagnostics
	var seen: Dictionary = {}
	for socket in result.profile.sockets:
		if socket == null:
			continue
		if seen.has(socket.socket_name):
			diag.error(&"E_DUPLICATE_SOCKET", socket.parent_role, "socket '%s' is declared twice" % socket.socket_name)
			continue
		seen[socket.socket_name] = true
		if not result.has_role(socket.parent_role):
			diag.error(&"E_SOCKET_PARENT_MISSING", socket.parent_role, "socket '%s' hangs on role %s, which is not mapped" % [socket.socket_name, socket.parent_role], "map the role or move the socket")
			continue
		var scale := result.profile.anatomy.character_scale if result.profile.anatomy != null else 1.0
		var bone_rest := skeleton.get_bone_global_rest(result.bone(socket.parent_role))
		var native_offset := Transform3D(socket.offset.basis, socket.offset.origin / maxf(scale, 0.0001))
		result.sockets[socket.socket_name] = bone_rest * native_offset

static func _check_joints(result: Resolved, _skeleton: Skeleton3D) -> void:
	var diag := result.diagnostics
	if result.profile.anatomy == null:
		return
	for joint in result.profile.anatomy.joints:
		if joint == null:
			continue
		if not result.has_role(joint.role):
			diag.error(&"E_JOINT_ROLE_MISSING", joint.role, "a joint spec names a role that is not mapped")
		elif joint.min_degrees >= joint.max_degrees:
			diag.error(&"E_JOINT_LIMITS", joint.role, "min %.0f is not below max %.0f degrees" % [joint.min_degrees, joint.max_degrees])
		elif joint.pole_direction.length() < 0.001:
			diag.error(&"E_JOINT_POLE", joint.role, "the pole direction is a zero vector")

# ---------------------------------------------------------------- capabilities

static func _cap(result: Resolved, name: StringName, status: Status, reason: String) -> void:
	var capability := Capability.new()
	capability.status = status
	capability.reason = reason
	result.capabilities[name] = capability

static func _missing(result: Resolved, roles: Array) -> Array:
	var missing: Array = []
	for role: StringName in roles:
		if not result.has_role(role):
			missing.append(role)
	return missing

static func _evaluate_capabilities(result: Resolved) -> void:
	var m := result.measurements
	var geometry_ok := not is_nan(m.leg_length) and not result.diagnostics.has_code(&"E_SIDE_INCONSISTENT") and not result.diagnostics.has_code(&"E_HIERARCHY") and not result.diagnostics.has_code(&"E_REST_DEGENERATE")
	var legs := [&"Hips", &"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot", &"RightUpperLeg", &"RightLowerLeg", &"RightFoot"]
	var arms := [&"LeftUpperArm", &"LeftLowerArm", &"LeftHand", &"RightUpperArm", &"RightLowerArm", &"RightHand"]
	var missing_legs := _missing(result, legs)
	var missing_arms := _missing(result, arms)
	var legs_ok := missing_legs.is_empty() and geometry_ok
	var arms_ok := missing_arms.is_empty() and not result.diagnostics.has_code(&"E_HIERARCHY")
	var bad := "a required chain is broken or incomplete (%s)"
	_cap(result, &"biped_locomotion", Status.SUPPORTED if legs_ok and result.has_role(&"Spine") else Status.UNSUPPORTED, "" if legs_ok else bad % str(missing_legs))
	_cap(result, &"turn_twist", Status.SUPPORTED if legs_ok and result.has_role(&"Spine") else Status.UNSUPPORTED, "needs hips, legs and a spine bone")
	if not legs_ok:
		_cap(result, &"crouch", Status.UNSUPPORTED, "no usable leg chain")
	elif is_nan(m.standing_height):
		_cap(result, &"crouch", Status.UNSUPPORTED, "standing height unknown: set anatomy.head_top_bone or anatomy.declared_height")
	elif not result.has_role(&"Chest"):
		_cap(result, &"crouch", Status.FALLBACK, "one spine bone only: the crouch leans through a single bone")
	else:
		_cap(result, &"crouch", Status.SUPPORTED, "")
	_cap(result, &"kneel", result.capabilities[&"crouch"].status if legs_ok else Status.UNSUPPORTED, "same prerequisites as crouch")
	_cap(result, &"stair_foot_placement", Status.SUPPORTED if legs_ok else Status.UNSUPPORTED, "" if legs_ok else "no usable leg chain: stair foot IK would not work")
	if legs_ok and arms_ok:
		_cap(result, &"ladder_contacts", Status.SUPPORTED, "")
	else:
		_cap(result, &"ladder_contacts", Status.UNSUPPORTED, "needs both leg and arm chains")
	_cap(result, &"two_arm_ik", Status.SUPPORTED if arms_ok else Status.UNSUPPORTED, "" if arms_ok else bad % str(missing_arms))
	if not arms_ok:
		_cap(result, &"hand_grip", Status.UNSUPPORTED, "no usable arm chains")
	elif _missing(result, Roles.finger_roles("Left") + Roles.finger_roles("Right")).is_empty():
		_cap(result, &"hand_grip", Status.SUPPORTED, "")
	else:
		_cap(result, &"hand_grip", Status.FALLBACK, "no finger bones: hands are placed on the contact, fingers stay in the rest pose")
	var sockets_ok := result.sockets.has(&"weapon_dominant_hand") and result.sockets.has(&"weapon_support_hand")
	if not arms_ok:
		_cap(result, &"weapon_ready_pose", Status.UNSUPPORTED, "no usable arm chains")
	elif not sockets_ok:
		_cap(result, &"weapon_ready_pose", Status.UNSUPPORTED, "no weapon hand sockets (a body can still be unarmed)")
	else:
		_cap(result, &"weapon_ready_pose", Status.SUPPORTED, "")
	if not arms_ok:
		_cap(result, &"carry_pose", Status.UNSUPPORTED, "no usable arm chains")
	elif not (result.has_role(&"Neck") or result.has_role(&"Head")) or not result.has_role(&"Chest"):
		_cap(result, &"carry_pose", Status.FALLBACK, "carry anchors fall back to the head and the single spine bone")
	else:
		_cap(result, &"carry_pose", Status.SUPPORTED, "")
	_cap(result, &"unarmed", Status.SUPPORTED if legs_ok else Status.UNSUPPORTED, "no equipment is required")
	_cap(result, &"object_interaction", Status.NOT_IMPLEMENTED if arms_ok else Status.UNSUPPORTED, "no interaction presentation exists yet" if arms_ok else "no usable arm chains")
	_cap(result, &"head_attention", Status.NOT_IMPLEMENTED if result.has_role(&"Head") and result.has_role(&"Neck") else Status.UNSUPPORTED, "no look-at presentation exists yet" if result.has_role(&"Neck") else "no neck bone")

## Can this body physically carry the equipment? (Presentation compatibility only; gameplay decides what is equipped and what may be done with it.)
static func supports_equipment(result: Resolved, equipment: EquipmentPresentation) -> Diagnostics:
	var diag := Diagnostics.new()
	for socket_name: StringName in equipment.required_sockets:
		if not result.sockets.has(socket_name):
			diag.error(&"E_EQUIPMENT_SOCKET", socket_name, "'%s' needs socket '%s', which this rig profile does not define" % [equipment.display_name, socket_name], "add the socket to the rig profile")
	if equipment.two_handed and not result.supports(&"two_arm_ik"):
		diag.error(&"E_EQUIPMENT_TWO_HANDED", &"", "'%s' is two-handed but the rig has no two-arm chain" % equipment.display_name)
	return diag
