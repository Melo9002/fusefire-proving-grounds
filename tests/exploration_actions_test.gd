extends SceneTree
## The sandbox's action packages, driven through the real playground (Task 08 follow-up proof of concept): aim and shoot with a mannequin and its health bar, cover, ladder, jump, stairs and ramp, carrying a body, and
## the player's health, defeat and respawn screen. Each package is a section; positions and the camera are set the way a player would be (the camera looks along the movement direction).
const PLAYGROUND := "res://research/exploration_playground/exploration_playground.tscn"
var failures := 0
var checks := 0
var world: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _press(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)

func _place(position: Vector3, camera_yaw: float) -> void:
	world.body.global_position = position
	world.body.velocity = Vector3.ZERO
	world.yaw = camera_yaw
	world.pitch = 0.0
	world._apply_camera_rotation()
	world.pivot_position = world._focus_point()

func _check_cover_release(label: String) -> void:
	var rig: CharacterRig = world.visual.rig
	var before := rig.cover_yaw()
	var facing := rig.global_rotation.y
	check(absf(before) > deg_to_rad(25.0), "%s takes a real sideways cover pose" % label)
	world._cover_or_jump()
	check(absf(angle_difference(before, rig.cover_yaw())) < 0.001, "%s leaves cover without snapping" % label)
	var eased := false
	for frame in 15:
		await process_frame
		var yaw := absf(rig.cover_yaw())
		eased = eased or (yaw > deg_to_rad(1.0) and yaw < absf(before) - deg_to_rad(1.0))
	check(eased, "%s passes through an intermediate cover yaw" % label)
	await _wait(0.5)
	check(absf(angle_difference(rig.character_root.global_rotation.y, facing)) < deg_to_rad(2.0),
		"%s settles on the exploration host's facing" % label)

