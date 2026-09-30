extends Node
## Edit saved poses in ../animations/animation_workbench.tscn.
## The _make_* builders below are fallbacks; saved library clips take precedence.
## Workflow and procedural timing: docs/animation-editing-guide.md.

signal state_changed(state_name: StringName)

const IDLE := &"rifle_idle"
const MOVE := &"move"
const AIM := &"aim"
const SHOOT := &"shoot"
const HIT := &"hit"
const DEFEAT := &"defeat"
const STATES: Array[StringName] = [IDLE, MOVE, AIM, SHOOT, HIT, DEFEAT,
	&"cover_low", &"cover_high", &"shoot_left", &"shoot_right", &"vault", &"climb", &"descend", &"land",
	&"pickup", &"carry_idle", &"carry_move", &"boarding"]

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
var clip_library: AnimationLibrary


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
	library.add_animation(&"move_back", _make_directional_move(Vector2(0, -1)))
	library.add_animation(&"move_left", _make_directional_move(Vector2(-1, 0)))
	library.add_animation(&"move_right", _make_directional_move(Vector2(1, 0)))
	library.add_animation(AIM, _make_aim())
	library.add_animation(SHOOT, _make_shoot())
	library.add_animation(HIT, _make_hit())
	library.add_animation(DEFEAT, _make_defeat())
	for pose in [&"pickup", &"carry_idle", &"carry_move", &"boarding"]:
		library.add_animation(pose, _make_rescue_pose(pose))
	for pose in [&"cover_low", &"cover_high", &"vault", &"climb", &"descend", &"land"]:
		library.add_animation(pose, _make_tactical_pose(pose))
	for side in [-1, 1]:
		var shot := _make_shoot()
		_add_position(shot, HIPS, [0.0, 0.07, 0.32], [Vector3(side * 0.10, -0.03, 0), Vector3(side * 0.14, -0.03, 0), Vector3(side * 0.10, -0.03, 0)])
		library.add_animation(&"shoot_left" if side < 0 else &"shoot_right", shot)
	# Saved clips are authoritative; builders remain a fallback for missing clips.
	if clip_library:
		for clip_name in clip_library.get_animation_list():
			if clip_name == &"RESET" or not library.has_animation(clip_name): continue
			var edited := clip_library.get_animation(clip_name)
			if not _valid_bone_clip(edited):
				push_warning("Ignoring invalid skeletal clip: %s" % clip_name)
				continue
			library.remove_animation(clip_name)
			library.add_animation(clip_name, edited)
	# Explicit rest tracks prevent a cover crouch from leaking into idle/aim.
	var reset := _new_animation(0.0, false)
	var seen := {}
	for clip_name in library.get_animation_list():
		var clip := library.get_animation(clip_name)
		for track in clip.get_track_count():
			var path := clip.track_get_path(track)
			var kind := clip.track_get_type(track)
			var key := "%s:%s" % [path, kind]
			if seen.has(key):
				continue
			seen[key] = true
			var bone := StringName(path.get_subname(0))
			if kind == Animation.TYPE_ROTATION_3D:
				_add_rotation(reset, bone, [0.0], [Quaternion.IDENTITY])
			elif kind == Animation.TYPE_POSITION_3D:
				_add_position(reset, bone, [0.0], [Vector3.ZERO])
	library.add_animation(&"RESET", reset)
	animation_player.add_animation_library(&"", library)

func _valid_bone_clip(clip: Animation) -> bool:
	for track in clip.get_track_count():
		var path := clip.track_get_path(track)
		if clip.track_get_type(track) not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]: return false
		if path.get_concatenated_names() != "." or path.get_subname_count() != 1: return false
		if skeleton.find_bone(path.get_subname(0)) < 0: return false
	return clip.get_track_count() > 0


func _build_animation_tree() -> void:
	animation_tree = AnimationTree.new()
	animation_tree.name = "VerticalSliceAnimationTree"
	skeleton.add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(animation_player)

	var state_machine := AnimationNodeStateMachine.new()
	for state_name: StringName in STATES:
		if state_name == &"carry_move":
			var carry_tree := AnimationNodeBlendTree.new()
			var carry_clip := AnimationNodeAnimation.new()
			carry_clip.animation = &"carry_move"
			carry_tree.add_node(&"Clip", carry_clip)
			carry_tree.add_node(&"Pace", AnimationNodeTimeScale.new())
			carry_tree.connect_node(&"Pace", 0, &"Clip")
			carry_tree.connect_node(&"output", 0, &"Pace")
			state_machine.add_node(state_name, carry_tree)
			continue
		if state_name == MOVE:
			state_machine.add_node(state_name, _make_locomotion_tree())
			continue
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
	set_locomotion(Vector2(0, 1), 1.0)


func set_locomotion(direction: Vector2, cycles_per_second: float) -> void:
	animation_tree.set("parameters/move/Direction/blend_position", direction)
	animation_tree.set("parameters/move/Pace/scale", clampf(cycles_per_second, 0.1, 5.0))
	animation_tree.set("parameters/carry_move/Pace/scale", clampf(cycles_per_second, 0.1, 5.0))


func _make_locomotion_tree() -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	var directions := AnimationNodeBlendSpace2D.new()
	# Synchronized loops preserve the planted/swinging foot when turning.
	directions.sync = true
	var clips := [&"move", &"move_back", &"move_left", &"move_right"]
	var points := [Vector2(0, 1), Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0)]
	for i in clips.size():
		var node := AnimationNodeAnimation.new()
		node.animation = clips[i]
		directions.add_blend_point(node, points[i], -1, clips[i])
	tree.add_node(&"Direction", directions)
	tree.add_node(&"Pace", AnimationNodeTimeScale.new())
	tree.connect_node(&"Pace", 0, &"Direction")
	tree.connect_node(&"output", 0, &"Pace")
	return tree


