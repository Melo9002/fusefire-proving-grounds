extends SceneTree

const DEMO := preload("res://art/characters/vroid_proof/demo/vroid_weapon_ik_demo.tscn")

var failed := false


func _initialize() -> void:
	var demo := DEMO.instantiate()
	root.add_child(demo)
	for frame in 3:
		await process_frame

	var skeleton := demo.find_child("Skeleton3D", true, false) as Skeleton3D
	var ik := demo.find_child("WeaponArmIK", true, false) as TwoBoneIK3D
	var attachment := demo.find_child("RightHandWeaponSocket", true, false) as BoneAttachment3D
	var support_target := demo.find_child("SupportHandTarget", true, false) as Node3D
	var muzzle := demo.find_child("MuzzleSocket", true, false) as Node3D
	var weapon_origin := demo.find_child("WeaponOrigin", true, false) as Node3D

	_assert(skeleton != null, "demo contains the VRoid skeleton")
	_assert(ik != null and ik.setting_count == 2 and ik.active, "two active arm IK chains")
	_assert(attachment != null and attachment.bone_name == &"J_Bip_R_Hand", "AUG follows right hand")
	_assert(support_target != null, "AUG exposes support-hand target")
	_assert(muzzle != null, "AUG preserves muzzle marker")
	_assert(weapon_origin != null, "AUG preserves weapon origin")
	_assert(ik.get_root_bone_name(0) == &"J_Bip_R_UpperArm", "right IK begins at upper arm")
	_assert(ik.get_end_bone_name(0) == &"J_Bip_R_Hand", "right IK ends at hand")
	_assert(ik.get_root_bone_name(1) == &"J_Bip_L_UpperArm", "left IK begins at upper arm")
	_assert(ik.get_end_bone_name(1) == &"J_Bip_L_Hand", "left IK ends at hand")

	# Skeleton modifiers are applied during a deferred skeleton pass and their
	# output is reset afterward. Sample precisely when this modifier finishes.
	await ik.modification_processed
	var right_target := demo.find_child("RightHandTarget", true, false) as Node3D
	var right_distance := _bone_distance_to_target(skeleton, &"J_Bip_R_Hand", right_target)
	var left_distance := _bone_distance_to_target(skeleton, &"J_Bip_L_Hand", support_target)
	_assert(right_distance < 0.03, "right hand reaches firing-hand target (%.3f m)" % right_distance)
	_assert(left_distance < 0.03, "left hand reaches AUG support target (%.3f m)" % left_distance)

	# Toggling the modifier changes the wrist basis. The presentation layer must
	# keep the rifle aim stable after every completed skeleton update.
	var stable_muzzle_direction := (muzzle.global_position - weapon_origin.global_position).normalized()
	for enabled in [false, true, false, true]:
		ik.active = enabled
		await skeleton.skeleton_updated
		await process_frame
		var muzzle_direction := (muzzle.global_position - weapon_origin.global_position).normalized()
		var aim_dot := muzzle_direction.dot(stable_muzzle_direction)
		_assert(aim_dot > 0.99, "AUG aim survives IK toggle (dot %.3f, direction %s)" % [aim_dot, muzzle_direction])

	if not failed:
		print("[VRoidWeaponIK] PASS — right-hand AUG attachment; left support-hand target; two deterministic arm chains")
	demo.queue_free()
	await process_frame
	quit(1 if failed else 0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failed = true
	push_error("[VRoidWeaponIK] FAIL — %s" % message)


func _bone_distance_to_target(skeleton: Skeleton3D, bone_name: StringName, target: Node3D) -> float:
	var bone_idx := skeleton.find_bone(bone_name)
	var bone_world_position := skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx).origin
	return bone_world_position.distance_to(target.global_position)
