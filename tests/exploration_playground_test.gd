extends SceneTree
## The experimental Exploration playground (Task 03 companion): reachable from Match Setup, playable with no tactical state, and able to return. This is a headless test of
## behaviour driven through the real input actions; it says nothing about how the sandbox LOOKS (that needs a human at a window). Uses the production MIRA visual, so it also
## documents what the existing presentation does outside combat (the Task 03 host probe was retired into tests/exploration_host_test.gd).
const MATCH_SETUP := "res://ui/match_setup.tscn"
const PLAYGROUND := "res://research/exploration_playground/exploration_playground.tscn"
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _has_tactical_nodes() -> bool:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is TacticalUnit:
			return true
		stack.append_array(node.get_children())
	return false

func _press(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)

func _run() -> void:
	# ---- Match Setup exposes the entry point and it opens the playground (no battle is started).
	var menu: Node = load(MATCH_SETUP).instantiate()
	root.add_child(menu)
	current_scene = menu
	await _frames(3)
	var button := menu.find_child("ExplorationButton", true, false) as Button
	check(button != null and button.text == "Exploration", "Match Setup shows an Exploration button")
	check(menu.find_child("ParcelEditorButton", true, false) != null and menu.get("start_button") != null, "The existing Parcel Editor and Start controls are still there")
	if button == null:
		print("Exploration playground: %d checks, %d failure(s)" % [checks, failures])
		quit(1)
		return
	button.pressed.emit()
	await _frames(8)
	var world: Node = current_scene
	check(world != null and world.scene_file_path == PLAYGROUND, "Pressing Exploration opens the playground scene (%s)" % [world.scene_file_path if world else "none"])
	if world == null or world.scene_file_path != PLAYGROUND:
		quit(1)
		return
	check(not _has_tactical_nodes(), "No TacticalUnit exists in the playground")
	check(world.visual.get("tactical_unit") == null, "MIRA's presentation has no tactical unit")
	await create_timer(1.2).timeout

	# ---- Idle, then walking forward relative to the camera (it starts behind MIRA, so forward is +Z).
	check(world.visual.get_presentation_state() == &"rifle_idle", "MIRA idles at the start (%s)" % world.visual.get_presentation_state())
	var start: Vector3 = world.body.global_position
	_press(&"playground_forward", true)
	await create_timer(1.6).timeout
	var travelled: Vector3 = world.body.global_position - start
	var speed: float = Vector3(world.body.get_real_velocity().x, 0.0, world.body.get_real_velocity().z).length()
	print("  forward: moved %.2f m, speed %.2f, state %s" % [travelled.length(), speed, world.visual.get_presentation_state()])
	check(travelled.z > 1.5 and absf(travelled.x) < 0.3, "W moves MIRA forward along the camera direction (%.2f, %.2f)" % [travelled.x, travelled.z])
	check(absf(speed - world.MOVE_SPEED) < 0.15, "Walking speed matches MOVE_SPEED (%.2f vs %.2f m/s)" % [speed, world.MOVE_SPEED])
	check(world.visual.get_presentation_state() == &"move", "The movement clip state plays while walking")
	check(float(world.visual.rig.locomotion_report.get("speed", 0.0)) > 1.0, "The gait presentation follows the real speed (%.2f)" % float(world.visual.rig.locomotion_report.get("speed", 0.0)))
	check(absf(rad_to_deg(angle_difference(world.visual.rig.global_rotation.y, 0.0))) < 10.0, "MIRA faces the movement direction")
	var focus: Vector3 = world.body.global_position + Vector3(0.0, 1.45, 0.0)
	var camera_distance: float = world.camera.global_position.distance_to(focus)
	check(camera_distance > 2.2 and camera_distance < 4.2, "The camera keeps following at a sensible distance while moving (%.2f m)" % camera_distance)
	check(world.camera.global_position.y > 0.3, "The camera stays above the floor")

	# ---- Diagonal movement is normalised.
	_press(&"playground_right", true)
	await create_timer(0.8).timeout
	var diagonal: float = Vector3(world.body.get_real_velocity().x, 0.0, world.body.get_real_velocity().z).length()
	check(absf(diagonal - world.MOVE_SPEED) < 0.15, "Diagonal movement is not faster (%.2f m/s)" % diagonal)
	_press(&"playground_right", false)
	_press(&"playground_forward", false)
	await create_timer(1.2).timeout
	var settled: float = float(world.visual.rig.locomotion_report.get("speed", 9.0))
	check(settled < 0.1 and world.visual.get_presentation_state() == &"rifle_idle", "Releasing the keys returns MIRA to idle (speed %.2f, state %s)" % [settled, world.visual.get_presentation_state()])

	# ---- Shift runs (the presenter derives the faster gait from the reported speed), C crouches and stands, Q holsters and draws the rifle (MIRA is rebuilt in place).
	_press(&"playground_forward", true)
	_press(&"playground_run", true)
	await create_timer(1.6).timeout
	var run_speed: float = Vector3(world.body.get_real_velocity().x, 0.0, world.body.get_real_velocity().z).length()
	check(run_speed > world.MOVE_SPEED * 2.5 and world.visual.presenter.speed > 3.5 and world.visual.get_presentation_state() == &"move", "Holding Shift runs (%.2f m/s, presenter speed %.2f)" % [run_speed, world.visual.presenter.speed])
	_press(&"playground_run", false)
	_press(&"playground_forward", false)
	await create_timer(1.2).timeout
	_press(&"playground_crouch", true)
	_press(&"playground_crouch", false)
	await create_timer(1.2).timeout
	check(world.visual.is_crouched() and world.visual.rig.crouch_modifier.depth > 0.2, "C crouches MIRA through the presenter's posture request (%.2f m)" % world.visual.rig.crouch_modifier.depth)
	_press(&"playground_crouch", true)
	_press(&"playground_crouch", false)
	await create_timer(1.5).timeout
	check(not world.visual.is_crouched() and world.visual.rig.crouch_modifier.depth < 0.02, "C again stands her up")
	var facing_before: float = world.visual.rig.rotation.y
	_press(&"playground_weapon", true)
	_press(&"playground_weapon", false)
	await create_timer(0.8).timeout
	check(not world.armed and not world.visual.rig.has_weapon() and world.visual.rig.equipment_state() == PresentationTypes.EquipmentState.NONE and absf(angle_difference(world.visual.rig.rotation.y, facing_before)) < 0.01, "Q holsters the rifle: the same character rebuilt with no weapon, facing kept")
	_press(&"playground_forward", true)
	await create_timer(1.0).timeout
	_press(&"playground_forward", false)
	check(world.visual.get_presentation_state() == &"move" and float(world.visual.rig.locomotion_report.get("speed", 0.0)) > 1.0, "Unarmed MIRA walks through the same host")
	await create_timer(0.8).timeout
	_press(&"playground_weapon", true)
	_press(&"playground_weapon", false)
	await create_timer(0.8).timeout
	check(world.armed and world.visual.rig.has_weapon(), "Q again draws the rifle")

	# ---- Solid props block MIRA.
	world.body.global_position = Vector3(-3.0, 0.0, 1.0)
	world.body.velocity = Vector3.ZERO
	world.yaw = 0.0   # the camera now looks toward -Z, so W walks into the large crate (front face at z = -1.5)
	world._apply_camera_rotation()
	await _frames(4)
	_press(&"playground_forward", true)
	await create_timer(2.6).timeout
	_press(&"playground_forward", false)
	check(world.body.global_position.z > -1.6, "MIRA cannot walk through the crate (stopped at z = %.2f)" % world.body.global_position.z)
	await create_timer(0.6).timeout

	# ---- Camera: look, pitch limits, zoom, recenter, mouse capture.
	var yaw_before: float = world.yaw
	world.look(Vector2(100.0, 0.0))
	check(absf(angle_difference(world.yaw, yaw_before)) > 0.1, "Mouse movement turns the camera")
	world.look(Vector2(0.0, 100000.0))
	check(world.pitch >= deg_to_rad(world.PITCH_LIMITS_DEGREES.x) - 0.001 and world.pitch <= deg_to_rad(world.PITCH_LIMITS_DEGREES.y) + 0.001, "Pitch stays within its limits")
	world.look(Vector2(0.0, -100000.0))
	check(world.pitch <= deg_to_rad(world.PITCH_LIMITS_DEGREES.y) + 0.001, "Pitch stays within its upper limit")
	world.pitch = deg_to_rad(-12.0)
	world.zoom_by(-100.0)
	check(is_equal_approx(world.zoom, world.ZOOM_RANGE.x), "Zoom stops at the closest distance")
	world.zoom_by(100.0)
	check(is_equal_approx(world.zoom, world.ZOOM_RANGE.y), "Zoom stops at the farthest distance")
	world.zoom = world.DEFAULT_ZOOM
	var facing: float = world.visual.rig.global_rotation.y
	_press(&"playground_recenter", true)
	await create_timer(1.5).timeout
	_press(&"playground_recenter", false)
	check(absf(rad_to_deg(angle_difference(world.yaw, facing + PI))) < 6.0, "Right mouse recenters the camera behind MIRA")
	check(world.mouse_captured, "The mouse is captured while playing (requested; a headless run has no real mouse mode to read back)")

	# ---- Interaction: prompt only near the chair; E responds and MIRA turns toward it.
	check(not world.prompt_label.visible and not world.interact(), "Far from the chair there is no prompt and E does nothing")
	world.body.global_position = Vector3(3.0, 0.0, -1.8)
	world.body.velocity = Vector3.ZERO
	await _frames(6)
	check(world.prompt_label.visible and world.prompt_label.text == "Press E to interact", "Near the chair the prompt appears")
	var seat_before: Material = world.chair_seat.material_override
	_press(&"playground_interact", true)
	_press(&"playground_interact", false)
	await _frames(6)
	check(world.chair_seat.material_override != seat_before and world.toast_label.visible, "Pressing E gives a visible response (chair changes colour, a message shows)")
	var to_chair: Vector3 = world.chair_position - world.body.global_position
	check(absf(rad_to_deg(angle_difference(world.visual.rig.global_rotation.y, atan2(to_chair.x, to_chair.z)))) < 5.0, "MIRA turns toward the chair")
	check(world.visual.is_interacting(), "The interaction is a running presentation (inspecting)")
	await create_timer(2.4).timeout
	check(not world.visual.is_interacting() and world.toast_label.text == "Done inspecting", "The interaction completes by itself and the sandbox hears it (%s)" % world.toast_label.text)

	# ---- Falling out of the world is part of exploration mode: the body falls for a moment, then returns to the spawn point and the character forgets its motion.
	var respawns := []
	world.spawn_guard.respawned.connect(func(point: Node3D, position: Vector3) -> void: respawns.append(position))
	world.body.global_position = Vector3(22.0, 0.3, 4.0)   # past the platform's edge
	world.body.velocity = Vector3.ZERO
	var lowest: float = 0.0
	var started := Time.get_ticks_msec()
	while respawns.is_empty() and Time.get_ticks_msec() - started < 5000:
		await process_frame
		lowest = minf(lowest, world.body.global_position.y)
	check(lowest < -2.0 and respawns.size() == 1, "Walking off the platform lets MIRA fall, then returns her (lowest %.1f m)" % lowest)
	await create_timer(0.6).timeout
	var spawn_flat: Vector3 = world.body.global_position
	spawn_flat.y = 0.0
	check(spawn_flat.length() < 0.3 and world.body.is_on_floor() and world.body.get_real_velocity().length() < 0.5, "...at the spawn point, standing, with no leftover velocity (%s)" % [world.body.global_position])
	check(world.visual.get_presentation_state() == &"rifle_idle" and not world.visual.is_moving() and not world.visual.is_interacting(), "...and her presentation is idle again")
	world.body.global_position = Vector3(3.0, 0.0, -1.8)
	world.body.velocity = Vector3.ZERO
	await _frames(6)

	# ---- Movement does not depend on the frame rate: the same walk covers the same distance at 30 fps and at 240 fps.
	var distances := []
	for fps in [30, 240]:
		Engine.max_fps = fps
		world.body.global_position = Vector3(-15.0, 0.0, -15.0)
		world.body.velocity = Vector3.ZERO
		await create_timer(0.5).timeout
		var from: Vector3 = world.body.global_position
		_press(&"playground_forward", true)
		await create_timer(1.5).timeout
		_press(&"playground_forward", false)
		var moved: Vector3 = world.body.global_position - from
		moved.y = 0.0
		distances.append(moved.length())
		await create_timer(0.6).timeout
	Engine.max_fps = 0
	check(absf(distances[0] - distances[1]) < 0.25 * distances[1] and distances[0] > 1.0, "Walking covers the same distance at 30 and at 240 fps (%.2f m and %.2f m)" % [distances[0], distances[1]])

	# ---- Esc opens the menu and releases the mouse; Resume captures it again; Back returns to Match Setup.
	_press(&"ui_cancel", true)
	_press(&"ui_cancel", false)
	await _frames(3)
	check(world.menu_open and world.menu_panel.visible and not world.mouse_captured, "Esc releases the mouse and shows the menu")
	var held_position: Vector3 = world.body.global_position
	_press(&"playground_forward", true)
	await create_timer(0.5).timeout
	_press(&"playground_forward", false)
	check(world.body.global_position.distance_to(held_position) < 0.05, "MIRA does not move while the menu is open")
	var picker := world.menu_panel.find_child("CharacterPicker", true, false) as OptionButton
	check(picker != null and picker.item_count == 2, "The exploration menu offers both humanoid models")
	if picker != null:
		var was_armed: bool = world.armed
		picker.select(1)
		picker.item_selected.emit(1)
		await _frames(4)
		check(world.visual.scene_file_path.contains("small_mira_0") and world.armed == was_armed and world.body.global_position.distance_to(held_position) < 0.05, "Switching to Small MIRA preserves the body position and equipment")
		picker.select(0)
		picker.item_selected.emit(0)
		await _frames(4)
		check(not world.visual.scene_file_path.contains("small_mira_0"), "The menu can switch back to MIRA")
	(world.menu_panel.find_child("ResumeButton", true, false) as Button).pressed.emit()
	check(not world.menu_open and world.mouse_captured, "Resume closes the menu and captures the mouse")
	_press(&"ui_cancel", true)
	_press(&"ui_cancel", false)
	await _frames(2)
	(world.menu_panel.find_child("BackToMatchSetupButton", true, false) as Button).pressed.emit()
	await _frames(8)
	check(current_scene != null and current_scene.scene_file_path == MATCH_SETUP, "Back to Match Setup returns to the previous screen")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "The mouse is released on the menu")
	check(not InputMap.has_action(&"playground_forward") and not InputMap.has_action(&"playground_recenter"), "The playground's temporary input actions are removed on exit")
	check(current_scene.find_child("ExplorationButton", true, false) != null, "Match Setup still offers Exploration after returning")

	print("Exploration playground: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
