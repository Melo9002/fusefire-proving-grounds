extends Node

signal state_changed(state_name: StringName)

const IDLE := &"rifle_idle"
const MOVE := &"move"
const AIM := &"aim"
const SHOOT := &"shoot"
const HIT := &"hit"
const DEFEAT := &"defeat"
const STATES: Array[StringName] = [IDLE, MOVE, AIM, SHOOT, HIT, DEFEAT]

const HIPS := &"J_Bip_C_Hips"
const SPINE := &"J_Bip_C_Spine"
const CHEST := &"J_Bip_C_Chest"
const UPPER_CHEST := &"J_Bip_C_UpperChest"
const NECK := &"J_Bip_C_Neck"
const HEAD := &"J_Bip_C_Head"
const LEFT_UPPER_LEG := &"J_Bip_L_UpperLeg"
const LEFT_LOWER_LEG := &"J_Bip_L_LowerLeg"
const LEFT_FOOT := &"J_Bip_L_Foot"
const RIGHT_UPPER_LEG := &"J_Bip_R_UpperLeg"
const RIGHT_LOWER_LEG := &"J_Bip_R_LowerLeg"
const RIGHT_FOOT := &"J_Bip_R_Foot"

var skeleton: Skeleton3D
var visual_root: Node3D
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var current_state := IDLE
var sequence_running := false
var _sequence_generation := 0
var _visual_tween: Tween


func setup(target_skeleton: Skeleton3D, target_visual_root: Node3D) -> void:
	skeleton = target_skeleton
	visual_root = target_visual_root
	_build_animation_player()
	_build_animation_tree()
	play(IDLE)


func play(state_name: StringName) -> void:
	if state_name not in STATES or playback == null:
		return
	_sequence_generation += 1
	sequence_running = false
	var repeat := current_state == state_name
	current_state = state_name
	if repeat:
		playback.start(state_name)
	else:
		playback.travel(state_name)
	_apply_visual_root_state(state_name)
	state_changed.emit(current_state)


func play_sequence() -> void:
	_sequence_generation += 1
	var generation := _sequence_generation
	sequence_running = true
	for step: Dictionary in [
		{"state": IDLE, "seconds": 1.5},
		{"state": MOVE, "seconds": 2.0},
		{"state": AIM, "seconds": 0.75},
		{"state": SHOOT, "seconds": 0.45},
		{"state": AIM, "seconds": 0.55},
		{"state": HIT, "seconds": 0.65},
		{"state": IDLE, "seconds": 0.8},
		{"state": DEFEAT, "seconds": 1.4},
	]:
		if generation != _sequence_generation:
			return
		current_state = step.state
		playback.travel(current_state)
		_apply_visual_root_state(current_state)
		state_changed.emit(current_state)
		await get_tree().create_timer(float(step.seconds)).timeout
	if generation == _sequence_generation:
		sequence_running = false


func _build_animation_player() -> void:
	animation_player = AnimationPlayer.new()
	animation_player.name = "VerticalSliceAnimationPlayer"
	skeleton.add_child(animation_player)
	animation_player.root_node = NodePath("..")

	var library := AnimationLibrary.new()
	library.add_animation(IDLE, _make_idle())
	library.add_animation(MOVE, _make_move())
	library.add_animation(AIM, _make_aim())
	library.add_animation(SHOOT, _make_shoot())
	library.add_animation(HIT, _make_hit())
	library.add_animation(DEFEAT, _make_defeat())
	animation_player.add_animation_library(&"", library)


func _build_animation_tree() -> void:
	animation_tree = AnimationTree.new()
	animation_tree.name = "VerticalSliceAnimationTree"
	skeleton.add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(animation_player)

	var state_machine := AnimationNodeStateMachine.new()
	for state_name: StringName in STATES:
		var animation_node := AnimationNodeAnimation.new()
		animation_node.animation = state_name
		state_machine.add_node(state_name, animation_node)

	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = 0.14
	state_machine.add_transition(&"Start", IDLE, transition)
	for from_state: StringName in STATES:
		for to_state: StringName in STATES:
			if from_state == to_state:
				continue
			var crossfade := AnimationNodeStateMachineTransition.new()
			crossfade.xfade_time = 0.12 if to_state != DEFEAT else 0.05
			state_machine.add_transition(from_state, to_state, crossfade)

	animation_tree.tree_root = state_machine
	animation_tree.active = true
	playback = animation_tree.get(&"parameters/playback") as AnimationNodeStateMachinePlayback


