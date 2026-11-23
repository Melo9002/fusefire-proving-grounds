extends SceneTree
## Normal-speed rendered review of the actual exploration controller. Pass
## small, unarmed, front or three-quarter as user args (default: MIRA armed, side).
## Also runs headless for final-skeleton contact measurements.
const PLAYGROUND := preload("res://research/exploration_playground/exploration_playground.tscn")
var _world: Node
var _diagnostic: ContactErrorDiagnostics
var _sheet_path := ""
var _tiles: Array[Image] = []
var _capture_ascent := true
var _metrics := {"frames": 0, "deck_foot_frames": 0, "deck_foot_max_error_mm": 0.0, "brace_frames": 0, "brace_and_foot_frames": 0, "unreachable_braces": 0, "unsupported_frames": 0, "worst_knee_below_deck_mm": 0.0}

func _initialize() -> void:
	_run.call_deferred()

func _sample(sample: Dictionary) -> void:
	var state: LadderClimb = _world.visual.rig.ladder
	if state == null or state.pose == null or state.climbed < TraversalSolver.landing_start(state.geometry, state.body) or state.pose.weight < 0.95 or sample.feet.size() != 2 or sample.hands.size() != 2:
		return
	_metrics.frames += 1
	var deck_foot := false
	var hand_support := false
	var rung_foot := false
	var deck_brace := false
	var rig: CharacterRig = _world.visual.rig
	var deck_edge := float(_world.traversal.ladder.deck_edge)
	var deck_y := float(_world.traversal.ladder.length)
	for side in 2:
		var foot: Dictionary = sample.feet[side]
		var hand: Dictionary = sample.hands[side]
		var leg := rig.bones.left_leg if side == 0 else rig.bones.right_leg
		var knee := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(leg[1])).origin
		if knee.z > deck_edge:
			_metrics.worst_knee_below_deck_mm = maxf(float(_metrics.worst_knee_below_deck_mm), (deck_y - knee.y) * 1000.0)
		if not is_nan(state.deck_from_rungs) and state.pose.foot_rung[side] < 0 and float(foot.error) < 0.05:
			deck_foot = true
		if state.pose.foot_rung[side] < 0:
			_metrics.deck_foot_max_error_mm = maxf(float(_metrics.deck_foot_max_error_mm), float(foot.error) * 1000.0)
		elif is_zero_approx(state.pose.foot_swing[side]) and float(foot.error) < 0.05:
			rung_foot = true
		if float(hand.weight) > 0.9 and float(hand.error) < 0.035:
			hand_support = true
			if not is_nan(state.deck_from_rungs) and state.pose.hand_deck[side] > 0.99:
				deck_brace = true
		if state.pose.hand_deck[side] > 0.99 and state.pose.hand_weight[side] > 0.9 and float(hand.weight) < 0.9:
			_metrics.unreachable_braces += 1
			if OS.get_cmdline_user_args().has("reach-detail"):
				var arm := rig.bones.left_arm if side == 0 else rig.bones.right_arm
				var shoulder := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(arm[0])).origin
				var offset := rig.character_root.to_global(state.pose.hands[side]) - shoulder
				print("limited brace t=%.3f %s offset %s (%.3f m / %.3f m)" % [state.pose.landing_phase, side, offset, offset.length(), state.body.arm_length()])
	if deck_foot:
		_metrics.deck_foot_frames += 1
	if deck_brace:
		_metrics.brace_frames += 1
		if deck_foot:
			_metrics.brace_and_foot_frames += 1
	if not deck_foot and not rung_foot and not hand_support:
		_metrics.unsupported_frames += 1

func _capture_if_needed() -> void:
	if not _capture_ascent or _sheet_path.is_empty() or _tiles.size() >= 5:
		return
	var phase := float(_world.traversal.climbed)
	var rise := float(_world.traversal.ladder.length)
	var progress := float(_world.body.global_position.z) - float(_world.traversal.ladder.z)
	var ready := [phase > rise - 0.63, phase > rise - 0.36, phase > rise - 0.09, progress > 0.32, progress > 0.64]
	if not ready[_tiles.size()]:
		return
	await RenderingServer.frame_post_draw
	var tile := root.get_texture().get_image()
	tile.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	tile.convert(Image.FORMAT_RGBA8)
	_tiles.append(tile)

func _wait_for_exit() -> bool:
	var deadline := create_timer(8.0)
	while _world.traversal.on_ladder and deadline.time_left > 0.0:
		await process_frame
		await _capture_if_needed()
	return not _world.traversal.on_ladder

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("sheet="):
			_sheet_path = arg.trim_prefix("sheet=")
	_world = PLAYGROUND.instantiate()
	root.add_child(_world)
	current_scene = _world
	await create_timer(0.35).timeout
	if args.has("small"):
		_world._select_character(1)
	if args.has("unarmed"):
		_world.toggle_weapon()
	_world.hint_label.hide()
	_world.state_label.hide()
	_world.yaw = PI if args.has("front") else (-2.25 if args.has("three-quarter") else -PI * 0.5)
	_world.zoom = 2.85
	_world._apply_camera_rotation()
	_world.body.global_position = _world.traversal.ladder_foot()
	await create_timer(0.6).timeout
	_diagnostic = ContactErrorDiagnostics.attach(_world.visual.rig)
	if _diagnostic == null:
		quit(1)
		return
	for layer: String in ContactErrorDiagnostics.LAYERS:
		_diagnostic.set_layer(layer, false)
	_diagnostic.sampled.connect(_sample)
	_diagnostic.set_enabled(true)
	_world.traversal.use_landing_contacts = not args.has("legacy")
	_world.traversal.mount()
	Input.action_press(&"playground_forward")
	if args.has("interrupt-acquire") or args.has("interrupt-release"):
		var after := float(_world.traversal.ladder.length) - 0.50
		var deadline := create_timer(8.0)
		while deadline.time_left > 0.0 and _world.traversal.on_ladder:
			await process_frame
			if args.has("interrupt-acquire") and _world.traversal.climbed > after:
				break
			if args.has("interrupt-release") and _world.body.global_position.z > float(_world.traversal.ladder.top_z) - 0.19:
				break
		var interrupted: bool = _world.traversal.on_ladder
		Input.action_release(&"playground_forward")
		_world.traversal.dismount_bottom()
		await create_timer(0.25).timeout
		var settled: bool = not _world.visual.is_climbing() and not _world.visual.rig.traversal_contacts_active() and not _world.visual.rig.is_weapon_stowed()
		print("ladder interruption ", args, ": ", interrupted and settled)
		quit(0 if interrupted and settled else 1)
		return
	var ascended := await _wait_for_exit()
	_capture_ascent = false
	Input.action_release(&"playground_forward")
	print("ladder ascent ", args, ": ", _metrics)
	await create_timer(0.65).timeout
	if not ascended or not _world.traversal.can_mount():
		quit(1)
		return
	for key: String in _metrics:
		_metrics[key] = 0
	_world.traversal.mount()
	Input.action_press(&"playground_back")
	var descended := await _wait_for_exit()
	Input.action_release(&"playground_back")
	print("ladder descent ", args, ": ", _metrics)
	if not _tiles.is_empty():
		var sheet := Image.create(640 * _tiles.size(), 360, false, Image.FORMAT_RGBA8)
		for index in _tiles.size():
			sheet.blit_rect(_tiles[index], Rect2i(0, 0, 640, 360), Vector2i(index * 640, 0))
		sheet.save_png(_sheet_path)
	await create_timer(0.6).timeout
	quit(0 if descended else 1)
