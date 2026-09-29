extends SceneTree

const DEMO := preload("res://art/characters/vroid_proof/demo/vroid_weapon_ik_demo.tscn")
const REQUIRED_ANIMATIONS: Array[StringName] = [
	&"rifle_idle", &"move", &"aim", &"shoot", &"hit", &"defeat",
]

var failed := false


func _initialize() -> void:
	var demo := DEMO.instantiate()
	root.add_child(demo)
	for frame in 4:
		await process_frame

	var skeleton := demo.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := demo.find_child("VerticalSliceAnimationPlayer", true, false) as AnimationPlayer
	var tree := demo.find_child("VerticalSliceAnimationTree", true, false) as AnimationTree
	var controller := demo.find_child("VerticalSliceController", true, false)
	var muzzle_flash := demo.find_child("MuzzleFlash", true, false) as MeshInstance3D
	var visual_root := demo.get_node("Character") as Node3D

	_assert(skeleton != null, "skeleton exists")
	_assert(player != null, "AnimationPlayer exists")
	_assert(tree != null and tree.active, "AnimationTree is active")
	_assert(controller != null, "vertical-slice controller exists")
	_assert(muzzle_flash != null, "shoot feedback has a muzzle flash")
	if failed:
		await _finish(demo)
		return

	for animation_name: StringName in REQUIRED_ANIMATIONS:
		_assert(player.has_animation(animation_name), "animation '%s' exists" % animation_name)
		var animation := player.get_animation(animation_name)
		_assert(animation.track_get_key_count(0) > 0, "animation '%s' contains keys" % animation_name)

	_assert(player.get_animation(&"rifle_idle").loop_mode == Animation.LOOP_LINEAR, "idle loops")
	_assert(player.get_animation(&"move").loop_mode == Animation.LOOP_LINEAR, "move loops")
	_assert(player.get_animation(&"shoot").loop_mode == Animation.LOOP_NONE, "shoot is one-shot")
	_assert(player.get_animation(&"defeat").loop_mode == Animation.LOOP_NONE, "defeat is one-shot")

	var left_leg := skeleton.find_bone(&"J_Bip_L_UpperLeg")
	var left_leg_rest_rotation := skeleton.get_bone_pose_rotation(left_leg)

	controller.play(&"move")
	await create_timer(0.3).timeout
	_assert(controller.current_state == &"move", "AnimationTree enters move")
	_assert(not skeleton.get_bone_pose_rotation(left_leg).is_equal_approx(left_leg_rest_rotation), "move animates a leg")

	controller.play(&"shoot")
	await process_frame
	_assert(muzzle_flash.visible, "shoot shows muzzle flash")
	await create_timer(0.1).timeout
	_assert(not muzzle_flash.visible, "muzzle flash is brief")

	controller.play(&"defeat")
	await create_timer(0.85).timeout
	_assert(absf(visual_root.rotation.z) > 0.7, "defeat tips the visual body")

	if not failed:
		print("[VRoidVerticalSlice] PASS — idle, move, aim, shoot, hit, defeat; AnimationTree; recoil and muzzle flash")
	await _finish(demo)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failed = true
	push_error("[VRoidVerticalSlice] FAIL — %s" % message)


func _finish(demo: Node) -> void:
	demo.queue_free()
	await process_frame
	quit(1 if failed else 0)