func _make_idle() -> Animation:
	var animation := _new_animation(2.0, true)
	_add_rotation(animation, CHEST, [0.0, 1.0, 2.0], [_rotation(0.0, 0.0, -1.0), _rotation(-2.4, 0.0, 1.5), _rotation(0.0, 0.0, -1.0)])
	_add_rotation(animation, HEAD, [0.0, 1.0, 2.0], [_rotation(0.0, -1.0, 0.0), _rotation(0.8, 1.0, 0.0), _rotation(0.0, -1.0, 0.0)])
	_add_grip(animation)
	return animation


func _make_move() -> Animation:
	var animation := _new_animation(1.0, true)
	_add_position(animation, HIPS, [0.0, 0.25, 0.5, 0.75, 1.0], [Vector3.ZERO, Vector3(0, 0.018, 0), Vector3.ZERO, Vector3(0, 0.018, 0), Vector3.ZERO])
	# Swing the bent leg forward along the rig's +Z facing direction.
	_add_rotation(animation, LEFT_UPPER_LEG, [0.0, 0.5, 1.0], [_rotation(-22, 0, 0), _rotation(22, 0, 0), _rotation(-22, 0, 0)])
	_add_rotation(animation, RIGHT_UPPER_LEG, [0.0, 0.5, 1.0], [_rotation(22, 0, 0), _rotation(-22, 0, 0), _rotation(22, 0, 0)])
	_add_rotation(animation, LEFT_LOWER_LEG, [0.0, 0.25, 0.5, 1.0], [_rotation(-5, 0, 0), _rotation(-48, 0, 0), _rotation(-5, 0, 0), _rotation(-5, 0, 0)])
	_add_rotation(animation, RIGHT_LOWER_LEG, [0.0, 0.5, 0.75, 1.0], [_rotation(-5, 0, 0), _rotation(-5, 0, 0), _rotation(-48, 0, 0), _rotation(-5, 0, 0)])
	_add_rotation(animation, LEFT_FOOT, [0.0, 0.5, 1.0], [_rotation(-8, 0, 0), _rotation(10, 0, 0), _rotation(-8, 0, 0)])
	_add_rotation(animation, RIGHT_FOOT, [0.0, 0.5, 1.0], [_rotation(10, 0, 0), _rotation(-8, 0, 0), _rotation(10, 0, 0)])
	_add_rotation(animation, CHEST, [0.0, 0.5, 1.0], [_rotation(-3, -2, 1), _rotation(-3, 2, -1), _rotation(-3, -2, 1)])
	_add_grip(animation)
	return animation


func _make_aim() -> Animation:
	var animation := _new_animation(0.5, false)
	_add_rotation(animation, SPINE, [0.0, 0.5], [Quaternion.IDENTITY, _rotation(-3, 0, 0)])
	_add_rotation(animation, CHEST, [0.0, 0.5], [Quaternion.IDENTITY, _rotation(-5, 0, 0)])
	_add_rotation(animation, HEAD, [0.0, 0.5], [Quaternion.IDENTITY, _rotation(2, 0, -5)])
	_add_grip(animation)
	return animation


func _make_shoot() -> Animation:
	var animation := _new_animation(0.32, false)
	_add_rotation(animation, CHEST, [0.0, 0.07, 0.18, 0.32], [_rotation(-5, 0, 0), _rotation(-15, 8, -4), _rotation(-4, 8, 1), _rotation(-5, 0, 0)])
	_add_rotation(animation, HEAD, [0.0, 0.07, 0.32], [_rotation(2, 0, -5), _rotation(-2, -5, 0), _rotation(2, 0, -5)])
	_add_grip(animation)
	return animation


