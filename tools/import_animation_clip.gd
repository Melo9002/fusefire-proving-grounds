extends SceneTree
## Convert one animation from a same-rig imported scene into a workbench clip.
## Arguments after --: res://scene.glb exact_animation_name res://new_clip.tres
func _initialize() -> void:
	call_deferred("run")

func fail(message: String) -> void:
	push_error(message)
	quit(1)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		fail("Expected: imported scene path, exact animation name, new .tres output path")
		return
	if not (args[2].begins_with("res://") or args[2].begins_with("user://")) or not args[2].ends_with(".tres") or FileAccess.file_exists(args[2]):
		fail("Output must be a new res:// .tres file; existing edits are never overwritten.")
		return
	var source := load(args[0]) as PackedScene
	if not source:
		fail("Input must be imported as a Scene, not an AnimationLibrary.")
		return
	var model := source.instantiate()
	root.add_child(model)
	var player: AnimationPlayer
	for node in model.find_children("*", "AnimationPlayer", true, false):
		if node.has_animation(args[1]):
			player = node
			break
	if not player:
		fail("Animation not found. Inspect the imported scene's AnimationPlayer for its exact name.")
		return
	var clip := player.get_animation(args[1]).duplicate(true) as Animation
	var runtime := load("res://art/characters/vroid_proof/models/vroid_test_runtime.glb").instantiate() as Node3D
	var reference := runtime.find_child("Skeleton3D", true, false) as Skeleton3D
	var animation_root := player.get_node(player.root_node)
	for track in range(clip.get_track_count() - 1, -1, -1):
		var path := clip.track_get_path(track)
		var bone_skeleton := animation_root.get_node_or_null(NodePath(path.get_concatenated_names())) as Skeleton3D
		if not bone_skeleton or path.get_subname_count() != 1:
			fail("Clip contains non-skeletal tracks. Export only armature bone animation.")
			runtime.free()
			return
		var bone := String(path.get_subname(0))
		var source_index := bone_skeleton.find_bone(bone)
		var target_index := reference.find_bone(bone)
		if source_index < 0 or target_index < 0 or not bone_skeleton.get_bone_rest(source_index).is_equal_approx(reference.get_bone_rest(target_index)):
			fail("Bone/rest mismatch: %s. Use the unchanged runtime armature; this converter does not retarget." % bone)
			runtime.free()
			return
		if clip.track_get_type(track) == Animation.TYPE_SCALE_3D:
			for key in clip.track_get_key_count(track):
				var value: Vector3 = clip.track_get_key_value(track, key)
				if not value.is_equal_approx(Vector3.ONE):
					fail("Animated bone scale is unsupported: %s" % bone)
					runtime.free()
					return
			clip.remove_track(track)
			continue
		if clip.track_get_type(track) not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]:
			fail("Only bone position and rotation tracks are supported.")
			runtime.free()
			return
		clip.track_set_path(track, NodePath(".:%s" % bone))
	runtime.free()
	if clip.get_track_count() == 0:
		fail("No usable bone tracks were exported.")
		return
	var error := ResourceSaver.save(clip, args[2])
	print("Animation conversion: %s" % error_string(error))
	quit(0 if error == OK else 1)
