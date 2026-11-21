extends Node
## Edit saved poses in ../animations/animation_workbench.tscn.
## Saved library clips take precedence. Procedural safety-net recipes live in
## character_fallback_animation_builder.gd.
## Workflow and procedural timing: docs/animation-editing-guide.md.

const FALLBACK_BUILDER := preload("res://presentation/characters/rig/character_fallback_animation_builder.gd")

signal state_changed(state_name: StringName)

const IDLE := &"rifle_idle"
const MOVE := &"move"
const AIM := &"aim"
const SHOOT := &"shoot"
const HIT := &"hit"
const DEFEAT := &"defeat"
const FORWARD_GAIT_PARAMETER := "parameters/move/Direction/move/blend_position"
const STATES: Array[StringName] = [IDLE, MOVE, AIM, SHOOT, HIT, DEFEAT,
	&"cover_low", &"cover_high", &"shoot_left", &"shoot_right", &"vault", &"climb", &"descend", &"land",
	&"pickup", &"carry_idle", &"carry_move", &"boarding"]


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
## Locomotion gaits and thresholds (see LocomotionProfile); set before setup(). Null keeps the builder's defaults.
var locomotion_profile: LocomotionProfile
var _fallbacks: RefCounted


func setup(target_skeleton: Skeleton3D, target_visual_root: Node3D, rig_bones: RigBones) -> void:
	skeleton = target_skeleton
	_fallbacks = FALLBACK_BUILDER.new(skeleton, rig_bones)
	if locomotion_profile != null:
		_fallbacks.profile = locomotion_profile
	visual_root = target_visual_root
	_build_animation_player()
	_build_animation_tree()
	play(IDLE)


## The anatomical axes (skeleton space) the procedural clips are built on: up, forward (the way the toes point) and the hip hinge.
func locomotion_axes() -> RigAxes:
	return RigAxes.new(_fallbacks.anatomical_up(), _fallbacks.anatomical_forward(), _fallbacks.hip_hinge())


## How long the clip of a state is, seconds (0 when it has none). The one-shot states (hit, defeat) report their own length so a finite presentation does not repeat it as a constant.
func state_length(state_name: StringName) -> float:
	if animation_player == null or not animation_player.has_animation(state_name):
		return 0.0
	return animation_player.get_animation(state_name).length


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
		await get_tree().create_timer(float(step.seconds), false).timeout
	if generation == _sequence_generation:
		sequence_running = false


func _build_animation_player() -> void:
	animation_player = AnimationPlayer.new()
	animation_player.name = "VerticalSliceAnimationPlayer"
	skeleton.add_child(animation_player)
	animation_player.root_node = NodePath("..")

	var library := AnimationLibrary.new()
	library.add_animation(IDLE, _fallbacks._make_idle())
	library.add_animation(MOVE, _fallbacks._make_move())
	# The forward gaits the speed blend mixes with the walk, phase for phase (all are one-second loops that start at the left heel strike).
	library.add_animation(&"move_jog", _fallbacks.make_forward_clip(&"jog"))
	library.add_animation(&"move_run", _fallbacks.make_forward_clip(&"run"))
	library.add_animation(&"carry_move_fast", _fallbacks.make_forward_clip(&"loaded_fast"))
	library.add_animation(&"move_back", _fallbacks._make_directional_move(Vector2(0, -1)))
	# Direction x is toward the character's LEFT (see the contract in the animation builder).
	library.add_animation(&"move_left", _fallbacks._make_directional_move(Vector2(1, 0)))
	library.add_animation(&"move_right", _fallbacks._make_directional_move(Vector2(-1, 0)))
	library.add_animation(AIM, _fallbacks._make_aim())
	library.add_animation(SHOOT, _fallbacks._make_shoot())
	library.add_animation(HIT, _fallbacks._make_hit())
	library.add_animation(DEFEAT, _fallbacks._make_defeat())
	for pose in [&"pickup", &"carry_idle", &"carry_move", &"boarding"]:
		library.add_animation(pose, _fallbacks._make_rescue_pose(pose))
	for pose in [&"cover_low", &"cover_high", &"vault", &"climb", &"descend", &"land"]:
		library.add_animation(pose, _fallbacks._make_tactical_pose(pose))
	for side in [-1, 1]:
		var shot: Animation = _fallbacks.make_lean_shot(side)
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
	var reset: Animation = _fallbacks._new_animation(0.0, false)
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
				_fallbacks._add_rotation(reset, bone, [0.0], [Quaternion.IDENTITY])
			elif kind == Animation.TYPE_POSITION_3D:
				_fallbacks._add_position(reset, bone, [0.0], [Vector3.ZERO])
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
			var carry_gaits := AnimationNodeBlendSpace1D.new()
			carry_gaits.sync = true
			for entry in [[&"carry_move", 0.0], [&"carry_move_fast", 1.0]]:
				var carry_clip := AnimationNodeAnimation.new()
				carry_clip.animation = entry[0]
				carry_gaits.add_blend_point(carry_clip, entry[1], -1, entry[0])
			carry_tree.add_node(&"Gait", carry_gaits)
			carry_tree.add_node(&"Pace", AnimationNodeTimeScale.new())
			carry_tree.connect_node(&"Pace", 0, &"Gait")
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


## Speed blend for the forward walk (0 walk, 1 jog, 2 run) and the loaded one (0 loaded walk, 1 loaded trot). The gaits are phase-synchronised, so the
## weights can change at any moment without the feet jumping.
func set_gait(forward_blend: float, loaded_blend := 0.0) -> void:
	animation_tree.set(FORWARD_GAIT_PARAMETER, forward_blend)
	animation_tree.set("parameters/carry_move/Gait/blend_position", loaded_blend)


func _make_locomotion_tree() -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	var directions := AnimationNodeBlendSpace2D.new()
	# Synchronized loops preserve the planted/swinging foot when turning.
	directions.sync = true
	# Direction x is toward the character's LEFT (see the movement coordinate contract in the animation builder).
	var clips := [&"move", &"move_back", &"move_left", &"move_right"]
	var points := [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]
	for i in clips.size():
		var node: AnimationRootNode
		if clips[i] == &"move":
			# Forward travel is itself a blend of the walk, jog and run, chosen by speed.
			var gaits := AnimationNodeBlendSpace1D.new()
			gaits.sync = true
			for entry in [[&"move", 0.0], [&"move_jog", 1.0], [&"move_run", 2.0]]:
				var gait_clip := AnimationNodeAnimation.new()
				gait_clip.animation = entry[0]
				gaits.add_blend_point(gait_clip, entry[1], -1, entry[0])
			node = gaits
		else:
			var clip_node := AnimationNodeAnimation.new()
			clip_node.animation = clips[i]
			node = clip_node
		directions.add_blend_point(node, points[i], -1, clips[i])
	tree.add_node(&"Direction", directions)
	tree.add_node(&"Pace", AnimationNodeTimeScale.new())
	tree.connect_node(&"Pace", 0, &"Direction")
	tree.connect_node(&"output", 0, &"Pace")
	return tree


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
		# Only the lean axes return to zero. The visual root's YAW belongs to the character's cover posture (UnitVisualAdapter._cover_yaw, written
		# every frame); resetting it here fought that posture for as long as play() kept being called, then released it with a jump.
		_visual_tween.parallel().tween_property(visual_root, "rotation:x", 0.0, 0.14)
		_visual_tween.parallel().tween_property(visual_root, "rotation:z", 0.0, 0.14)
		_visual_tween.parallel().tween_property(visual_root, "position", Vector3.ZERO, 0.14)

