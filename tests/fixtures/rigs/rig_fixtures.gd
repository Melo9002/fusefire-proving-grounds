extends RefCounted
## Task 05 PROTOTYPE fixtures: two humanoid configurations described by the SAME schema.
##   A  MIRA: the real production skeleton (Mixamo names, T-pose, native scale 0.58 m hips shown at 1.6x, local bone axes rotated 90 degrees about Y, a head-top end bone, five-finger hands).
##   B  Alternate: a small SYNTHETIC skeleton, not a production character: Unreal-style names, a different hierarchy (a root bone, only two spine bones), A-pose arms, shorter legs and arms, wider
##      shoulders, facing -Z (the opposite of Godot's convention), bone local +X along each bone, no toes, no fingers, no head-top bone (so its height is declared).
const RigProfile := preload("res://presentation/characters/rig_profile/rig_profile.gd")
const Anatomy := preload("res://presentation/characters/rig_profile/rig_anatomy.gd")
const JointSpec := preload("res://presentation/characters/rig_profile/rig_joint_spec.gd")
const Socket := preload("res://presentation/characters/rig_profile/rig_socket.gd")
const EquipmentPresentation := preload("res://presentation/characters/equipment/equipment_presentation.gd")
const MIRA_MODEL := "res://art/characters/mira_0/models/mira_0_prototype.glb"

# ---------------------------------------------------------------- shared helpers

static func new_bone_map(pairs: Dictionary) -> BoneMap:
	var bone_map := BoneMap.new()
	bone_map.profile = SkeletonProfileHumanoid.new()
	for role: StringName in pairs:
		bone_map.set_skeleton_bone_name(role, pairs[role])
	return bone_map

static func joint(role: StringName, max_degrees: float, pole: Vector3) -> JointSpec:
	var spec := JointSpec.new()
	spec.role = role
	spec.min_degrees = 0.0
	spec.max_degrees = max_degrees
	spec.pole_direction = pole
	return spec

static func socket(socket_name: StringName, parent_role: StringName, offset := Transform3D.IDENTITY) -> Socket:
	var s := Socket.new()
	s.socket_name = socket_name
	s.parent_role = parent_role
	s.offset = offset
	return s

static func rifle() -> EquipmentPresentation:
	var e := EquipmentPresentation.new()
	e.display_name = "two-handed rifle"
	e.required_sockets = [&"weapon_dominant_hand", &"weapon_support_hand"]
	e.two_handed = true
	return e

# ---------------------------------------------------------------- A: MIRA

static func mira_profile() -> RigProfile:
	var p := RigProfile.new()
	p.display_name = "MIRA (Mixamo)"
	var pairs := {
		&"Hips": &"mixamorig_Hips", &"Spine": &"mixamorig_Spine", &"Chest": &"mixamorig_Spine1", &"UpperChest": &"mixamorig_Spine2",
		&"Neck": &"mixamorig_Neck", &"Head": &"mixamorig_Head",
		&"LeftShoulder": &"mixamorig_LeftShoulder", &"LeftUpperArm": &"mixamorig_LeftArm", &"LeftLowerArm": &"mixamorig_LeftForeArm", &"LeftHand": &"mixamorig_LeftHand",
		&"RightShoulder": &"mixamorig_RightShoulder", &"RightUpperArm": &"mixamorig_RightArm", &"RightLowerArm": &"mixamorig_RightForeArm", &"RightHand": &"mixamorig_RightHand",
		&"LeftUpperLeg": &"mixamorig_LeftUpLeg", &"LeftLowerLeg": &"mixamorig_LeftLeg", &"LeftFoot": &"mixamorig_LeftFoot", &"LeftToes": &"mixamorig_LeftToeBase",
		&"RightUpperLeg": &"mixamorig_RightUpLeg", &"RightLowerLeg": &"mixamorig_RightLeg", &"RightFoot": &"mixamorig_RightFoot", &"RightToes": &"mixamorig_RightToeBase",
	}
	for side in ["Left", "Right"]:
		# Mixamo fingers have four joints, the fourth an end bone; Godot's profile has three per finger (thumb: metacarpal, proximal, distal).
		for finger in [["Thumb", "ThumbMetacarpal", "ThumbProximal", "ThumbDistal"], ["Index", "IndexProximal", "IndexIntermediate", "IndexDistal"], ["Middle", "MiddleProximal", "MiddleIntermediate", "MiddleDistal"], ["Ring", "RingProximal", "RingIntermediate", "RingDistal"], ["Pinky", "LittleProximal", "LittleIntermediate", "LittleDistal"]]:
			for joint_index in 3:
				pairs[StringName(side + finger[joint_index + 1])] = StringName("mixamorig_%sHand%s%d" % [side, finger[0], joint_index + 1])
	p.skeleton_map = new_bone_map(pairs)
	var anatomy := Anatomy.new()
	anatomy.character_scale = 1.6
	anatomy.head_top_bone = &"mixamorig_HeadTop_End"
	anatomy.joints = [joint(&"LeftLowerLeg", 150.0, Vector3.BACK), joint(&"RightLowerLeg", 150.0, Vector3.BACK), joint(&"LeftLowerArm", 145.0, Vector3.FORWARD), joint(&"RightLowerArm", 145.0, Vector3.FORWARD)]
	p.anatomy = anatomy
	# Sockets are DECLARED; their offsets are placeholders until Task 07 takes the real values from the rig scene and the weapon handling profile.
	p.sockets = [socket(&"weapon_dominant_hand", &"RightHand"), socket(&"weapon_support_hand", &"LeftHand"), socket(&"sling_chest", &"UpperChest"), socket(&"carry_shoulder", &"RightShoulder")]
	return p

