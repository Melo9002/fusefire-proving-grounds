extends SceneTree

const DUMMY_PATH := "res://art/characters/android_test_dummy/models/android_test_dummy_rigprep.glb"
const AUG_PATH := "res://art/weapons/aug/models/aug_runtime.glb"
const HEIGHT_TOLERANCE := 0.01
const LENGTH_TOLERANCE := 0.01


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures: Array[String] = []
	_check_asset(DUMMY_PATH, 1.60, HEIGHT_TOLERANCE, "dummy height", failures)
	_check_asset(AUG_PATH, 0.79, LENGTH_TOLERANCE, "AUG length", failures)
	if failures.is_empty():
		print("[CharacterAssets] PASS — dummy 1.60 m; AUG 0.79 m; project imports load correctly")
		quit(0)
		return
	for failure in failures:
		push_error("[CharacterAssets] %s" % failure)
	quit(1)


func _check_asset(path: String, expected_largest_dimension: float, tolerance: float, label: String, failures: Array[String]) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		failures.append("Could not load %s" % path)
		return
	var instance := packed.instantiate() as Node3D
	if instance == null:
		failures.append("Could not instantiate %s" % path)
		return
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
		instance.queue_free()
		return
	var largest := maxf(combined.size.x, maxf(combined.size.y, combined.size.z))
	if absf(largest - expected_largest_dimension) > tolerance:
		failures.append("%s expected %.2f m, got %.4f m (%s)" % [label, expected_largest_dimension, largest, path])
	instance.queue_free()