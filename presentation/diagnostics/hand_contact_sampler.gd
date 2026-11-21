class_name HandContactSampler
extends RefCounted
## Diagnostic measurements of where a character's hands are, relative to where the weapon rig intends
## them to be. Read-only: it never writes to the skeleton, the weapon or any animation state, and it is
## only ever created by diagnostic tools (the pose workbench, tests, capture scripts), never by gameplay.
##
## Coordinate space: every position is in WORLD space, in metres. Bone positions come from the skeleton's
## pose (`get_bone_global_pose`) transformed by `skeleton.global_transform`, so they are the final pose
## when sampled after the skeleton has finished its modifiers (see HandContactDiagnostics: it samples in
## the `skeleton_updated` callback). Sampled earlier in a frame, the same call returns the previous
## update's pose: `meta.timing` records when a sample was taken so the two can be told apart.
##
## What is DIRECT and what is APPROXIMATE (also in KIND, used by the readout):
##   direct: bone and marker positions, wrist-to-IK-target distance, arm reach, reach margin, elbow angle,
##           hand orientation derived from the hand bone, finger joint positions.
##   approx: the "palm centre" (midpoint of the wrist and the knuckle line: the skeleton has no palm bone),
##           anything built on it (palm-to-intended-contact, contact displacement) and the palm-facing
##           direction (the plane of the knuckles; its sign is taken from the rest pose, which the
##           production hand grip also assumes faces down).
## Not measurable with this data: mesh surface contact or penetration. No grip radius or surface exists in
## the weapon profile, so finger-to-grip distances are to the grip CENTRE point, not to a surface.

const DOMINANT := 0
const SUPPORT := 1
const HAND_NAMES := ["dominant", "support"]
const FINGER_NAMES := ["Thumb", "Index", "Middle", "Ring", "Pinky"]

const KIND := {
	"wrist_to_ik_target": "direct",
	"palm_to_intended": "approx",
	"finger_direction_error_deg": "direct",
	"palm_normal_error_deg": "approx",
	"reach": "direct",
	"reach_margin": "direct",
	"elbow_angle_deg": "direct",
	"palm_in_weapon_frame": "approx",
	"finger_joints_to_grip_centre": "approx",
}

var rig: CharacterRig
var skeleton: Skeleton3D
var weapon: Node3D
var handling: WeaponHandlingProfile
## Per hand (DOMINANT, SUPPORT): bone indices and rest-pose reference data. See setup().
var _hands: Array[Dictionary] = [{}, {}]
var setup_issues: Array[String] = []