static func mira_skeleton() -> Skeleton3D:
	var model: Node = load(MIRA_MODEL).instantiate()
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	skeleton.get_parent().remove_child(skeleton)   # a detached skeleton at native scale: the profile's character_scale supplies the 1.6
	model.free()
	return skeleton

# ---------------------------------------------------------------- B: synthetic alternate

static func _basis_along(direction: Vector3, up_hint: Vector3) -> Basis:
	var x := direction.normalized()
	var hint := up_hint if absf(x.dot(up_hint)) < 0.95 else Vector3.RIGHT
	var z := x.cross(hint).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)

## The synthetic skeleton: design frame is X = character left, Y up, Z forward; then rotated 180 degrees about Y so the body faces -Z.
static func alternate_skeleton(drop_bone := "", rename: Dictionary = {}) -> Skeleton3D:
	var flip := Basis(Vector3.UP, PI)
	var d := {}   # name -> [parent, global position in the design frame, direction to child (design frame)]
	var arm_dir := Vector3(cos(deg_to_rad(40.0)), -sin(deg_to_rad(40.0)), 0.0)   # A-pose: 40 degrees below horizontal
	d["root"] = ["", Vector3(0, 0, 0), Vector3.UP]
	d["pelvis"] = ["root", Vector3(0, 0.82, 0), Vector3.UP]
	d["spine_01"] = ["pelvis", Vector3(0, 0.92, 0), Vector3.UP]
	d["spine_02"] = ["spine_01", Vector3(0, 1.05, 0), Vector3.UP]
	d["neck_01"] = ["spine_02", Vector3(0, 1.22, 0.01), Vector3.UP]
	d["head"] = ["neck_01", Vector3(0, 1.30, 0.01), Vector3.UP]
	for side in [["l", 1.0], ["r", -1.0]]:
		var x: float = side[1]
		var tag: String = side[0]
		d["clavicle_" + tag] = ["spine_02", Vector3(0.04 * x, 1.18, 0.0), Vector3.RIGHT * x]
		var shoulder := Vector3(0.17 * x, 1.17, 0.0)
		var dir := Vector3(arm_dir.x * x, arm_dir.y, 0.0)
		d["upperarm_" + tag] = ["clavicle_" + tag, shoulder, dir]
		d["lowerarm_" + tag] = ["upperarm_" + tag, shoulder + dir * 0.27, dir]
		d["hand_" + tag] = ["lowerarm_" + tag, shoulder + dir * 0.51, dir]
		d["thigh_" + tag] = ["pelvis", Vector3(0.075 * x, 0.80, 0.0), Vector3.DOWN]
		d["calf_" + tag] = ["thigh_" + tag, Vector3(0.075 * x, 0.44, 0.0), Vector3.DOWN]
		d["foot_" + tag] = ["calf_" + tag, Vector3(0.075 * x, 0.08, 0.0), Vector3.BACK]
	var order := ["root", "pelvis", "spine_01", "spine_02", "neck_01", "head", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r", "thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]
	var skeleton := Skeleton3D.new()
	var index := {}
	var global := {}
	for bone_name: String in order:
		if bone_name == drop_bone:
			continue
		var entry: Array = d[bone_name]
		var position: Vector3 = flip * entry[1]
		var basis := _basis_along(flip * (entry[2] as Vector3), Vector3.UP)   # +X along the bone: a different local convention from the production rig
		var final_name: String = rename.get(bone_name, bone_name)
		var bone_id := skeleton.get_bone_count()
		skeleton.add_bone(final_name)
		index[bone_name] = bone_id
		global[bone_name] = Transform3D(basis, position)
		var parent_name: String = entry[0]
		if parent_name != "" and index.has(parent_name):
			skeleton.set_bone_parent(bone_id, index[parent_name])
			skeleton.set_bone_rest(bone_id, (global[parent_name] as Transform3D).affine_inverse() * (global[bone_name] as Transform3D))
		else:
			skeleton.set_bone_rest(bone_id, global[bone_name])
	skeleton.reset_bone_poses()
	return skeleton

static func alternate_profile() -> RigProfile:
	var p := RigProfile.new()
	p.display_name = "Alternate (synthetic, Unreal-style names)"
	p.skeleton_map = new_bone_map({
		&"Root": &"root", &"Hips": &"pelvis", &"Spine": &"spine_01", &"Chest": &"spine_02", &"Neck": &"neck_01", &"Head": &"head",
		&"LeftShoulder": &"clavicle_l", &"LeftUpperArm": &"upperarm_l", &"LeftLowerArm": &"lowerarm_l", &"LeftHand": &"hand_l",
		&"RightShoulder": &"clavicle_r", &"RightUpperArm": &"upperarm_r", &"RightLowerArm": &"lowerarm_r", &"RightHand": &"hand_r",
		&"LeftUpperLeg": &"thigh_l", &"LeftLowerLeg": &"calf_l", &"LeftFoot": &"foot_l",
		&"RightUpperLeg": &"thigh_r", &"RightLowerLeg": &"calf_r", &"RightFoot": &"foot_r",
	})
	var anatomy := Anatomy.new()
	anatomy.character_scale = 1.0
	anatomy.declared_height = 1.43   # no head-top bone on this skeleton: authored by hand
	anatomy.joints = [joint(&"LeftLowerLeg", 140.0, Vector3.BACK), joint(&"RightLowerLeg", 140.0, Vector3.BACK), joint(&"LeftLowerArm", 140.0, Vector3.FORWARD), joint(&"RightLowerArm", 140.0, Vector3.FORWARD)]
	p.anatomy = anatomy
	p.sockets = [socket(&"weapon_dominant_hand", &"RightHand"), socket(&"weapon_support_hand", &"LeftHand"), socket(&"sling_chest", &"Chest")]
	return p
