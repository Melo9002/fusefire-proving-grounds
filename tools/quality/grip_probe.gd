extends SceneTree
## Where are the hands, palms and stock relative to the rifle's grips and the body? Everything is
## printed in the weapon's own frame (+z toward the muzzle, y up) unless noted, in metres.
##   godot_console --headless --path . --script res://tools/quality/grip_probe.gd
## First prints an occupancy map of the weapon mesh below the barrel line (to find the grips), then
## the aim-pose measurements.
const STOCK_REAR := Vector3(-0.007, 0.044, -0.395)
const PISTOL_GRIP := Vector3(-0.042, -0.055, -0.015)  # palm target on the firing grip (profile)
const FRONT_HANDLE := Vector3(0.028, -0.04, 0.20)  # palm target on the front handle (profile)

var _attachments := {}

func _initialize() -> void:
	_run.call_deferred()

func _attach(skeleton: Skeleton3D, bone: StringName) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	_attachments[bone] = attachment

func _w(rig: UnitVisualAdapter, point: Vector3) -> Vector3:
	return rig.weapon.global_transform.affine_inverse() * point

func _bone(bone: StringName) -> Vector3:
	return (_attachments[bone] as BoneAttachment3D).global_position

func _run() -> void:
	var weapon_scene := load("res://art/weapons/aug/models/aug_runtime_socketed.glb") as PackedScene
	var probe := weapon_scene.instantiate() as Node3D
	root.add_child(probe)
	var mesh_node := probe.find_child("AUG_Runtime", true, false) as MeshInstance3D
	var to_weapon := probe.global_transform.affine_inverse() * mesh_node.global_transform
	var cells := {}
	for surface in mesh_node.mesh.get_surface_count():
		for vertex: Vector3 in mesh_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			var point := to_weapon * vertex
			var key := Vector2i(int(floor(point.z / 0.02)), int(floor(point.y / 0.02)))
			cells[key] = int(cells.get(key, 0)) + 1
	# Rows from high y to low y, columns from rear to front z.
	print("GMAP  columns z -0.40 .. 0.40 step 0.02 (rear to muzzle); rows y 0.14 .. -0.16")
	for row in range(7, -9, -1):
		var line := "GMAP y %+.2f " % (row * 0.02)
		for column in range(-20, 20):
			line += "#" if cells.has(Vector2i(column, row)) else "."
		print(line)
	probe.queue_free()

	var stage := Node3D.new()
	root.add_child(stage)
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	stage.add_child(rig)
	rig.position = Vector3.ZERO
	for i in 20: await process_frame
	var skeleton: Skeleton3D = rig.skeleton
	for bone in [&"mixamorig_RightHand", &"mixamorig_RightHandMiddle1", &"mixamorig_RightHandIndex1", &"mixamorig_RightHandPinky1", &"mixamorig_LeftHandIndex1", &"mixamorig_LeftHandPinky1", &"mixamorig_LeftHand", &"mixamorig_LeftHandMiddle1", &"mixamorig_LeftHandMiddle4", &"mixamorig_RightHandMiddle4", &"mixamorig_LeftHandIndex4", &"mixamorig_RightHandIndex4", &"mixamorig_RightArm", &"mixamorig_RightForeArm", &"mixamorig_LeftArm", &"mixamorig_LeftForeArm", &"mixamorig_Spine2", &"mixamorig_Spine1", &"mixamorig_RightShoulder", &"mixamorig_Neck"]:
		_attach(skeleton, bone)
	# Palm normal from the knuckle row, signed so that it points down in the rest T-pose.
	var rest_sign := {}
	for side in ["Left", "Right"]:
		var n_rest := _palm_normal(side)
		rest_sign[side] = 1.0 if n_rest.dot(Vector3.DOWN) > 0.0 else -1.0
	rig.animation_controller.play(&"aim")
	rig.presenter.aim.held = true
	rig.presenter.aim.release_left = 1000000.0
	for i in 90: await process_frame
	await create_timer(0.8).timeout
	var facing: Basis = rig.character_root.global_basis
	var right_palm := (_bone(&"mixamorig_RightHand") + _bone(&"mixamorig_RightHandMiddle1")) * 0.5
	var left_palm := (_bone(&"mixamorig_LeftHand") + _bone(&"mixamorig_LeftHandMiddle1")) * 0.5
	print("GRIP right wrist %s palm %s -> pistol grip error %s" % [_r(_w(rig, _bone(&"mixamorig_RightHand"))), _r(_w(rig, right_palm)), _r(_w(rig, right_palm) - PISTOL_GRIP)])
	print("GRIP left  wrist %s palm %s -> front handle error %s" % [_r(_w(rig, _bone(&"mixamorig_LeftHand"))), _r(_w(rig, left_palm)), _r(_w(rig, left_palm) - FRONT_HANDLE)])
	var rear := rig.weapon.to_global(STOCK_REAR)
	var arm := _bone(&"mixamorig_RightArm")
	var rel: Vector3 = facing.inverse() * (rear - arm)
	print("STOCK rear plate relative to right shoulder joint, character frame (x lateral, y up, z forward): %s" % _r(rel))
	var chest: Vector3 = facing.inverse() * (rear - _bone(&"mixamorig_Spine2"))
	print("STOCK rear plate relative to chest (Spine2), character frame: %s" % _r(chest))
	print("ARM lengths: right upper %.3f fore %.3f | left upper %.3f fore %.3f" % [_bone(&"mixamorig_RightArm").distance_to(_bone(&"mixamorig_RightForeArm")), _bone(&"mixamorig_RightForeArm").distance_to(_bone(&"mixamorig_RightHand")), _bone(&"mixamorig_LeftArm").distance_to(_bone(&"mixamorig_LeftForeArm")), _bone(&"mixamorig_LeftForeArm").distance_to(_bone(&"mixamorig_LeftHand"))])
	print("ARM reach: right shoulder->wrist %.3f | left shoulder->wrist %.3f" % [_bone(&"mixamorig_RightArm").distance_to(_bone(&"mixamorig_RightHand")), _bone(&"mixamorig_LeftArm").distance_to(_bone(&"mixamorig_LeftHand"))])
	print("MARKERS stock_marker %s shoulder_marker (world rel. arm, char frame) %s" % [_r(_w(rig, rig.stock_marker.global_position)), _r(facing.inverse() * (rig.shoulder_marker.global_position - arm))])
	for side in ["Left", "Right"]:
		var normal: Vector3 = _palm_normal(side) * rest_sign[side]
		var along: Vector3 = _bone(StringName("mixamorig_%sHandMiddle1" % side)) - _bone(StringName("mixamorig_%sHand" % side))
		var tip := _bone(StringName("mixamorig_%sHandMiddle4" % side))
		var wrist_position := _bone(StringName("mixamorig_%sHand" % side))
		var tip_offset: Vector3 = tip - wrist_position
		print("FINGER %s middle tip: %.3f m from wrist, %.3f m toward the palm side (negative = bent backward)" % [side, tip_offset.length(), tip_offset.dot(normal)])
		print("HAND %s fingers point (weapon frame) %s | palm faces %s" % [side, _r(rig.weapon.global_basis.orthonormalized().inverse() * along.normalized()), _r(rig.weapon.global_basis.orthonormalized().inverse() * normal)])
	quit(0)

func _r(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]

func _palm_normal(side: String) -> Vector3:
	var wrist := _bone(StringName("mixamorig_%sHand" % side))
	var index_finger := _bone(StringName("mixamorig_%sHandIndex1" % side)) - wrist
	var pinky := _bone(StringName("mixamorig_%sHandPinky1" % side)) - wrist
	return index_finger.cross(pinky).normalized()
