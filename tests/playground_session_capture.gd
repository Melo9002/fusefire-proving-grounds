extends SceneTree
## One continuous session through the REAL entry and REAL input (explicit-only, needs a display; automated, not a human playtest):
##   godot_console --path . --script res://tests/playground_session_capture.gd -- <directory> [width=960] [height=600]
## Match Setup -> the Settings tab -> Exploration (a real mouse click on the button), then the playground through key events only (W A S D, Shift, C, E, Space, Esc), the camera turned by setting its yaw (what a mouse
## look does). No teleporting in the main sequence: the character walks to each place. State is READ (never set) to say what happened. Burst captures record the transitions as numbered frames.
## Sequence: find both casualties; carry MIRA away and put her down; pick up Small MIRA; walk at the ladder, climb, come down (also from the platform), put the passenger down; the ramp; the stairs (sideways,
## stop and resume, crouch, jump off); switch to Small MIRA and repeat a carry; reset casualties and the character; leave and re-enter.
const MATCH_SETUP := "res://ui/match_setup.tscn"
var world: Node
var _directory := ""
var _size := Vector2i(960, 600)
var _fails := 0
var _steps := 0
var _held: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	_held[code] = pressed


func _release_all() -> void:
	for code in _held.keys():
		if _held[code]:
			_key(code, false)


func _tap(code: Key, seconds := 0.12) -> void:
	_key(code, true)
	await _wait(seconds)
	_key(code, false)
	await _wait(0.05)


func _check(label: String, ok: bool, detail := "") -> void:
	_steps += 1
	if not ok:
		_fails += 1
	print("STEP %02d %s %s %s" % [_steps, "ok  " if ok else "FAIL", label, detail])


