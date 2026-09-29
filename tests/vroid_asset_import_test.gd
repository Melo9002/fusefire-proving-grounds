extends SceneTree

const MODEL_PATH := "res://art/characters/vroid_proof/models/vroid_test_runtime.glb"
const HEIGHT_TARGET := 1.60
const HEIGHT_TOLERANCE := 0.01
const REQUIRED_BONES: Array[String] = [
	"J_Bip_C_Hips", "J_Bip_C_Spine", "J_Bip_C_Chest", "J_Bip_C_Head",
	"J_Bip_L_UpperArm", "J_Bip_L_LowerArm", "J_Bip_L_Hand",
	"J_Bip_R_UpperArm", "J_Bip_R_LowerArm", "J_Bip_R_Hand",
	"J_Bip_L_UpperLeg", "J_Bip_L_LowerLeg", "J_Bip_L_Foot",
	"J_Bip_R_UpperLeg", "J_Bip_R_LowerLeg", "J_Bip_R_Foot",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		failures.append("Could not load %s" % MODEL_PATH)
		_finish(failures)
		return
	var instance := packed.instantiate() as Node3D
	root.add_child(instance)
	await process_frame

	var skeleton: Skeleton3D
	for candidate in instance.find_children("*", "Skeleton3D", true, false):
		skeleton = candidate as Skeleton3D
		break
	if skeleton == null:
		failures.append("Runtime VRoid has no Skeleton3D")
	else:
		for bone_name in REQUIRED_BONES:
			if skeleton.find_bone(bone_name) < 0:
				failures.append("Runtime VRoid is missing bone %s" % bone_name)

	var bounds := AABB()
	var has_bounds := false
	var blend_shape_count := 0
	var skinned_meshes := 0
	for candidate in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var local_bounds := mesh_instance.global_transform * mesh_instance.get_aabb()
		bounds = bounds.merge(local_bounds) if has_bounds else local_bounds
		has_bounds = true
		blend_shape_count += mesh_instance.mesh.get_blend_shape_count()
		if not mesh_instance.skeleton.is_empty():
			skinned_meshes += 1

	if not has_bounds:
		failures.append("Runtime VRoid has no renderable mesh bounds")
	elif absf(bounds.size.y - HEIGHT_TARGET) > HEIGHT_TOLERANCE:
		failures.append("Runtime VRoid height %.4f m differs from %.2f m" % [bounds.size.y, HEIGHT_TARGET])
	if skinned_meshes != 3:
		failures.append("Expected 3 skinned meshes, found %d" % skinned_meshes)
	if blend_shape_count < 57:
		failures.append("Expected at least 57 facial morph targets, found %d" % blend_shape_count)

	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("[VRoidAssets] PASS — 1.60 m; humanoid skeleton; 3 skinned meshes; 57 facial morphs")
		quit(0)
		return
	for failure in failures:
		push_error("[VRoidAssets] %s" % failure)
	quit(1)
