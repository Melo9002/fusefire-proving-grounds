extends SceneTree
## Which way does a bone rotate the limb? Rotates a bone by 30 degrees about each of its own local
## axes (with the animation stopped) and prints where the child joint moves, in the character's
## frame (x = character left/right, y = up, z = forward).
##   godot_console --headless --path . --script res://tools/quality/bone_axis_probe.gd
const CASES := [
	[&"mixamorig_LeftUpLeg", &"mixamorig_LeftLeg"],
	[&"mixamorig_LeftLeg", &"mixamorig_LeftFoot"],
	[&"mixamorig_Spine", &"mixamorig_Spine2"],
	[&"mixamorig_Spine1", &"mixamorig_Head"],
]

var _attachments := {}

func _initialize() -> void:
	_run.call_deferred()

func _local(rig: TacticalCharacterAdapter, bone: StringName) -> Vector3:
	return rig.rig.character_root.global_basis.inverse() * ((_attachments[bone] as BoneAttachment3D).global_position - rig.rig.character_root.global_position)

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as TacticalCharacterAdapter
	stage.add_child(rig)
	rig.position = Vector3.ZERO
	for i in 20: await process_frame
	var skeleton: Skeleton3D = rig.rig.skeleton
	for pair in CASES:
		for bone in pair:
			if not _attachments.has(bone):
				var attachment := BoneAttachment3D.new()
				attachment.bone_name = bone
				skeleton.add_child(attachment)
				_attachments[bone] = attachment
	rig.rig.animation_controller.animation_tree.active = false
	rig.rig.animation_controller.animation_player.stop()
	skeleton.reset_bone_poses()
	for i in 5: await process_frame
	for pair in CASES:
		var bone: StringName = pair[0]
		var child: StringName = pair[1]
		var index := skeleton.find_bone(bone)
		var rest_basis := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		skeleton.reset_bone_poses()
		await process_frame
		await process_frame
		var base := _local(rig, child)
		var rest_axes := skeleton.get_bone_rest(index).basis
		print("AXIS %s rest basis x=%s y=%s z=%s" % [bone, rest_axes.x.snapped(Vector3.ONE * 0.01), rest_axes.y.snapped(Vector3.ONE * 0.01), rest_axes.z.snapped(Vector3.ONE * 0.01)])
		for axis_name in ["X", "Y", "Z"]:
			var axis := Vector3.RIGHT if axis_name == "X" else Vector3.UP if axis_name == "Y" else Vector3.BACK
			skeleton.set_bone_pose_rotation(index, rest_basis * Quaternion(axis, deg_to_rad(30.0)))
			await process_frame
			await process_frame
			var moved := _local(rig, child) - base
			print("AXIS   %-20s +30 about local %s moves %s by (x %.3f, y %.3f, z %.3f)" % [bone, axis_name, child, moved.x, moved.y, moved.z])
		skeleton.reset_bone_poses()
	quit(0)