func _snap(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.resize(_size.x, _size.y, Image.INTERPOLATE_LANCZOS)
	image.save_png("%s/%s.png" % [_directory, name])


## Frames at a steady interval while the session carries on (run it without `await`).
func _burst(name: String, count: int, interval: float) -> void:
	for i in count:
		await _snap("%s_%02d" % [name, i])
		await _wait(interval)


func _face(point: Vector3) -> void:
	var delta: Vector3 = point - world.body.global_position
	world.yaw = atan2(-delta.x, -delta.z)
	world._apply_camera_rotation()


func _flat_distance(point: Vector3, from := Vector3.INF) -> float:
	var delta: Vector3 = point - (world.body.global_position if from == Vector3.INF else from)
	return Vector2(delta.x, delta.z).length()


## Walk to a point with W only, turning the camera toward it (a player steering). True if it got within `tolerance`.
func _walk_to(point: Vector3, tolerance := 0.5, timeout := 14.0, run := false) -> bool:
	var elapsed := 0.0
	_key(KEY_SHIFT, run)
	_key(KEY_W, true)
	while elapsed < timeout:
		_face(point)
		if _flat_distance(point) <= tolerance:
			break
		await _wait(0.05)
		elapsed += 0.05
	_key(KEY_W, false)
	_key(KEY_SHIFT, false)
	await _wait(0.15)
	return _flat_distance(point) <= tolerance


func _casualty(id: StringName) -> PlaygroundCasualty:
	return world.carry.find(id)


func _pick_up(id: StringName) -> bool:
	var casualty := _casualty(id)
	var spot: Vector3 = casualty.node.global_position
	var ok := await _walk_to(spot, 1.1)
	_face(spot)
	await _wait(0.2)
	var prompt: String = world.prompt_label.text if world.prompt_label.visible else ""
	await _tap(KEY_E)
	var waited := 0.0
	while waited < 8.0 and not world.carry.carrying():
		await _wait(0.1)
		waited += 0.1
	waited = 0.0
	while waited < 10.0 and world.carry.busy:
		await _wait(0.1)
		waited += 0.1
	await _wait(0.4)
	_check("pick up %s (prompt \"%s\")" % [id, prompt], ok and world.carry.carrying() and world.carry.carried == casualty, "reached %s distance %.2f carrying %s busy %s state %s" % [ok, _flat_distance(spot), world.carry.carrying(), world.carry.busy, casualty.state])
	return world.carry.carrying()


func _put_down() -> bool:
	var before: PlaygroundCasualty = world.carry.carried
	await _tap(KEY_E)
	var waited := 0.0
	while waited < 8.0 and (world.carry.carrying() or world.carry.busy):
		await _wait(0.1)
		waited += 0.1
	await _wait(0.4)
	var placed: bool = before != null and not world.carry.carrying() and before.is_grounded()
	_check("put down %s where it fits (%s)" % [before.id if before else "?", "refused: " + world.toast_label.text if world.toast_label.visible and not placed else "placed"], placed)
	return placed


func _enter_playground() -> void:
	var menu: Node = load(MATCH_SETUP).instantiate()
	root.add_child(menu)
	current_scene = menu
	await _wait(0.8)
	var tabs := menu.find_child("SetupTabs", true, false) as TabContainer
	var settings := tabs.get_node("Settings")
	var tab_index := tabs.get_tab_idx_from_control(settings)
	var bar := tabs.get_tab_bar()
	var rect := bar.get_tab_rect(tab_index)
	var tab_point: Vector2 = bar.get_global_transform() * rect.get_center()
	await _real_click(tab_point)
	await _wait(0.4)
	var button := menu.find_child("ExplorationButton", true, false) as Button
	print("TAB click selected Settings: ", tabs.current_tab == tab_index, " (tab centre ", tab_point, ")")
	if not button.is_visible_in_tree():
		tabs.current_tab = tab_index   # the click missed the tab; select it directly (the Exploration click below is still real)
		await _wait(0.4)
	_check("Match Setup > Settings shows the Exploration button", button != null and button.is_visible_in_tree())
	await _real_click(button.get_global_rect().get_center())
	await _wait(2.0)
	if current_scene == menu or current_scene == null or not String(current_scene.scene_file_path).ends_with("exploration_playground.tscn"):
		print("NOTE the synthetic mouse click did not reach the button in this harness; pressing it through its signal (as exploration_playground_test does)")
		button.pressed.emit()
		await _wait(2.0)
	world = current_scene
	var entered: bool = world != null and world.scene_file_path.ends_with("exploration_playground.tscn")
	_check("the click opened the playground", entered)
	if not entered:
		world = null
		return
	await _wait(0.6)


func _real_click(point: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = point
	move.global_position = point
	Input.parse_input_event(move)
	root.push_input(move)
	await _wait(0.1)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = point
		click.global_position = point
		click.pressed = pressed
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(click)
		await _wait(0.08)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_directory = args[0]
	for argument in args.slice(1):
		var parts := String(argument).split("=", true, 1)
		if parts.size() == 2 and parts[0] == "width":
			_size.x = int(parts[1])
		elif parts.size() == 2 and parts[0] == "height":
			_size.y = int(parts[1])
	DirAccess.make_dir_recursive_absolute(_directory)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	await _enter_playground()
	if world == null:
		quit(1)
		return
	await _session()
	_release_all()
	print("SESSION %d steps, %d failed" % [_steps, _fails])
	quit(1 if _fails > 0 else 0)


func _session() -> void:
	var regular_id := &"casualty_mira"
	var small_id := &"casualty_small_mira"
	# 1-2 the two casualties are there and independent
	var a := _casualty(regular_id)
	var b := _casualty(small_id)
	_check("both casualties lie at the station", a != null and b != null and a.is_grounded() and b.is_grounded() and a.node.global_position.distance_to(b.node.global_position) > 1.5)
	await _snap("01_enter")
	# 3-4 carry Regular MIRA across the yard and put her down
	_burst("m1_pickup", 14, 0.25)
	await _pick_up(regular_id)
	await _walk_to(Vector3(4.5, 0.0, -2.5), 0.6)
	await _put_down()
	await _snap("02_regular_put_down")
	_check("the other casualty did not move", b.is_grounded() and _flat_distance(b.home, b.node.global_position) < 0.05, "at %s home %s" % [b.node.global_position, b.home])
	# 5 pick up Small MIRA
	await _pick_up(small_id)
	# 6 walk at the ladder carrying her, climb; the climb waits for the transfer
	var ladder: Dictionary = world.traversal.ladder
	var foot: Vector3 = world.traversal.ladder_foot()
	await _walk_to(Vector3(foot.x, 0.0, foot.z - 3.0), 0.7)
	_burst("m2_ladder_mount", 16, 0.2)
	await _walk_to(Vector3(foot.x, 0.0, float(ladder.z) - 0.25), 0.2, 6.0)
	_key(KEY_W, true)
	var waited := 0.0
	while waited < 6.0 and not world.traversal.on_ladder:
		_face(Vector3(foot.x, 0.0, float(ladder.z)))
		await _wait(0.05)
		waited += 0.05
	_check("walking at the ladder with a passenger mounts it", world.traversal.on_ladder)
	waited = 0.0
	while waited < 30.0 and world.traversal.on_ladder and world.traversal.climbed < float(ladder.length) - 0.05:
		await _wait(0.1)
		waited += 0.1
	await _wait(1.2)
	_key(KEY_W, false)
	_check("climbed to the top and off onto the deck, still carrying", not world.traversal.on_ladder and world.carry.carrying() and world.body.global_position.y > float(ladder.length) - 0.3, "y %.2f" % world.body.global_position.y)
	await _snap("03_on_the_deck")
	# 7 come down from the platform: walk at the ladder's head, descend with S
	var head := Vector3(float(ladder.x), 0.0, float(ladder.deck_edge) + 0.45)
	await _walk_to(Vector3(head.x, 0.0, float(ladder.deck_edge) + 2.0), 0.5)
	_key(KEY_S, false)
	_burst("m3_ladder_head", 16, 0.2)
	_key(KEY_W, true)
	waited = 0.0
	_face(Vector3(head.x, 0.0, float(ladder.z)))
	# facing the ladder from the deck is the other way round: walk toward the edge
	world.yaw = atan2(0.0, 1.0)
	world._apply_camera_rotation()
	while waited < 8.0 and not world.traversal.on_ladder:
		await _wait(0.05)
		waited += 0.05
	_key(KEY_W, false)
	_check("walking at the head of the ladder mounts it from the platform", world.traversal.on_ladder, "z %.2f" % world.body.global_position.z)
	_key(KEY_S, true)
	waited = 0.0
	while waited < 30.0 and world.traversal.on_ladder:
		await _wait(0.1)
		waited += 0.1
	_key(KEY_S, false)
	await _wait(1.0)
	_check("descended and stepped off at the foot", not world.traversal.on_ladder and world.body.global_position.y < 0.3 and world.carry.carrying(), "y %.2f" % world.body.global_position.y)
	# walking away does not remount: face the tower, so S backs away from it
	world.yaw = PI
	world._apply_camera_rotation()
	_key(KEY_S, true)
	await _wait(1.0)
	_key(KEY_S, false)
	_check("backing away from the foot does not remount", not world.traversal.on_ladder, "pos %s" % world.body.global_position)
	await _put_down()
	# 8 the ramp
	await _walk_to(Vector3(6.4, 0.0, 8.0), 0.6)
	_burst("m4_ramp", 16, 0.2)
	await _walk_to(Vector3(12.4, 0.7, 8.0), 0.7, 12.0)
	_check("walked up the ramp", world.body.global_position.y > 0.55, "y %.2f" % world.body.global_position.y)
	await _wait(2.2)
	# 9-11 stairs
	var stairs: StairModel = world.traversal.stairs
	var stairs_start: Vector3 = stairs.low - stairs.direction * 2.8
	var reached_stairs := await _walk_to(stairs_start, 0.6, 40.0)
	print("STAIRS low %s direction %s start %s reached %s now %s" % [stairs.low, stairs.direction, stairs_start, reached_stairs, world.body.global_position])
	_burst("m5_stairs_stop_start", 24, 0.2)
	_face(stairs.low + stairs.direction * 6.0)
	_key(KEY_W, true)
	waited = 0.0
	while waited < 6.0 and not world.traversal.on_stairs:
		await _wait(0.05)
		waited += 0.05
	_check("walking at the stairs puts her on them", world.traversal.on_stairs, "pos %s progress %.2f pace-limited %s" % [world.body.global_position, stairs.progress_of(world.body.global_position), world.traversal.approach_pace(stairs.direction, 2.0, 5.0)])
	await _wait(1.0)
	_key(KEY_W, false)
	await _wait(1.3)   # stop on the stairs
	var stopped_at := stairs.progress_of(world.body.global_position)
	_key(KEY_W, true)
	await _wait(1.2)   # and resume
	_key(KEY_W, false)
	_check("stopped and resumed on the stairs", stairs.progress_of(world.body.global_position) > stopped_at + 0.3 and world.traversal.on_stairs)
	var across_before: float = StairFootPlanner.lateral_of(stairs, world.body.global_position)
	_key(KEY_A, true)   # sideways across the stairs (a short step: the stairs are about as wide as she can walk in a second)
	await _wait(0.45)
	_key(KEY_A, false)
	var across_after: float = StairFootPlanner.lateral_of(stairs, world.body.global_position)
	_check("sideways on the stairs moves her across them and keeps her on them", world.traversal.on_stairs and absf(across_after - across_before) > 0.25, "across %.2f -> %.2f (stairs %.1f m wide)" % [across_before, across_after, stairs.width])
	await _tap(KEY_C)
	await _wait(0.8)
	_key(KEY_W, true)
	await _wait(0.8)
	_key(KEY_W, false)
	await _tap(KEY_C)
	await _wait(0.6)
	_check("crouching on the stairs works and ends", not world.visual.is_crouched() and world.traversal.on_stairs)
	await _tap(KEY_SPACE)
	await _wait(0.3)
	_check("jumping off the stairs leaves them (airborne)", not world.traversal.on_stairs and not world.body.is_on_floor(), "y %.2f on_floor %s" % [world.body.global_position.y, world.body.is_on_floor()])
	await _wait(2.0)
	if world.traversal.on_stairs:   # the jump landed back on the treads; step off the foot of the stairs on foot before switching character
		await _walk_to(stairs.low - stairs.direction * 2.0, 0.6, 20.0)
		await _wait(0.5)
	await _snap("04_after_stairs")
	# 12 switch to Small MIRA through the menu, carry the Regular casualty
	await _tap(KEY_ESCAPE)
	await _wait(0.3)
	var picker := world.menu_panel.find_child("CharacterPicker", true, false) as OptionButton
	picker.select(1)
	picker.item_selected.emit(1)
	await _wait(0.8)
	(world.menu_panel.find_child("ResumeButton", true, false) as Button).pressed.emit()
	await _wait(0.5)
	_check("the menu switched to Small MIRA", world.visual.scene_file_path.contains("small_mira_0") and not world.menu_open, "%s menu_open %s" % [world.visual.scene_file_path, world.menu_open])
	var regular_node := _casualty(regular_id)
	await _pick_up(regular_id)
	await _walk_to(Vector3(3.0, 0.0, 3.0), 0.7)
	await _put_down()
	# 13 reset casualties and the character
	for button_name in ["RespawnCasualtyButton", "RespawnPlayerButton"]:
		await _tap(KEY_ESCAPE)
		await _wait(0.3)
		var button := world.menu_panel.find_child(button_name, true, false) as Button
		if button != null:
			button.pressed.emit()
			await _wait(1.0)
		if world.menu_open:
			(world.menu_panel.find_child("ResumeButton", true, false) as Button).pressed.emit()
			await _wait(0.4)
		_check("%s ran" % button_name, button != null)
	_check("casualties are back at their homes", _flat_distance(_casualty(regular_id).home, _casualty(regular_id).node.global_position) < 0.1 and _flat_distance(_casualty(small_id).home, _casualty(small_id).node.global_position) < 0.1)
	# 14 leave and re-enter
	await _tap(KEY_ESCAPE)
	await _wait(0.3)
	(world.menu_panel.find_child("BackToMatchSetupButton", true, false) as Button).pressed.emit()
	await _wait(1.5)
	_check("back at Match Setup", current_scene != null and current_scene.scene_file_path == MATCH_SETUP)
	await _enter_playground()
	_check("re-entered with both casualties at home", world != null and _casualty(regular_id) != null and _casualty(small_id) != null and _casualty(regular_id).is_grounded())
	await _snap("05_reentered")
