extends SceneTree
## Measures where the weapon sits relative to the character in each pose, in metres, so a
## change to the weapon rig can be judged by numbers as well as by pictures.
##   godot_console --headless --path . --script res://tools/quality/aim_pose_report.gd [-- out.json]
## Prints one AIMREPORT line per state and writes JSON when a path is given.
## The eye is an estimate (between the head bone and the top of the head, nudged forward), so
## treat eye numbers as relative: compare before and after, not against an absolute truth.
const STATES := [&"rifle_idle", &"aim", &"shoot", &"cover_low", &"cover_high"]

func _initialize() -> void:
	_run.call_deferred()

## Bone attachments follow the final skinned pose that is actually rendered, including IK,
## so they are the trustworthy way to read where a bone really is.
var _attachments := {}

func _attach(skeleton: Skeleton3D, bone: StringName) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	_attachments[bone] = attachment

func _bone_world(_skeleton: Skeleton3D, bone: StringName) -> Vector3:
	return (_attachments[bone] as BoneAttachment3D).global_position if _attachments.has(bone) else Vector3.INF

func _round3(value: Vector3) -> Array:
	return [snappedf(value.x, 0.0001), snappedf(value.y, 0.0001), snappedf(value.z, 0.0001)]

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	stage.add_child(rig)
	rig.position = Vector3.ZERO  # the scene hangs 1 m below the unit centre; stand it on the floor here
	for i in 20: await process_frame
	var skeleton: Skeleton3D = rig.skeleton
	for bone in [&"mixamorig_Head", &"mixamorig_HeadTop_End", &"mixamorig_RightHand", &"mixamorig_LeftHand", &"mixamorig_Spine2", &"mixamorig_LeftLeg", &"mixamorig_RightLeg", &"mixamorig_LeftUpLeg", &"mixamorig_RightUpLeg", &"mixamorig_LeftFoot", &"mixamorig_RightFoot"]:
		_attach(skeleton, bone)
	for i in 10: await process_frame
	var report := {}
	for state in STATES:
		rig.animation_controller.play(state)
		# Let the blend tween, recoil and the animation tree settle.
		for i in 60: await process_frame
		await create_timer(0.7).timeout
		await process_frame
		var forward: Vector3 = rig.weapon.global_basis.z.normalized()
		var sight_origin: Vector3 = rig.sight_marker.global_position
		var head := _bone_world(skeleton, &"mixamorig_Head")
		var head_top := _bone_world(skeleton, &"mixamorig_HeadTop_End")
		var facing: Vector3 = rig.character_root.global_basis.z.normalized()
		var eye := head + (head_top - head) * 0.55 + facing * 0.085
		var along := (eye - sight_origin).dot(forward)
		var off_line := (eye - sight_origin - forward * along).length()
		var right_hand := _bone_world(skeleton, &"mixamorig_RightHand")
		var left_hand := _bone_world(skeleton, &"mixamorig_LeftHand")
		var chest := _bone_world(skeleton, &"mixamorig_Spine2")
		var entry := {
			"aim_blend": snappedf(rig.aim_blend, 0.001),
			"stock_to_shoulder": snappedf(rig.stock_marker.global_position.distance_to(rig.shoulder_marker.global_position), 0.0001),
			"right_hand_reach_error": snappedf(right_hand.distance_to(rig.right_hand_target.global_position), 0.0001),
			"support_hand_reach_error": snappedf(left_hand.distance_to(rig.support_ik_target.global_position), 0.0001),
			"eye_off_sight_line": snappedf(off_line, 0.0001),
			"eye_behind_sight": snappedf(along, 0.0001),
			"eye_height": snappedf(eye.y - rig.global_position.y, 0.0001),
			"muzzle_height": snappedf(rig.muzzle_socket.global_position.y - rig.global_position.y, 0.0001),
			"weapon_pitch_degrees": snappedf(rad_to_deg(asin(clampf(forward.y, -1.0, 1.0))), 0.01),
			"weapon_yaw_off_facing_degrees": snappedf(rad_to_deg(Vector2(forward.x, forward.z).angle_to(Vector2(facing.x, facing.z))), 0.01),
			"stock_to_chest_bone": snappedf(rig.stock_marker.global_position.distance_to(chest), 0.0001),
			# Legs, looking from the front: knees pinching inward show as knee spacing below hip spacing.
			"hip_spacing": snappedf(_bone_world(skeleton, &"mixamorig_LeftUpLeg").distance_to(_bone_world(skeleton, &"mixamorig_RightUpLeg")), 0.0001),
			"knee_spacing": snappedf(_bone_world(skeleton, &"mixamorig_LeftLeg").distance_to(_bone_world(skeleton, &"mixamorig_RightLeg")), 0.0001),
			"foot_spacing": snappedf(_bone_world(skeleton, &"mixamorig_LeftFoot").distance_to(_bone_world(skeleton, &"mixamorig_RightFoot")), 0.0001),
			# Ankle bones above the floor (a standing foot's ankle sits roughly 8 cm up; below that the sole is in the floor).
			"left_ankle_height": snappedf(_bone_world(skeleton, &"mixamorig_LeftFoot").y - rig.global_position.y, 0.0001),
			"right_ankle_height": snappedf(_bone_world(skeleton, &"mixamorig_RightFoot").y - rig.global_position.y, 0.0001),
			"knee_height":snappedf((_bone_world(skeleton, &"mixamorig_LeftLeg").y + _bone_world(skeleton, &"mixamorig_RightLeg").y) * 0.5 - rig.global_position.y, 0.0001),
			"stock_world": _round3(rig.stock_marker.global_position),
			"shoulder_world": _round3(rig.shoulder_marker.global_position),
			"sight_world": _round3(sight_origin),
			"muzzle_world": _round3(rig.muzzle_socket.global_position),
		}
		report[String(state)] = entry
		print("AIMREPORT ", state, " ", JSON.stringify(entry))
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0], FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	quit(0)