func _make_directional_move(direction: Vector2) -> Animation:
	var animation := _make_move()
	# Re-author thigh swing in travel direction, keeping knee flexion anatomical.
	# Lift happens during the first half-cycle for the left leg and second for right.
	for side in ["L", "R"]:
		var bone := LEFT_UPPER_LEG if side == "L" else RIGHT_UPPER_LEG
		var track := animation.find_track(NodePath(".:%s" % bone), Animation.TYPE_ROTATION_3D)
		animation.remove_track(track)
		var sign_value := 1.0 if side == "L" else -1.0
		var start := _rotation(-22.0 * direction.y * sign_value, 0, 18.0 * direction.x * sign_value)
		var end := _rotation(22.0 * direction.y * sign_value, 0, -18.0 * direction.x * sign_value)
		_add_rotation(animation, bone, [0.0, 0.5, 1.0], [start, end, start])
	return animation


func _make_idle() -> Animation:
	var animation := _new_animation(2.0, true)
	_add_rotation(animation, CHEST, [0.0, 1.0, 2.0], [_rotation(0.0, 0.0, -1.0), _rotation(-2.4, 0.0, 1.5), _rotation(0.0, 0.0, -1.0)])
	_add_rotation(animation, HEAD, [0.0, 1.0, 2.0], [_rotation(0.0, -1.0, 0.0), _rotation(0.8, 1.0, 0.0), _rotation(0.0, -1.0, 0.0)])
	_add_grip(animation)
	return animation


func _make_tactical_pose(pose: StringName) -> Animation:
	# Blocking poses: knee flexion stays negative on this imported rig.
	# Root travel is supplied by the tactical path, never by these clips.
	var landing := pose == &"land"
	var animation := _new_animation(0.3 if landing else 0.8, not landing)
	var crouch := 0.10 if pose == &"cover_low" else 0.012
	var thigh := 30.0 if pose == &"cover_low" else 10.0
	var knee := -60.0 if pose == &"cover_low" else -20.0
	if pose in [&"vault", &"climb", &"descend", &"land"]:
		crouch = 0.10
		thigh = 45.0
		knee = -80.0
	if pose == &"descend":
		crouch = 0.05
		thigh = 25.0
		knee = -55.0
	var end := animation.length
	var times := [0.0, end * 0.5, end]
	_add_position(animation, HIPS, times, [Vector3(0, -crouch, 0), Vector3(0, -crouch - 0.015, 0), Vector3.ZERO if landing else Vector3(0, -crouch, 0)])
	for side in ["L", "R"]:
		var upper := LEFT_UPPER_LEG if side == "L" else RIGHT_UPPER_LEG
		var lower := LEFT_LOWER_LEG if side == "L" else RIGHT_LOWER_LEG
		var foot := LEFT_FOOT if side == "L" else RIGHT_FOOT
		var alternating := pose in [&"climb", &"descend"]
		var a := thigh * (0.35 if alternating and side == "R" else 1.0)
		var b := thigh * (0.35 if alternating and side == "L" else 1.0)
		_add_rotation(animation, upper, times, [_rotation(a, 0, 0), _rotation(b, 0, 0), Quaternion.IDENTITY if landing else _rotation(a, 0, 0)])
		_add_rotation(animation, lower, times, [_rotation(knee, 0, 0), _rotation(knee * 0.8, 0, 0), Quaternion.IDENTITY if landing else _rotation(knee, 0, 0)])
		_add_rotation(animation, foot, times, [_rotation(-a - knee, 0, 0), _rotation(-b - knee * 0.8, 0, 0), Quaternion.IDENTITY if landing else _rotation(-a - knee, 0, 0)])
	_add_rotation(animation, CHEST, [0.0], [_rotation(-5, 12, -6) if pose == &"cover_high" else _rotation(-8, 0, 0)])
	_add_grip(animation)
	return animation

func _make_rescue_pose(pose: StringName) -> Animation:
	var moving := pose == &"carry_move"
	var animation := _make_move() if moving else _new_animation(0.6, pose == &"carry_idle")
	if moving:
		animation.remove_track(animation.find_track(NodePath(".:%s" % CHEST), Animation.TYPE_ROTATION_3D))
	var times := [0.0, 0.3, 0.6]
	var angles := [-10.0, -12.0, -10.0]
	if pose == &"pickup":
		angles = [-5.0, -35.0, -10.0]
	elif pose == &"boarding":
		angles = [-10.0, -30.0, -5.0]
	if moving:
		times = [0.0, 0.5, 1.0]
	_add_rotation(animation, CHEST, times, [_rotation(angles[0], 0, 0), _rotation(angles[1], 0, 0), _rotation(angles[2], 0, 0)])
	if not moving:
		_add_grip(animation)
	for side in ["L", "R"]:
		var sign_value := -1.0 if side == "L" else 1.0
		_add_rotation(animation, StringName("J_Bip_%s_UpperArm" % side), [0.0], [_rotation(-20, 0, 45 * sign_value)])
		_add_rotation(animation, StringName("J_Bip_%s_LowerArm" % side), [0.0], [_rotation(-65, 0, 0)])
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

