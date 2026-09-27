extends SceneTree

const DUMMY_PATH := "res://art/characters/android_test_dummy/models/android_test_dummy_rigged.glb"
const AUG_PATH := "res://art/weapons/aug/models/aug_runtime_socketed.glb"
const HEIGHT_TOLERANCE := 0.01
const LENGTH_TOLERANCE := 0.01
const REQUIRED_BONES: Array[String] = [
	"Root", "Pelvis", "Spine", "Chest", "Neck", "Head",
	"UpperArm.L", "Forearm.L", "Hand.L", "UpperArm.R", "Forearm.R", "Hand.R",
	"Thigh.L", "Shin.L", "Foot.L", "Thigh.R", "Shin.R", "Foot.R",
	"hand_ik.L", "hand_ik.R", "weapon_socket_r", "carry_socket",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures: Array[String] = []
	var dummy := _check_asset(DUMMY_PATH, 1.60, HEIGHT_TOLERANCE, "dummy height", failures)
	var aug := _check_asset(AUG_PATH, 0.79, LENGTH_TOLERANCE, "AUG length", failures)
	if dummy != null:
		_check_rig(dummy, failures)
	if aug != null:
		_check_marker(aug, "MuzzleSocket", failures)
		_check_marker(aug, "WeaponOrigin", failures)
	if failures.is_empty():
		print("[CharacterAssets] PASS — rigged dummy 1.60 m; 26-bone skeleton and sockets present; AUG 0.79 m with muzzle marker")
		quit(0)
		return
	for failure in failures:
		push_error("[CharacterAssets] %s" % failure)
	quit(1)


func _check_asset(path: String, expected_largest_dimension: float, tolerance: float, label: String, failures: Array[String]) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		failures.append("Could not load %s" % path)
		return null
	var instance := packed.instantiate() as Node3D
	if instance == null:
		failures.append("Could not instantiate %s" % path)
		return null
	root.add_child(instance)
	var combined := AABB()
	var found_mesh := false
	for descendant in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := descendant as MeshInstance3D
		var world_bounds: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
		combined = world_bounds if not found_mesh else combined.merge(world_bounds)
		found_mesh = true
	if not found_mesh:
		failures.append("No MeshInstance3D found in %s" % path)
		return instance
	var largest := maxf(combined.size.x, maxf(combined.size.y, combined.size.z))
	if absf(largest - expected_largest_dimension) > tolerance:
		failures.append("%s expected %.2f m, got %.4f m (%s)" % [label, expected_largest_dimension, largest, path])
	return instance


func _check_rig(instance: Node3D, failures: Array[String]) -> void:
	var skeleton := instance.find_child("*", true, false) as Skeleton3D
	for candidate in instance.find_children("*", "Skeleton3D", true, false):
		skeleton = candidate as Skeleton3D
		break
	if skeleton == null:
		failures.append("Rigged dummy has no Skeleton3D")
		return
	for bone_name in REQUIRED_BONES:
		if skeleton.find_bone(bone_name) < 0:
			failures.append("Rigged dummy is missing bone %s" % bone_name)
	var skinned_mesh_found := false
	for candidate in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if not mesh_instance.skeleton.is_empty():
			skinned_mesh_found = true
			break
	if not skinned_mesh_found:
		failures.append("Rigged dummy mesh is not connected to its Skeleton3D")


func _check_marker(instance: Node3D, marker_name: String, failures: Array[String]) -> void:
	if instance.find_child(marker_name, true, false) == null:
		failures.append("AUG is missing marker %s" % marker_name)