## `p_rig` is a CharacterRig (or a subclass such as TacticalCharacterAdapter or the pose workbench).
func setup(p_rig: Node3D) -> bool:
	setup_issues.clear()
	rig = p_rig
	skeleton = rig.get("skeleton") as Skeleton3D
	weapon = rig.get("weapon") as Node3D
	handling = rig.get("handling") as WeaponHandlingProfile
	if skeleton == null or weapon == null or handling == null:
		setup_issues.append("The rig has no skeleton, weapon or handling profile yet")
		return false
	var arms: Array = [rig.get("right_arm_bones"), rig.get("left_arm_bones")]
	var scale := _skeleton_scale()
	for hand in 2:
		var bones: Array = arms[hand]
		var data := {"upper": skeleton.find_bone(bones[0]), "fore": skeleton.find_bone(bones[1]), "hand": skeleton.find_bone(bones[2]), "fingers": []}
		if int(data.upper) < 0 or int(data.fore) < 0 or int(data.hand) < 0:
			setup_issues.append("%s arm bones are missing from the skeleton" % HAND_NAMES[hand])
			return false
		var rest_upper := skeleton.get_bone_global_rest(data.upper)
		var rest_fore := skeleton.get_bone_global_rest(data.fore)
		var rest_hand := skeleton.get_bone_global_rest(data.hand)
		data["chain_length"] = (rest_upper.origin.distance_to(rest_fore.origin) + rest_fore.origin.distance_to(rest_hand.origin)) * scale
		data["upper_length"] = rest_upper.origin.distance_to(rest_fore.origin) * scale
		data["fore_length"] = rest_fore.origin.distance_to(rest_hand.origin) * scale
		data["rest_hand_basis"] = rest_hand.basis.orthonormalized()
		# Finger bones are named after the hand bone: <hand bone><Finger><joint 1..4> on this rig family.
		var fingers: Array = []
		for finger in FINGER_NAMES:
			var joints: Array[int] = []
			for joint in [1, 2, 3, 4]:
				joints.append(skeleton.find_bone(StringName("%s%s%d" % [bones[2], finger, joint])))
			fingers.append(joints)
		data["fingers"] = fingers
		data["has_fingers"] = not (fingers as Array).any(func(joints: Array) -> bool: return joints.has(-1))
		if not bool(data.has_fingers):
			setup_issues.append("%s hand: finger bones were not found by name; palm and finger measurements are unavailable" % HAND_NAMES[hand])
		else:
			var middle: int = fingers[2][0]
			var forward_rest := (skeleton.get_bone_global_rest(middle).origin - rest_hand.origin).normalized()
			var index_rest := skeleton.get_bone_global_rest(fingers[1][0]).origin
			var pinky_rest := skeleton.get_bone_global_rest(fingers[4][0]).origin
			var normal := forward_rest.cross((pinky_rest - index_rest).normalized()).normalized()
			if normal.dot(Vector3.DOWN) < 0.0:
				normal = -normal
			data["rest_forward"] = forward_rest
			data["rest_palm_normal"] = normal
			# How far the knuckle plane is from horizontal in the rest pose. The production grip assumes the
			# rest pose is a T-pose with the palms down; this measures that assumption instead of trusting it.
			data["rest_palm_vs_down_deg"] = rad_to_deg(acos(clampf(normal.dot(Vector3.DOWN), -1.0, 1.0)))
		_hands[hand] = data
	return true

func is_ready() -> bool:
	return skeleton != null and not _hands[0].is_empty() and not _hands[1].is_empty()

func _skeleton_scale() -> float:
	var scale := skeleton.global_basis.get_scale().y if skeleton.is_inside_tree() else 1.0
	return scale if scale > 0.0001 else 1.0

func _world(bone: int) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin

