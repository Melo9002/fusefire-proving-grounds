class_name WeaponPoseModifier
extends SkeletonModifier3D
## Places the weapon's hand targets from the shoulder as it is in THIS skeleton pass, then makes sure the
## support arm can reach its target without stretching.
##
## Why a modifier: the stock, both hand targets and the elbow poles hang off the right shoulder. A node's
## `_process` runs before the skeleton's modifiers, and outside the modifier pass `get_bone_global_pose` does not
## include what CoverCrouch does (hips, spine lean, support-shoulder reach). Read there, the shoulder was up to
## 29 cm from where it ends up in a half-kneel, and the support target ended up beyond the arm's length. Inside
## the modifier pass the pose includes every earlier modifier, so this node reads the real shoulder.
##
## Evaluation order of the skeleton's modifiers (child order, set by CharacterRig):
##   CoverCrouch -> WeaponPose -> WeaponArmIK -> HandGrip
##
## The target FORMULAS are CharacterRig.apply_weapon_targets (one place, also used by the legacy path); this
## node only supplies the shoulder and then adjusts the support shoulder.
##
## SUPPORT-REACH ADJUSTMENT. CoverCrouch applies a base support-shoulder protraction (CharacterRig's
## SUPPORT_REACH_DEGREES while the weapon is up). If the support wrist target would still need the arm nearly
## straight, this node adds the least extra protraction that brings the elbow down to `support_elbow_comfort_degrees`,
## never beyond `support_protraction_limit_degrees` in total. It does not move the target, stretch a bone or change
## a length. When the limit is reached it stops and REPORTS what is still missing (`report`), instead of hiding it.
## Both limits are properties of the CharacterRig, so another character or weapon can set its own.
##
## The default limit, 18 degrees in total, is deliberately conservative. Anatomy sources (StatPearls, Kenhub,
## GPnotebook, Wikimsk) give about 30 to 35 degrees for the whole protraction-retraction range of the sternoclavicular
## joint. From neutral that is roughly half in each direction, so about 17 to 18 degrees of protraction, which is what
## the limit allows. The scapula glides on the ribs as well, so real shoulders can protract further, but that
## contribution is not claimed here. The existing base of 14 degrees leaves 4 degrees of headroom.

var rig: Node3D
## What the last pass did: base/extra/total/limit protraction (degrees), whether the limit was hit, the support arm's
## distance to its target, its length, the remaining deficit (metres, 0 when reachable) and the elbow bend at that distance.
var report: Dictionary = {}
## The right shoulder (world space) this pass read. Exposed so tests can prove it is the same-pass pose.
var last_shoulder_world := Vector3.INF
var passes := 0

var _right_shoulder := -1
var _chest := -1
var _left_upper := -1
var _left_fore := -1
var _left_hand := -1
var _upper_length := 0.0
var _fore_length := 0.0

func setup(p_rig: Node3D) -> bool:
	rig = p_rig
	var skeleton: Skeleton3D = rig.get("skeleton")
	var right_bones: Array = rig.get("right_arm_bones")
	var left_bones: Array = rig.get("left_arm_bones")
	_right_shoulder = skeleton.find_bone(right_bones[0])
	_chest = skeleton.find_bone(rig.get("torso_bone_name"))
	_left_upper = skeleton.find_bone(left_bones[0])
	_left_fore = skeleton.find_bone(left_bones[1])
	_left_hand = skeleton.find_bone(left_bones[2])
	if _right_shoulder < 0 or _left_upper < 0 or _left_fore < 0 or _left_hand < 0:
		return false
	measure_arms(skeleton)
	return true

## The support arm's segment lengths in metres, from the rest pose and the skeleton's scale. Call again if the
## skeleton's proportions change (tests do).
func measure_arms(skeleton: Skeleton3D) -> void:
	var skeleton_scale := skeleton.global_basis.get_scale().y if skeleton.is_inside_tree() else 1.0
	if skeleton_scale <= 0.0001:
		skeleton_scale = 1.0
	var upper := skeleton.get_bone_global_rest(_left_upper).origin
	var fore := skeleton.get_bone_global_rest(_left_fore).origin
	var hand := skeleton.get_bone_global_rest(_left_hand).origin
	_upper_length = upper.distance_to(fore) * skeleton_scale
	_fore_length = fore.distance_to(hand) * skeleton_scale

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or rig == null or _right_shoulder < 0:
		return
	# Carrying someone (or IK switched off): the weapon targets are not used, so leave the pose alone.
	var arm_ik: Node = rig.get("arm_ik")
	if arm_ik == null or not arm_ik.active:
		return
	passes += 1
	last_shoulder_world = skeleton.global_transform * skeleton.get_bone_global_pose(_right_shoulder).origin
	# Carrying: the wrists belong to the carry contacts, not to the weapon. The weapon targets, the torso frame and the support
	# reach are skipped; the same arm IK, elbow guidance and hand grip then run on the contact targets.
	if bool(rig.call("carry_contacts_active")):
		var left_shoulder: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(_left_upper).origin
		rig.call("apply_carry_targets", [last_shoulder_world, left_shoulder], (rig.get("carry_passenger") as Node3D).call("anchor_world"))
		report = {"available": false}
		_guide_elbows(skeleton, true)
		return
	# The torso frame is read from the chest in this same pass, before any target is placed, so the stock, both
	# grips and (after the pass) the weapon itself are built from one frame.
	if _chest >= 0:
		var root_node: Node3D = rig.get("character_root")
		var chest_in_root: Basis = root_node.global_basis.orthonormalized().inverse() * skeleton.global_basis.orthonormalized() * skeleton.get_bone_global_pose(_chest).basis.orthonormalized()
		rig.call("update_torso_frame", chest_in_root, get_process_delta_time())
	rig.call("apply_weapon_targets", last_shoulder_world)
	_adjust_support_reach(skeleton)
	# A ladder (or obstacle) climbed: the hands go to its contacts over the weapon's targets.
	var holding := bool(rig.call("traversal_contacts_active"))
	if holding:
		rig.call("apply_traversal_hand_targets")
	_guide_elbows(skeleton, holding)

