extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var workbench := load("res://art/characters/vroid_proof/animations/animation_workbench.tscn").instantiate() as Node3D
	root.add_child(workbench)
	var editor_player := workbench.get_node("AnimationPlayer") as AnimationPlayer
	var library := editor_player.get_animation_library(&"")
	var target := editor_player.get_node(editor_player.root_node) as Skeleton3D
	check(target != null, "Workbench animation root resolves to the skeleton")
	var adapter := load("res://art/characters/vroid_proof/runtime/unit_visual_adapter.tscn").instantiate() as UnitVisualAdapter
	root.add_child(adapter)
	await process_frame
	await process_frame
	for clip_name in library.get_animation_list():
		var clip := library.get_animation(clip_name)
		check(adapter.animation_controller._valid_bone_clip(clip), "Bone tracks resolve: %s" % clip_name)
		if clip_name != &"RESET":
			check(adapter.animation_controller.animation_player.get_animation(clip_name) == clip, "Runtime uses the editable resource: %s" % clip_name)
	var hip := target.find_bone("J_Bip_C_Hips")
	editor_player.play(&"cover_low")
	editor_player.seek(0.1, true)
	check(target.get_bone_pose_position(hip).y < target.get_bone_rest(hip).origin.y, "Workbench scrubbing visibly applies crouch")
	workbench.queue_free()
	adapter.queue_free()
	await process_frame
	print("Animation handoff: %d failure(s)" % failures)
	quit(1 if failures else 0)