## One complete measurement of the current pose. `timing` is a free label stored in the sample ("post-update",
## "process", "manual"...). Returns {} when the sampler is not ready.
func sample(timing := "manual") -> Dictionary:
	if not is_ready() or not is_instance_valid(weapon) or not weapon.is_inside_tree():
		return {}
	var weapon_basis := weapon.global_basis.orthonormalized()
	var weapon_frame := Transform3D(weapon_basis, weapon.global_position)
	var weapon_frame_inverse := weapon_frame.affine_inverse()
	var targets: Array[Node3D] = [rig.get("right_hand_target") as Node3D, rig.get("support_ik_target") as Node3D]
	var poles: Array[Node3D] = [rig.get("right_elbow_pole") as Node3D, rig.get("left_elbow_pole") as Node3D]
	var grip_modifier: HandGripModifier = rig.get("grip_modifier") as HandGripModifier
	var crouch_modifier: CoverCrouchModifier = rig.get("crouch_modifier") as CoverCrouchModifier
	var intended_palms: Array[Vector3] = [weapon.to_global(handling.firing_palm()), weapon.to_global(handling.support_palm())]
	var grip_centres: Array[Vector3] = [weapon.to_global(handling.firing_grip), weapon.to_global(handling.support_grip)]
	# Carrying: the hands' intent is the passenger contact (see CharacterRig.apply_carry_targets), not the weapon's grips.
	var carry: Array = rig.get("carry_contact_report") if rig.get("carry_contact_report") != null else []
	for hand in 2:
		if hand < carry.size() and not (carry[hand] as Dictionary).is_empty():
			intended_palms[hand] = carry[hand].intended_palm
			grip_centres[hand] = carry[hand].point
	var skeleton_basis := skeleton.global_basis.orthonormalized()
	var points := {
		"stock": weapon.to_global(handling.stock_rear),
		"sight": weapon.to_global(handling.sight),
		"firing_grip": grip_centres[0],
		"support_grip": grip_centres[1],
	}
	var hands: Array[Dictionary] = []
	for hand in 2:
		var data: Dictionary = _hands[hand]
		var result := {"name": HAND_NAMES[hand]}
		var shoulder := _world(data.upper)
		var elbow := _world(data.fore)
		var wrist := _world(data.hand)
		var target: Vector3 = targets[hand].global_position if is_instance_valid(targets[hand]) else Vector3.INF
		result["ik_target"] = target
		result["wrist"] = wrist
		result["wrist_to_ik_target"] = wrist.distance_to(target) if target.is_finite() else INF
		result["shoulder"] = shoulder
		result["elbow"] = elbow
		result["pole"] = poles[hand].global_position if is_instance_valid(poles[hand]) else Vector3.INF
		result["elbow_to_pole"] = elbow.distance_to(result.pole) if (result.pole as Vector3).is_finite() else INF
		# Reach: straight shoulder-to-wrist distance against the arm's own segment lengths (from the rest pose).
		var reach := shoulder.distance_to(wrist)
		var chain: float = data.chain_length
		result["reach"] = reach
		result["arm_length"] = chain
		result["reach_fraction"] = reach / chain
		result["reach_margin"] = chain - reach
		var to_shoulder := (shoulder - elbow).normalized()
		var to_wrist := (wrist - elbow).normalized()
		result["elbow_angle_deg"] = rad_to_deg(acos(clampf(to_shoulder.dot(to_wrist), -1.0, 1.0)))
		result["intended_palm"] = intended_palms[hand]
		result["grip_centre"] = grip_centres[hand]
		var carry_entry: Dictionary = carry[hand] if hand < carry.size() else {}
		if not carry_entry.is_empty():
			result["contact"] = String(carry_entry.contact)
		if bool(data.has_fingers):
			var fingers: Array = data.fingers
			var knuckles := (_world(fingers[1][0]) + _world(fingers[2][0]) + _world(fingers[3][0]) + _world(fingers[4][0])) * 0.25
			var palm := (wrist + knuckles) * 0.5
			result["knuckle_centre"] = knuckles
			result["palm"] = palm
			result["palm_to_intended"] = palm.distance_to(intended_palms[hand])
			result["palm_in_weapon_frame"] = weapon_frame_inverse * palm
			result["wrist_in_weapon_frame"] = weapon_frame_inverse * wrist
			var tips: Array[Vector3] = []
			var mids: Array[Vector3] = []
			for finger in 5:
				tips.append(_world(fingers[finger][3]))
				mids.append(_world(fingers[finger][1]))
			result["fingertips"] = tips
			result["finger_mid_joints"] = mids
			var distances: Array[float] = []
			for finger in range(1, 5):
				distances.append(mids[finger].distance_to(grip_centres[hand]))
			result["finger_joints_to_grip_centre"] = distances
			result["thumb_tip_to_grip_centre"] = tips[0].distance_to(grip_centres[hand])
			# Hand orientation now: the hand bone's rotation since the rest pose applied to the rest axes.
			var turn: Basis = skeleton.get_bone_global_pose(data.hand).basis.orthonormalized() * (data.rest_hand_basis as Basis).inverse()
			var finger_direction: Vector3 = (skeleton_basis * (turn * (data.rest_forward as Vector3))).normalized()
			var palm_normal: Vector3 = (skeleton_basis * (turn * (data.rest_palm_normal as Vector3))).normalized()
			result["finger_direction"] = finger_direction
			result["palm_normal"] = palm_normal
			var intended_direction := (weapon_basis * handling.hand_forward()).normalized()
			if not carry_entry.is_empty():
				intended_direction = carry_entry.intended_finger_direction
			result["intended_finger_direction"] = intended_direction
			result["finger_direction_error_deg"] = rad_to_deg(acos(clampf(finger_direction.dot(intended_direction), -1.0, 1.0)))
			if grip_modifier != null:
				var palm_index := 1 if hand == DOMINANT else 0   # the grip modifier indexes hands left = 0, right = 1
				var intended_normal: Vector3 = (weapon_basis * (grip_modifier.palm_normals[palm_index] as Vector3)).normalized()
				if not carry_entry.is_empty():
					intended_normal = carry_entry.intended_palm_normal
				result["intended_palm_normal"] = intended_normal
				result["palm_normal_error_deg"] = rad_to_deg(acos(clampf(palm_normal.dot(intended_normal), -1.0, 1.0)))
		hands.append(result)
	var meta := {
		"timing": timing,
		"frame": Engine.get_process_frames(),
		"state": String(rig.get("animation_controller").get("current_state")) if rig.get("animation_controller") != null else "",
		"aim_blend": float(rig.get("aim_blend")),
		"crouch_depth": crouch_modifier.depth if crouch_modifier != null else 0.0,
		"kneel": crouch_modifier.kneel if crouch_modifier != null else 0.0,
		"weapon_scale": handling.scale,
		"skeleton_scale": _skeleton_scale(),
		"weapon_basis": weapon_basis,
	}
	# What the WeaponPose modifier did about the support arm's reach in the last pass (if the rig has one).
	var pose_modifier: Variant = rig.get("weapon_pose_modifier")
	meta["weapon_pose_modifier"] = pose_modifier != null and bool(rig.get("weapon_pose_modifier_enabled"))
	if pose_modifier != null and bool(meta.weapon_pose_modifier):
		var modifier_report: Dictionary = pose_modifier.report
		if bool(modifier_report.get("available", false)):
			meta["protraction_base_deg"] = float(modifier_report.base_degrees)
			meta["protraction_extra_deg"] = float(modifier_report.extra_degrees)
			meta["protraction_total_deg"] = float(modifier_report.total_degrees)
			meta["protraction_limit_deg"] = float(modifier_report.limit_degrees)
			meta["protraction_limited"] = bool(modifier_report.limited)
			meta["support_deficit_mm"] = float(modifier_report.deficit) * 1000.0
			meta["support_comfort_deficit_mm"] = float(modifier_report.comfort_deficit) * 1000.0
	# Is the weapon where the rig says it should be right now? (Detects a weapon that lags the skeleton update.)
	if rig.has_method("_rifle_local_basis") and is_instance_valid(rig.get("character_root")):
		var expected: Basis = ((rig.get("character_root") as Node3D).global_basis * (rig.call("_rifle_local_basis") as Basis)).orthonormalized()
		meta["weapon_basis_error_deg"] = rad_to_deg(expected.get_rotation_quaternion().angle_to(weapon_basis.get_rotation_quaternion()))
	return {"meta": meta, "hands": hands, "points": points}

## A compact copy of a sample's numbers for logs and baselines: metres and degrees, finite values only.
static func scalars(measurement: Dictionary) -> Dictionary:
	var out := {"meta": (measurement.get("meta", {}) as Dictionary).duplicate(), "hands": []}
	(out.meta as Dictionary).erase("weapon_basis")
	for hand: Dictionary in measurement.get("hands", []):
		var entry := {}
		for key: String in hand:
			var value: Variant = hand[key]
			if value is float or value is int:
				entry[key] = snappedf(float(value), 0.00001)
			elif value is Vector3 and key.ends_with("_in_weapon_frame"):
				entry[key] = [snappedf(value.x, 0.00001), snappedf(value.y, 0.00001), snappedf(value.z, 0.00001)]
			elif key == "finger_joints_to_grip_centre":
				entry[key] = (value as Array).map(func(d: float) -> float: return snappedf(d, 0.00001))
		(out.hands as Array).append(entry)
	return out
