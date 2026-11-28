extends SceneTree
## The loaded ladder in the real Exploration Playground (animation assignment), for every carrier/passenger pairing: the two selectors are independent, the casualty keeps its own identity through lift, carry, climb,
## descent and put-down, the climb waits for the passenger to be moved into the climbing carry before the body moves (at the foot AND at the head of the ladder), the ordinary carry returns afterwards, and nothing is left behind.
## Driven the way a player drives it: the pickers' code paths, E, W and S. Real time (a few minutes for four pairings).
const PLAYGROUND := "res://research/exploration_playground/exploration_playground.tscn"
const IDS := [&"mira_0", &"small_mira_0"]   # the playground's own characters, in its picker order

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


func _run() -> void:
	world = load(PLAYGROUND).instantiate()
	root.add_child(world)
	current_scene = world
	await _wait(1.0)
	await _selectors_are_independent()
	for carrier in IDS.size():
		for passenger in IDS.size():
			await _pairing(carrier, IDS[passenger])
	print("loaded_ladder_playground_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)


## The controlled character is chosen on its own: neither default casualty follows it, and both lie at the station from the start.
func _selectors_are_independent() -> void:
	world._select_character(0)
	await _wait(0.4)
	check(world.carry.casualties.size() == 2 and world.carry.find(&"casualty_mira").character_id == IDS[0] and world.carry.find(&"casualty_small_mira").character_id == IDS[1], "Both default casualties lie at the station, each its own model")
	world._select_character(1)
	await _wait(0.4)
	check(world.character_index == 1 and world.carry.find(&"casualty_mira").character_id == IDS[0] and world.carry.find(&"casualty_small_mira").character_id == IDS[1], "Choosing the carrier changes neither casualty")
	for casualty in world.carry.casualties:
		var model: Node3D = casualty.node.find_child("PassengerModel", true, false)
		check(model != null and is_equal_approx(model.scale.x, casualty.definition.scale), "%s keeps its own scale (%.2f), not the carrier's" % [casualty.id, model.scale.x if model != null else -1.0])


## Where a carrier stands to pick `character`'s default casualty up, facing it.
func _station_spot(character: StringName) -> Vector3:
	return Vector3(6.5, 0.0, -5.2) if character == IDS[0] else Vector3(9.5, 0.0, -5.2)


## Holds `action` until the ladder has taken her (or `limit` ms pass).
func _walk_until_on_ladder(action: StringName, limit := 3000) -> void:
	_press(action, true)
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < limit and not world.traversal.on_ladder:
		await process_frame


func _pairing(carrier_index: int, passenger: StringName) -> void:
	var label := "%s carries %s" % [IDS[carrier_index], passenger]
	world._select_character(carrier_index)
	world.carry.reset_all()
	await _wait(0.6)
	var casualty: PlaygroundCasualty = world.carry.find(&"casualty_mira" if passenger == IDS[0] else &"casualty_small_mira")
	var other: PlaygroundCasualty = world.carry.find(&"casualty_small_mira" if passenger == IDS[0] else &"casualty_mira")
	check(world.character_index == carrier_index and casualty.character_id == passenger, "%s: the carrier and the casualty are the two chosen" % label)
	var definition := PassengerDefinition.for_character(passenger)

	# ---- Lift: the body that lies there is the one that is lifted.
	_place(_station_spot(passenger), PI)
	await _wait(0.5)
	var body_before: Node = casualty.node
	check(world.carry.target() == casualty, "%s: standing at its body, it is the one E would lift" % label)
	world.interact()
	await _wait(4.3)
	var rig: CharacterRig = world.visual.rig
	check(world.visual.is_carrying() and not world.carry.busy, "%s: the lift completes" % label)
	check(is_instance_valid(rig.carry_passenger) and rig.carry_passenger.definition.character_id == passenger and is_equal_approx(rig.carry_passenger.find_child("PassengerModel", true, false).scale.x, definition.scale), "%s: the carried body is the casualty, at its own scale" % label)
	check(not is_instance_valid(body_before) or body_before.is_queued_for_deletion(), "%s: the ground body is gone, so there are not two bodies for one casualty" % label)
	check(other.is_grounded() and is_instance_valid(other.node) and other.node.visible, "%s: the other casualty is still lying at the station" % label)

	# ---- Up the ladder, from its foot.
	check(world.traversal.place_at_approach(false), "%s: the foot-of-ladder shortcut places the carrier" % label)
	await _wait(0.6)
	check(world.traversal.can_mount(), "%s: a loaded carrier at the foot is in the mounting zone" % label)
	await _wait(0.3)
	check(not world.traversal.on_ladder, "%s: standing at the foot does not mount" % label)
	await _walk_until_on_ladder(&"playground_forward")
	await _wait(0.05)
	check(world.traversal.on_ladder and rig.ladder != null and rig.loaded_ladder != null, "%s: walking at the ladder mounts it with the loaded presentation" % label)
	var held := true
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 700 and not rig.loaded_ladder_ready():
		await process_frame
		held = held and world.body.global_position.y < 0.02
	check(held, "%s: W waits while the passenger is moved onto the back (the body did not rise during the transfer)" % label)
	await _wait(1.8)
	check(world.body.global_position.y > 0.5 and rig.loaded_ladder != null and rig.loaded_ladder.blend > 0.999, "%s: then it climbs, the passenger in the climbing carry (%.2f m)" % [label, world.body.global_position.y])
	check(rig.carry_passenger.definition.character_id == passenger, "%s: the casualty is still itself on the ladder" % label)
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 12000 and world.traversal.on_ladder:
		await process_frame
	_press(&"playground_forward", false)
	check(not world.traversal.on_ladder and absf(world.body.global_position.y - 3.0) < 0.15, "%s: she steps onto the tower (y %.2f)" % [label, world.body.global_position.y])
	await _wait(2.2)
	check(world.visual.is_carrying() and rig.loaded_ladder == null and rig.carry_passenger.pose_blend > 0.999, "%s: the ordinary carry is back, nothing left of the transfer" % label)
	check(rig.carry_passenger.ladder_blend == 0.0 and rig.carry_passenger.landing_tuck == 0.0, "%s: the passenger is across the shoulders again" % label)

	# ---- Down, from the head of the ladder.
	check(world.traversal.can_mount(), "%s: the ladder can be entered from the deck, loaded" % label)
	await _walk_until_on_ladder(&"playground_back")
	await _wait(0.05)
	check(world.traversal.on_ladder, "%s: walking toward the ladder from the deck enters it" % label)
	var top: Vector3 = world.body.global_position
	held = true
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 900 and not rig.loaded_ladder_ready():
		await process_frame
		held = held and world.body.global_position.distance_to(top) < 0.03
	check(held, "%s: S waits at the head of the ladder until the passenger is in the climbing carry" % label)
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 14000 and world.traversal.on_ladder:
		await process_frame
	_press(&"playground_back", false)
	check(not world.traversal.on_ladder and world.body.global_position.y < 0.15, "%s: the descent hands control back on the floor" % label)
	await _wait(2.2)
	check(world.visual.is_carrying() and rig.loaded_ladder == null and rig.carry_passenger.ladder_blend == 0.0, "%s: the ordinary carry is back at the bottom" % label)

	# ---- Put down: the same body lies there, still itself.
	_place(Vector3(8.0, 0.0, -2.0), PI)
	await _wait(0.4)
	world.interact()
	await _wait(3.8)
	check(not world.visual.is_carrying() and casualty.is_grounded() and casualty.node.definition.character_id == passenger and world.carry.carried == null, "%s: put down, the casualty lies there and is still itself" % label)
	check(is_equal_approx(casualty.node.find_child("PassengerModel", true, false).scale.x, definition.scale), "%s: and still at its own scale" % label)
	check(world.carry.can_reset(), "%s: nothing is left locked" % label)