func _run() -> void:
	world = load(PLAYGROUND).instantiate()
	root.add_child(world)
	current_scene = world
	await _wait(1.0)

	# ---- Aim and shoot: the rifle comes up, a shot hits the mannequin, its bar goes down, it reacts, at zero it goes down and is rebuilt.
	var target: PlaygroundTarget = world.get_children().filter(func(n): return n is PlaygroundTarget)[0]
	_place(Vector3(target.global_position.x - 0.45, 0.0, target.global_position.z + 5.0), 0.0)
	await _wait(1.0)
	world.combat.set_aim(true)
	await _wait(0.8)
	check(world.visual.is_aiming() and world.visual.rig.aim_blend > 0.9 and world.combat.crosshair.visible, "Right mouse raises the rifle and shows the crosshair (aim blend %.2f)" % world.visual.rig.aim_blend)
	var aim_point: Vector3 = world.combat.aim_point()
	check(aim_point.distance_to(target.global_position + Vector3(0, 1.2, 0)) < 1.2, "The crosshair ray meets the mannequin (%s)" % [aim_point])
	world.combat.fire()
	await _wait(0.5)
	check(target.health < 100.0 and absf(target.bar._fill.scale.x - target.health / 100.0) < 0.01, "A hit lowers its health bar (%.0f)" % target.health)
	var reaction := target.host.get_presentation_state()
	check(reaction == &"hit" or target.host.presenter.is_holding(), "The mannequin plays its hit reaction (%s)" % reaction)
	for i in 8:
		if target.is_down():
			break
		await _wait(1.3)
		world.combat.fire()
	await _wait(1.0)
	check(target.is_down() and target.host.is_defeated() and target.host.get_presentation_state() == &"defeat", "At zero health the mannequin plays its takedown")
	await _wait(PlaygroundTarget.RESPAWN_SECONDS + 0.5)
	check(not target.is_down() and target.health == 100.0 and not target.host.is_defeated(), "...and it is rebuilt standing with full health a few seconds later")
	world.combat.set_aim(false)
	await _wait(0.5)
	check(not world.visual.is_aiming() and world.visual.rig.aim_blend < 0.2 and not world.combat.crosshair.visible, "Releasing the button lowers the rifle")

	# ---- Cover (Mass Effect 2 style): snap to a low wall, crouch, slide along it, pop up to aim, step out; a high wall leans around the edge.
	_place(Vector3(0.0, 0.0, 0.0), 0.0)
	await _wait(0.3)
	check(not world.cover.can_enter(), "Away from any wall there is no cover to take")
	_place(Vector3(-8.0, 0.0, 3.0), 0.0)
	await _wait(0.4)
	check(world.cover.can_enter(), "Near a wall, cover can be taken")
	world._cover_or_jump()
	await _wait(1.2)
	check(world.cover.active and world.visual.is_in_cover() and absf(world.body.global_position.z - 2.65) < 0.1, "Space snaps her to the wall (z %.2f)" % world.body.global_position.z)
	check(world.visual.rig.crouch_modifier.depth > 0.05 and world.visual.get_presentation_state() == &"cover_low", "She crouches behind it (depth %.2f m, %s)" % [world.visual.rig.crouch_modifier.depth, world.visual.get_presentation_state()])
	var before_x: float = world.body.global_position.x
	_press(&"playground_right", true)
	await _wait(0.8)
	_press(&"playground_right", false)
	check(absf(world.body.global_position.x - before_x) > 0.5 and absf(world.body.global_position.z - 2.65) < 0.1, "A and D slide her along the wall, staying at it (moved %.2f m)" % (world.body.global_position.x - before_x))
	var low_depth: float = world.visual.rig.crouch_modifier.depth
	world.combat.set_aim(true)
	await _wait(1.0)
	check(world.visual.rig.aim_blend > 0.9 and world.visual.rig.crouch_modifier.depth < low_depth - 0.02, "Aiming pops her up over the low wall (depth %.2f to %.2f m)" % [low_depth, world.visual.rig.crouch_modifier.depth])
	world.combat.set_aim(false)
	await _wait(0.5)
	await _check_cover_release("MIRA exploration")
	await _wait(0.8)
	check(not world.cover.active and not world.visual.is_in_cover() and world.visual.rig.crouch_modifier.depth < 0.05, "Space again leaves cover and she stands")
	await _wait(1.0)
	check(absf(world.visual.rig.character_root.rotation.y) < deg_to_rad(2.0), "After leaving cover her body is square to her facing again, not left turned along the wall (%.1f degrees)" % rad_to_deg(world.visual.rig.character_root.rotation.y))
	world.combat.set_aim(true)
	await _wait(0.8)
	var aim_yaw := absf(angle_difference(world.visual.rig.character_root.global_rotation.y, atan2(world.combat.aim_point().x - world.body.global_position.x, world.combat.aim_point().z - world.body.global_position.z)))
	check(rad_to_deg(aim_yaw) < 5.0, "...and aiming afterwards points her at the crosshair, not sideways (%.1f degrees off)" % rad_to_deg(aim_yaw))
	world.combat.set_aim(false)
	_place(Vector3(7.0, 0.0, 4.0), 0.0)
	await _wait(0.4)
	world._cover_or_jump()
	await _wait(1.0)
	check(world.visual.is_in_cover() and world.visual.get_presentation_state() == &"cover_high" and bool(world.visual._cover.full), "A high wall is full cover (%s)" % world.visual.get_presentation_state())
	world.cover.leave()
	await _wait(0.5)

	# ---- Jump (a placeholder: the body goes up and comes down).
	_place(Vector3(-15.0, 0.0, -15.0), 0.0)
	await _wait(0.5)
	world._cover_or_jump()
	var peak := 0.0
	for i in 40:
		await process_frame
		peak = maxf(peak, world.body.global_position.y)
	await _wait(1.0)
	check(peak > 0.5 and world.body.is_on_floor() and world.body.global_position.y < 0.1, "Space with no wall near jumps and she lands (peak %.2f m)" % peak)

	# ---- Stairs: she walks up the treads onto the deck and back down; the stair pose plants her feet while she is on them.
	_place(Vector3(-12.0, 0.0, 4.6), PI)
	await _wait(0.5)
	_press(&"playground_forward", true)
	var on_stairs_seen := false
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 9000 and world.body.global_position.z < 10.5:
		await process_frame
		on_stairs_seen = on_stairs_seen or (world.traversal.on_stairs and world.visual.is_on_stairs())
	_press(&"playground_forward", false)
	await _wait(0.8)
	check(on_stairs_seen, "Walking up the staircase puts her on the stairs (the stair pose runs)")
	check(absf(world.body.global_position.y - 2.0) < 0.15 and world.body.is_on_floor() and not world.traversal.on_stairs, "She arrives on the deck at its height (y %.2f)" % world.body.global_position.y)
	_place(Vector3(-12.0, 2.0, 10.4), 0.0)
	await _wait(0.5)
	_press(&"playground_forward", true)
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 9000 and world.body.global_position.z > 4.8:
		await process_frame
	_press(&"playground_forward", false)
	await _wait(0.8)
	check(absf(world.body.global_position.y) < 0.15 and world.body.is_on_floor(), "...and back down to the floor (y %.2f)" % world.body.global_position.y)

	# ---- The stairs retain contact solving while crouched; a held run stays capped.
	_place(Vector3(-12.0, 0.0, 4.4), PI)
	world.visual.set_crouched(true)
	await _wait(0.8)
	_press(&"playground_forward", true)
	_press(&"playground_run", true)
	var deepest_crouch := 0.0
	var fastest := 0.0
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 9000 and world.body.global_position.z < 8.0:
		await process_frame
		if world.traversal.on_stairs and Time.get_ticks_msec() - started > 1500:
			deepest_crouch = maxf(deepest_crouch, world.visual.rig.crouch_modifier.depth)
			fastest = maxf(fastest, Vector3(world.body.get_real_velocity().x, 0.0, world.body.get_real_velocity().z).length())
	_press(&"playground_forward", false)
	_press(&"playground_run", false)
	check(world.traversal.on_stairs and deepest_crouch > 0.2, "A crouch stays active on the stairs (deepest crouch %.2f m)" % deepest_crouch)
	check(fastest < world.MOVE_SPEED + 0.3, "A held run is walked on the stairs (%.2f m/s)" % fastest)
	world.visual.set_crouched(false)
	await _wait(0.3)
	var contacts := ContactErrorDiagnostics.attach(world.visual.rig)
	contacts.set_enabled(true)
	contacts.start_recording()
	_press(&"playground_left", true)
	await _wait(0.38)
	_press(&"playground_left", false)
	var lateral := contacts.stop_recording()
	var swung := false
	for sample in contacts.history:
		for foot: Dictionary in sample.feet:
			swung = swung or (foot.weight > 0.9 and not foot.planted)
	print("  lateral stair contacts: ", lateral)
	check(world.traversal.on_stairs and swung, "Crossing a tread alternates a lifted step instead of only sliding planted targets")
	contacts.set_enabled(false)
	contacts.queue_free()
	var jump_y: float = world.body.global_position.y
	world._cover_or_jump()
	await _wait(0.20)
	check(not world.traversal.on_stairs and not world.visual.is_on_stairs() and world.body.global_position.y > jump_y + 0.3, "Jump detaches stair IK and lifts above the tread")
	await _wait(0.9)
	check(world.traversal.on_stairs and world.visual.is_on_stairs(), "Landing on the flight restores stair contacts")
	_place(Vector3(-12.0, 0.0, 3.0), 0.0)
	await _wait(0.6)
	# The treads are solid from the side: walking into them does not go through.
	_place(Vector3(-10.4, 0.0, 6.6), PI * 0.5)
	await _wait(0.5)
	_press(&"playground_forward", true)
	await _wait(1.8)
	_press(&"playground_forward", false)
	check(world.body.global_position.x > -11.2 and not world.traversal.on_stairs, "The staircase has collision: walking into its side stops her (x %.2f)" % world.body.global_position.x)

	# ---- Ramp: a plain collider.
	_place(Vector3(7.5, 0.0, 8.0), -PI * 0.5)
	await _wait(0.5)
	_press(&"playground_forward", true)
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 9000 and world.body.global_position.x < 14.5:
		await process_frame
	_press(&"playground_forward", false)
	await _wait(0.6)
	check(world.body.global_position.y > 1.3 and world.body.is_on_floor(), "She walks up the ramp onto the platform (y %.2f)" % world.body.global_position.y)

	# ---- Ladder: E at its foot mounts, W climbs with her hands on the rungs, and at the top she steps onto the tower.
	_place(Vector3(0.0, 0.0, 14.4), PI)
	await _wait(0.5)
	check(world.traversal.can_mount() and world._prompt_text() == "Press E to climb", "At the foot of the ladder E offers to climb")
	world.interact()
	await _wait(0.5)
	check(world.traversal.on_ladder and world.visual.is_climbing(), "E mounts the ladder")
	check(float(world.traversal.ladder.z) - world.body.global_position.z >= 0.35, "The mount starts on the near side of the fixed rung plane")
	_press(&"playground_forward", true)
	await _wait(1.5)
	var mid_height: float = world.body.global_position.y
	var hands: float = world.visual.rig.ladder.pose.hand_weight[0] if world.visual.rig.ladder != null and world.visual.rig.ladder.pose != null else 0.0
	check(mid_height > 0.8 and mid_height < 2.2 and hands > 0.5, "W climbs and her hands take the rungs (height %.2f m, hand weight %.2f)" % [mid_height, hands])
	started = Time.get_ticks_msec()
	var saw_landing_step := false
	var saw_braced_lead := false
	while Time.get_ticks_msec() - started < 8000 and world.traversal.on_ladder:
		await process_frame
		saw_landing_step = saw_landing_step or (world.visual.is_climbing() and world.body.global_position.z > float(world.traversal.ladder.z) + 0.1 and world.body.global_position.z < float(world.traversal.ladder.top_z) - 0.1)
		var climb: LadderClimb = world.visual.rig.ladder
		if climb != null and climb.pose != null:
			saw_braced_lead = saw_braced_lead or (climb.pose.foot_deck[0] > 0.99 and climb.pose.foot_rung[0] < 0 and climb.pose.hand_deck[0] > 0.99 and climb.pose.hand_weight[0] > 0.9)
	_press(&"playground_forward", false)
	await _wait(0.8)
	check(not world.traversal.on_ladder and not world.visual.is_climbing() and absf(world.body.global_position.y - 3.0) < 0.15 and world.body.is_on_floor(), "At the top she steps onto the tower (y %.2f)" % world.body.global_position.y)
	check(saw_landing_step, "Top-out crosses the landing approach over multiple frames")
	check(saw_braced_lead, "Lead foot acquires the deck while a hand brace is still active")
	check(world.traversal.can_mount() and world.interact(), "E can enter the ladder from the deck")
	_press(&"playground_back", true)
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 8000 and world.traversal.on_ladder:
		await process_frame
	_press(&"playground_back", false)
	check(not world.visual.is_climbing() and world.body.global_position.y < 0.15, "Reverse entry returns control on the floor")

	# ---- Carry a body: E lifts it (the rescue lift), she walks loaded and slower, E puts it down and it stays lying.
	_place(Vector3(8.0, 0.0, -4.5), PI)
	await _wait(0.5)
	check(world.carry.can_pick_up() and world._prompt_text() == "Press E to lift the body", "Near the body E offers to lift it")
	world.interact()
	await _wait(4.2)
	check(world.visual.is_carrying() and not world.carry.busy and world.visual.get_presentation_state() == &"carry_idle", "The lift completes and she carries the body (%s)" % world.visual.get_presentation_state())
	_press(&"playground_forward", true)
	await _wait(1.2)
	var speed := Vector3(world.body.get_real_velocity().x, 0.0, world.body.get_real_velocity().z).length()
	_press(&"playground_forward", false)
	check(speed > 0.5 and speed < 1.1 and world.visual.get_presentation_state() == &"carry_move", "She walks loaded and slower (%.2f m/s, %s)" % [speed, world.visual.get_presentation_state()])
	await _wait(0.8)
	world.interact()
	await _wait(3.6)
	check(not world.visual.is_carrying() and is_instance_valid(world.carry.prop), "E puts the body down and it stays lying there to be lifted again")

	# ---- Health, defeat and the respawn screen: the red plate hurts, each hit reacts, at zero she goes down and a screen offers a respawn.
	_place(Vector3(14.0, 0.0, -12.0), 0.0)
	await _wait(1.0)
	check(world.player_health.health < 100.0 and world.player_health.bar.value < 100.0, "Standing on the red plate lowers her health bar (%.0f)" % world.player_health.health)
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 9000 and not world.dead:
		await process_frame
	await _wait(0.6)
	check(world.dead and world.visual.is_defeated() and world.visual.get_presentation_state() == &"defeat", "At zero health she is defeated (%s)" % world.visual.get_presentation_state())
	await _wait(PlaygroundPlayerHealth.SCREEN_DELAY + 0.5)
	check(world.player_health.screen.visible, "A respawn screen appears")
	world.player_health.screen.find_child("RespawnButton", true, false).pressed.emit()
	await _wait(1.2)
	check(not world.dead and world.player_health.health == 100.0 and not world.visual.is_defeated() and not world.player_health.screen.visible, "Respawn restores her health and she stands again")
	var spawn_flat: Vector3 = world.body.global_position
	spawn_flat.y = 0.0
	check(spawn_flat.length() < 1.0, "...at the spawn point (%s)" % [world.body.global_position])

	# The same real wall interaction after switching to the second model.
	world._select_character(1)
	check(world.character_index == 1, "The exploration host switches to Small MIRA")
	_place(Vector3(-8.0, 0.0, 3.0), 0.0)
	await _wait(0.4)
	world._cover_or_jump()
	await _wait(0.4)
	check(world.cover.active, "Small MIRA enters exploration cover")
	_press(&"playground_right", true)
	await _wait(0.4)
	_press(&"playground_right", false)
	await _wait(0.4)
	await _check_cover_release("Small MIRA exploration")

	print("Exploration actions: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
