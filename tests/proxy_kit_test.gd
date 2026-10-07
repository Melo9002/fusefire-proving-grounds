extends SceneTree

const CHARACTER_PATH := "res://art/research/proxies/models/fusefire_animation_proxy.glb"
const RIFLE_PATH := "res://art/research/proxies/models/fusefire_rifle_proxy.glb"

const REQUIRED_BONES := [
	&"mixamorig_Hips",
	&"mixamorig_Spine",
	&"mixamorig_Spine1",
	&"mixamorig_Spine2",
	&"mixamorig_Neck",
	&"mixamorig_Head",
	&"mixamorig_LeftArm",
	&"mixamorig_LeftForeArm",
	&"mixamorig_LeftHand",
	&"mixamorig_RightArm",
	&"mixamorig_RightForeArm",
	&"mixamorig_RightHand",
]

const REQUIRED_CONTACTS := [
	&"WeaponOrigin",
	&"GripReference",
	&"SupportHandTarget",
	&"MuzzleSocket",
	&"SightReference",
	&"ButtstockContact",
]


func _initialize() -> void:
	var character_scene := load(CHARACTER_PATH) as PackedScene
	assert(character_scene != null, "FuseFire animation proxy must import")
	var character := character_scene.instantiate()
	var skeleton := character.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(skeleton != null, "FuseFire animation proxy must expose Skeleton3D")
	for bone_name in REQUIRED_BONES:
		assert(skeleton.find_bone(bone_name) >= 0, "Missing proxy bone: %s" % bone_name)
	character.free()

	var rifle_scene := load(RIFLE_PATH) as PackedScene
	assert(rifle_scene != null, "FuseFire rifle proxy must import")
	var rifle := rifle_scene.instantiate()
	for contact_name in REQUIRED_CONTACTS:
		assert(rifle.find_child(contact_name, true, false) != null, "Missing rifle contact: %s" % contact_name)
	rifle.free()
	print("[PASS] FuseFire original proxy kit contract")
	quit()