## Elbow poles from the final shoulders and hand targets of this pass (see CharacterRig.apply_elbow_guidance).
func _guide_elbows(skeleton: Skeleton3D, carrying := false) -> void:
	if _chest < 0:
		return
	var root_node: Node3D = rig.get("character_root")
	var skeleton_basis := skeleton.global_basis.orthonormalized()
	var deviation := skeleton.get_bone_global_pose(_chest).basis.orthonormalized() * skeleton.get_bone_global_rest(_chest).basis.orthonormalized().inverse()
	var chest_world := skeleton_basis * deviation * skeleton_basis.inverse() * root_node.global_basis.orthonormalized()
	var shoulders := [last_shoulder_world, skeleton.global_transform * skeleton.get_bone_global_pose(_left_upper).origin]
	rig.call("apply_elbow_guidance", shoulders, chest_world, carrying)

func _support_distance(skeleton: Skeleton3D, target: Vector3) -> float:
	return (skeleton.global_transform * skeleton.get_bone_global_pose(_left_upper).origin).distance_to(target)

func _adjust_support_reach(skeleton: Skeleton3D) -> void:
	var crouch: CoverCrouchModifier = rig.get("crouch_modifier") as CoverCrouchModifier
	var target_node: Node3D = rig.get("support_ik_target") as Node3D
	if crouch == null or not crouch.has_support_clavicle() or not is_instance_valid(target_node):
		report = {"available": false}
		return
	var target := target_node.global_position
	var arm_length := _upper_length + _fore_length
	var base: float = crouch.support_reach_degrees if crouch.support_reach_degrees > 0.05 else 0.0
	var limit := float(rig.get("support_protraction_limit_degrees"))
	var comfort := deg_to_rad(float(rig.get("support_elbow_comfort_degrees")))
	# Distance at which the elbow bend equals the comfort angle (law of cosines on the two segments).
	var comfort_distance := sqrt(maxf(0.0, _upper_length * _upper_length + _fore_length * _fore_length - 2.0 * _upper_length * _fore_length * cos(comfort)))
	comfort_distance = minf(comfort_distance, arm_length)
	var distance_base := _support_distance(skeleton, target)
	var extra := 0.0
	var headroom := maxf(0.0, limit - base)
	var clavicle := crouch.support_clavicle_bone()
	var animated_clavicle := skeleton.get_bone_pose_rotation(clavicle)
	if distance_base > comfort_distance and headroom > 0.0:
		crouch.set_support_reach(skeleton, base + headroom)
		var distance_max := _support_distance(skeleton, target)
		if distance_max >= distance_base:
			extra = 0.0   # more protraction does not bring the hand closer in this pose: do not apply it
		elif distance_max > comfort_distance:
			extra = headroom   # the limit is reached before the comfort bend: use all of it and report the rest
		else:
			var low := 0.0
			var high := headroom
			for iteration in int(rig.get("support_solve_iterations")):
				var middle := (low + high) * 0.5
				crouch.set_support_reach(skeleton, base + middle)
				if _support_distance(skeleton, target) > comfort_distance:
					low = middle
				else:
					high = middle
			extra = high
		# Leave the shoulder exactly as the animation and CoverCrouch had it when nothing was added.
		if extra > 0.0:
			crouch.set_support_reach(skeleton, base + extra)
		elif base > 0.05:
			crouch.set_support_reach(skeleton, base)
		else:
			skeleton.set_bone_pose_rotation(clavicle, animated_clavicle)
	var distance := _support_distance(skeleton, target)
	var interior := acos(clampf((_upper_length * _upper_length + _fore_length * _fore_length - distance * distance) / (2.0 * _upper_length * _fore_length), -1.0, 1.0)) if distance < arm_length else PI
	report = {
		"available": true,
		"base_degrees": base,
		"extra_degrees": extra,
		"total_degrees": base + extra,
		"limit_degrees": limit,
		"limited": extra >= headroom - 0.0001 and distance > comfort_distance + 0.0005 and headroom > 0.0,
		"support_distance": distance,
		"arm_length": arm_length,
		"deficit": maxf(0.0, distance - arm_length),
		"comfort_deficit": maxf(0.0, distance - comfort_distance),
		"elbow_degrees": rad_to_deg(interior),
	}