func _make_hit() -> Animation:
	var animation := _new_animation(0.55, false)
	_add_rotation(animation, HIPS, [0.0, 0.12, 0.32, 0.55], [Quaternion.IDENTITY, _rotation(0, -7, -4), _rotation(0, 4, 2), Quaternion.IDENTITY])
	_add_rotation(animation, CHEST, [0.0, 0.12, 0.32, 0.55], [Quaternion.IDENTITY, _rotation(20, -24, -18), _rotation(-7, 12, 8), Quaternion.IDENTITY])
	_add_rotation(animation, HEAD, [0.0, 0.12, 0.55], [Quaternion.IDENTITY, _rotation(-8, 10, 8), Quaternion.IDENTITY])
	_add_grip(animation)
	return animation


func _make_defeat() -> Animation:
	var animation := _new_animation(1.2, false)
	_add_rotation(animation, HIPS, [0.0, 0.3, 1.2], [Quaternion.IDENTITY, _rotation(4, 0, -5), _rotation(7, 0, -10)])
	_add_rotation(animation, CHEST, [0.0, 0.3, 0.72, 1.2], [Quaternion.IDENTITY, _rotation(12, 5, -5), _rotation(22, -6, -12), _rotation(18, -8, -18)])
	_add_rotation(animation, HEAD, [0.0, 0.3, 1.2], [Quaternion.IDENTITY, _rotation(-10, 8, 4), _rotation(15, -10, 10)])
	_add_rotation(animation, LEFT_UPPER_LEG, [0.0, 1.2], [Quaternion.IDENTITY, _rotation(-8, 4, 0)])
	_add_rotation(animation, RIGHT_UPPER_LEG, [0.0, 1.2], [Quaternion.IDENTITY, _rotation(10, -4, 0)])
	_add_grip(animation)
	return animation


func _apply_visual_root_state(state_name: StringName) -> void:
	if not is_instance_valid(visual_root):
		return
	if _visual_tween != null and _visual_tween.is_valid():
		_visual_tween.kill()
	_visual_tween = create_tween()
	if state_name == DEFEAT:
		_visual_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_visual_tween.parallel().tween_property(visual_root, "rotation:z", deg_to_rad(-82.0), 1.05)
		_visual_tween.parallel().tween_property(visual_root, "position", Vector3(0.02, 0.035, 0.0), 1.05)
	else:
		_visual_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_visual_tween.parallel().tween_property(visual_root, "rotation", Vector3.ZERO, 0.14)
		_visual_tween.parallel().tween_property(visual_root, "position", Vector3.ZERO, 0.14)


func _add_grip(animation: Animation) -> void:
	for side in ["L", "R"]:
		var direction := -1.0 if side == "L" else 1.0
		for finger in ["Index", "Middle", "Ring", "Little"]:
			for joint in [1, 2, 3]:
				var bone := StringName("J_Bip_%s_%s%d" % [side, finger, joint])
				_add_rotation(animation, bone, [0.0], [_rotation(0, 0, 42.0 * direction if joint == 1 else 58.0 * direction)])
		for joint in [1, 2, 3]:
			var thumb := StringName("J_Bip_%s_Thumb%d" % [side, joint])
			_add_rotation(animation, thumb, [0.0], [_rotation(0, 18.0 * direction, 22.0 * direction)])


func _new_animation(length: float, looping: bool) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	return animation


func _add_rotation(animation: Animation, bone: StringName, times: Array, values: Array) -> void:
	var bone_index := skeleton.find_bone(bone)
	if bone_index < 0:
		return
	var rest_rotation := skeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion()
	var track := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, NodePath(".:%s" % bone))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	for index in times.size():
		animation.rotation_track_insert_key(track, float(times[index]), rest_rotation * values[index])


func _add_position(animation: Animation, bone: StringName, times: Array, values: Array) -> void:
	var bone_index := skeleton.find_bone(bone)
	if bone_index < 0:
		return
	var rest_position := skeleton.get_bone_rest(bone_index).origin
	var track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, NodePath(".:%s" % bone))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	for index in times.size():
		animation.position_track_insert_key(track, float(times[index]), rest_position + values[index])


func _rotation(x_degrees: float, y_degrees: float, z_degrees: float) -> Quaternion:
	return Quaternion.from_euler(Vector3(deg_to_rad(x_degrees), deg_to_rad(y_degrees), deg_to_rad(z_degrees)))

