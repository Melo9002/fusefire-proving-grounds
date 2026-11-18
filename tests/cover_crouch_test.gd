extends SceneTree
## Procedural cover crouch: depth follows cover height within human limits, the feet stay on the
## floor, the knees bend forward, very low cover kneels, and aiming never crouches deeper than hiding.
## Presentation only: it writes no tactical state.

var failures := 0
var checks := 0
var _attachments := {}

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _p(bone: StringName) -> Vector3:
	return (_attachments[bone] as BoneAttachment3D).global_position

func _settle(rig: UnitVisualAdapter, height: float, aiming: bool) -> void:
	rig.last_cover_contact = {"type": MapCellData.CoverType.LOW, "height": height, "direction": Vector3.FORWARD}
	rig._aim_held = aiming
	rig._aim_release_left = 1000000.0
	rig._retarget_aim_blend()
	for i in 150: await process_frame

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	stage.add_child(rig)
	rig.position = Vector3.ZERO
	for i in 20: await process_frame
	for bone in [&"mixamorig_LeftFoot", &"mixamorig_RightFoot", &"mixamorig_LeftLeg", &"mixamorig_LeftUpLeg", &"mixamorig_Hips"]:
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = bone
		rig.skeleton.add_child(attachment)
		_attachments[bone] = attachment
	for i in 10: await process_frame
	var modifier := rig.crouch_modifier
	check(modifier != null, "The rig builds the procedural crouch layer")
	if modifier == null:
		quit(1)
		return
	check(modifier.max_depth > 0.25 and modifier.max_depth < 0.7, "The deepest natural crouch is human (%.3f m)" % modifier.max_depth)
	var standing_ankle := (_p(&"mixamorig_LeftFoot").y + _p(&"mixamorig_RightFoot").y) * 0.5
	rig.animation_controller.play(&"cover_low")

	var depths := {}
	for height in [1.4, 1.1, 0.9, 0.5]:
		await _settle(rig, height, false)
		depths[height] = modifier.depth
		check(modifier.depth <= modifier.max_depth + 0.0001, "Depth never exceeds the human limit (cover %.1f m: %.3f)" % [height, modifier.depth])
		var forward: Vector3 = rig.character_root.global_basis.z
		var front_foot := minf(_p(&"mixamorig_LeftFoot").y, _p(&"mixamorig_RightFoot").y) if modifier.kneel < 0.5 else _p(&"mixamorig_LeftFoot").y
		check(absf(front_foot - standing_ankle) < 0.035, "The planted foot stays on the floor (cover %.1f m: ankle %.3f, standing %.3f)" % [height, front_foot, standing_ankle])
		if modifier.kneel < 0.5 and modifier.depth > 0.1:
			var knee_ahead := (_p(&"mixamorig_LeftLeg") - _p(&"mixamorig_LeftUpLeg")).dot(forward)
			check(knee_ahead > 0.1, "Knees bend forward, not sideways (cover %.1f m: %.3f m ahead of the hip)" % [height, knee_ahead])
			var sideways := absf((_p(&"mixamorig_LeftLeg") - _p(&"mixamorig_LeftUpLeg")).dot(rig.character_root.global_basis.x))
			check(sideways < 0.08, "Knees do not splay sideways (cover %.1f m: %.3f m)" % [height, sideways])
		print("cover %.1f: depth %.3f kneel %.2f" % [height, modifier.depth, modifier.kneel])
	check(depths[1.4] <= depths[1.1] + 0.001 and depths[1.1] <= depths[0.9] + 0.001 and depths[0.9] <= depths[0.5] + 0.001, "Lower cover never asks for a shallower crouch")
	check(depths[1.4] < depths[0.9] - 0.05, "Tall low-cover asks for a clearly shallower crouch than short cover")

	await _settle(rig, 0.5, false)
	check(modifier.kneel > 0.9, "Very low cover goes down on one knee (kneel %.2f)" % modifier.kneel)
	await _settle(rig, 1.4, false)
	check(modifier.kneel < 0.1, "Tall low-cover is hidden behind by crouching, not kneeling (kneel %.2f)" % modifier.kneel)

	await _settle(rig, 1.1, false)
	var hiding_depth := modifier.depth
	await _settle(rig, 1.1, true)
	check(modifier.depth <= hiding_depth + 0.001, "Aiming never crouches deeper than hiding (%.3f vs %.3f)" % [modifier.depth, hiding_depth])

	# Out of cover everything returns to standing.
	rig.last_cover_contact = {"type": MapCellData.CoverType.NONE, "direction": Vector3.ZERO}
	rig._aim_held = false
	rig.animation_controller.play(&"rifle_idle")
	for i in 150: await process_frame
	check(modifier.depth < 0.01 and modifier.kneel < 0.01, "Leaving cover stands her back up (depth %.3f, kneel %.2f)" % [modifier.depth, modifier.kneel])
	print("Cover crouch: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
