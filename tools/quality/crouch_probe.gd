extends SceneTree
## Procedural crouch check: for several cover heights, hiding and aiming, prints the applied depth,
## whether the feet stay planted, the head height and how far the head leans forward.
##   godot_console --headless --path . --script res://tools/quality/crouch_probe.gd
const HEIGHTS := [0.3, 0.6, 0.9, 1.1, 1.4]

var _attachments := {}

func _initialize() -> void:
	_run.call_deferred()

func _p(bone: StringName) -> Vector3:
	return (_attachments[bone] as BoneAttachment3D).global_position

## Bone positions in the character's own frame (x right/left, y up, z forward) relative to the floor point.
func _dump(rig: UnitVisualAdapter, label: String) -> void:
	var inverse := rig.character_root.global_basis.inverse()
	var out := "CROUCH-DUMP %s" % label
	for bone in [&"mixamorig_Hips", &"mixamorig_Spine2", &"mixamorig_HeadTop_End", &"mixamorig_LeftUpLeg", &"mixamorig_LeftLeg", &"mixamorig_LeftFoot", &"mixamorig_RightUpLeg", &"mixamorig_RightLeg", &"mixamorig_RightFoot"]:
		var local := inverse * (_p(bone) - rig.character_root.global_position)
		out += "\n   %-22s x %.3f y %.3f z %.3f" % [bone, local.x, local.y, local.z]
	print(out)

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	stage.add_child(rig)
	rig.position = Vector3.ZERO
	for i in 20: await process_frame
	for bone in [&"mixamorig_Head", &"mixamorig_HeadTop_End", &"mixamorig_LeftFoot", &"mixamorig_RightFoot", &"mixamorig_Hips", &"mixamorig_LeftLeg", &"mixamorig_LeftUpLeg"]:
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = bone
		rig.skeleton.add_child(attachment)
		_attachments[bone] = attachment
	for i in 10: await process_frame
	var modifier := rig.crouch_modifier
	print("CROUCH modifier=", modifier != null)
	if modifier == null:
		quit(1)
		return
	print("CROUCH max_depth=%.3f standing_head=%.3f" % [modifier.max_depth, modifier.standing_head_height])
	for bone in [&"mixamorig_Spine2", &"mixamorig_RightLeg", &"mixamorig_RightUpLeg", &"mixamorig_RightFoot"]:
		var extra := BoneAttachment3D.new()
		extra.bone_name = bone
		rig.skeleton.add_child(extra)
		_attachments[bone] = extra
	rig.animation_controller.play(&"cover_low")
	for i in 30: await process_frame
	_dump(rig, "standing-ish")
	for height in HEIGHTS:
		for aiming in [false, true]:
			rig.last_cover_contact = {"type": MapCellData.CoverType.LOW, "height": height, "direction": Vector3.FORWARD}
			rig.presenter.aim.held = aiming
			rig.presenter.aim.release_left = 1000000.0
			for i in 120: await process_frame
			var forward: Vector3 = rig.character_root.global_basis.z
			var head := _p(&"mixamorig_HeadTop_End")
			var hips := _p(&"mixamorig_Hips")
			var lean := (head - hips).dot(forward)
			var knee_forward := (_p(&"mixamorig_LeftLeg") - _p(&"mixamorig_LeftUpLeg")).dot(forward)
			print("CROUCH h=%.2f %s depth=%.3f/%.3f head=%.3f lean=%.3f kneeFwd=%.3f ankles %.3f %.3f yaw=%.0f" % [height, "aim " if aiming else "hide", modifier.depth, modifier.max_depth, head.y, lean, knee_forward, _p(&"mixamorig_LeftFoot").y, _p(&"mixamorig_RightFoot").y, rad_to_deg(rig._cover_yaw)])
	rig.last_cover_contact = {"type": MapCellData.CoverType.LOW, "height": 0.9, "direction": Vector3.FORWARD}
	rig.presenter.aim.held = false
	for i in 120: await process_frame
	_dump(rig, "crouched h=0.9 hiding")
	quit(0)
